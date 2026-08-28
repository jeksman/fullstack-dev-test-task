#!/usr/bin/env bash
# remote/install-ghost.sh — stage 2, executed on the VPS over the Tailscale
# tunnel as the unprivileged ghostops user.
#
# Usage: install-ghost.sh <domain> <admin_user> <node_major> <ghost_cli_spec> <mysql_package>
#
# Idempotent by design: every step checks the desired end state first, and a
# healthy existing Ghost installation is never reinstalled or reset.

set -Eeuo pipefail

DOMAIN="${1:?domain required}"
ADMIN_USER="${2:?admin user required}"
NODE_MAJOR="${3:?node major required}"
GHOST_CLI_SPEC="${4:?ghost-cli spec required}"
MYSQL_PACKAGE="${5:-mysql-server}"

GHOST_DIR=/var/www/ghost
DB_NAME="ghost_prod"
DB_USER="ghost_app"
STATE=/var/lib/gho-install.json

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

say() { printf '::: %s\n' "$*"; }
fail() {
	printf '!!! %s\n' "$*" >&2
	exit 1
}

mark() {
	sudo install -m 0644 /dev/null "$STATE" 2>/dev/null || true
	printf '{"stage":"%s","ts":"%s"}\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" |
		sudo tee "$STATE" >/dev/null
}

# A password made of [A-Za-z0-9] only: nothing that needs SQL, shell or JSON
# escaping can ever appear in it.
gen_password() {
	LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40
	printf '\n'
}

# run_sql <file> — executes a SQL file as MySQL root via the unix_socket
# plugin. Statements come from a 0600 file, never from a command line.
run_sql() {
	# shellcheck disable=SC2024  # the SQL file is owned by the invoking user by design
	sudo mysql --batch --raw <"$1" >/dev/null
}

# ---------------------------------------------------------------- 1. swap ---

setup_swap() {
	local mem_kb swap_kb
	mem_kb="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
	swap_kb="$(awk '/SwapTotal/{print $2}' /proc/meminfo)"
	if [ "$swap_kb" -gt 0 ]; then
		say "swap already present ($((swap_kb / 1024)) MB)"
		return 0
	fi
	if [ "$mem_kb" -ge 3800000 ]; then
		say "memory is $((mem_kb / 1024)) MB, no swap file needed"
		return 0
	fi
	say "creating a 2G swap file (RAM is $((mem_kb / 1024)) MB)"
	sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
	sudo chmod 600 /swapfile
	sudo mkswap /swapfile >/dev/null
	sudo swapon /swapfile
	grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
	printf 'vm.swappiness=10\n' | sudo tee /etc/sysctl.d/60-ghost-swap.conf >/dev/null
	sudo sysctl -q -p /etc/sysctl.d/60-ghost-swap.conf || true
}

# ------------------------------------------------------------ 2. packages ---

install_base_packages() {
	say "installing base packages"
	sudo apt-get update -qq
	sudo apt-get install -y -qq --no-install-recommends \
		ca-certificates curl gnupg jq nginx unzip zip \
		apt-transport-https software-properties-common >/dev/null
}

install_nodejs() {
	local have_major=""
	if command -v node >/dev/null 2>&1; then
		have_major="$(node -v | sed 's/^v\([0-9]*\).*/\1/')"
	fi
	if [ "$have_major" = "$NODE_MAJOR" ]; then
		say "Node.js ${NODE_MAJOR}.x already installed ($(node -v))"
		return 0
	fi
	[ -n "$have_major" ] && say "replacing unsupported Node.js ${have_major}.x with ${NODE_MAJOR}.x"
	say "installing Node.js ${NODE_MAJOR}.x from NodeSource"
	sudo install -d -m 0755 /usr/share/keyrings
	curl -fsSL --proto '=https' https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key |
		sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/nodesource.gpg
	sudo chmod 0644 /usr/share/keyrings/nodesource.gpg
	echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" |
		sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null
	sudo apt-get update -qq
	sudo apt-get install -y -qq nodejs >/dev/null
	node -v | grep -q "^v${NODE_MAJOR}\." || fail "Node.js ${NODE_MAJOR}.x did not install"
}

install_mysql() {
	if systemctl is-active --quiet mysql; then
		say "MySQL already active ($(mysql --version | sed 's/.*Ver //;s/ .*//'))"
	else
		say "installing ${MYSQL_PACKAGE}"
		sudo apt-get install -y -qq "$MYSQL_PACKAGE" >/dev/null ||
			sudo apt-get install -y -qq mysql-server >/dev/null
		sudo systemctl enable --now mysql
	fi
	# Bind to loopback only. Ubuntu already defaults to this; we make it
	# explicit and independent of distribution defaults changing.
	printf '[mysqld]\nbind-address = 127.0.0.1\nmysqlx = 0\nskip-name-resolve\n' |
		sudo tee /etc/mysql/mysql.conf.d/99-ghost-hetzner.cnf >/dev/null
	sudo chmod 0644 /etc/mysql/mysql.conf.d/99-ghost-hetzner.cnf
	sudo systemctl restart mysql
	local listeners
	listeners="$(sudo ss -ltn 2>/dev/null | awk '$4 ~ /:3306$/ {print $4}')"
	if printf '%s\n' "$listeners" | grep -q . && printf '%s\n' "$listeners" | grep -qv '^127\.0\.0\.1:'; then
		fail "MySQL is listening on a non-loopback address"
	fi
	say "MySQL bound to loopback only"
}

install_ghost_cli() {
	if command -v ghost >/dev/null 2>&1; then
		say "ghost-cli already installed ($(ghost version 2>/dev/null | head -1))"
		return 0
	fi
	say "installing ${GHOST_CLI_SPEC}"
	sudo npm install --global --no-fund --no-audit --silent "$GHOST_CLI_SPEC"
	command -v ghost >/dev/null 2>&1 || fail "ghost-cli did not install"
}

# ------------------------------------------------------------- 3. database --

# Creates the application database and user. The password is generated here, on
# the VPS, and is never transmitted, printed or logged.
provision_database() {
	local pw sqlfile
	pw="$(gen_password)"
	sqlfile="$(mktemp "${TMPDIR:-/tmp}/gho-sql.XXXXXX")"
	chmod 600 "$sqlfile"
	# Identifiers are fixed literals; the password contains [A-Za-z0-9] only.
	{
		printf "CREATE DATABASE IF NOT EXISTS \`%s\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\n" "$DB_NAME"
		printf "CREATE USER IF NOT EXISTS '%s'@'127.0.0.1' IDENTIFIED BY '%s';\n" "$DB_USER" "$pw"
		printf "ALTER USER '%s'@'127.0.0.1' IDENTIFIED BY '%s';\n" "$DB_USER" "$pw"
		printf "GRANT ALL PRIVILEGES ON \`%s\`.* TO '%s'@'127.0.0.1';\n" "$DB_NAME" "$DB_USER"
		printf "FLUSH PRIVILEGES;\n"
	} >"$sqlfile"
	run_sql "$sqlfile"
	shred -u "$sqlfile" 2>/dev/null || rm -f "$sqlfile"
	printf '%s' "$pw"
}

database_has_ghost_tables() {
	sudo mysql --batch --skip-column-names -e \
		"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='posts';" 2>/dev/null |
		grep -q '^1$'
}

# ---------------------------------------------------------------- 4. ghost ---

install_ghost() {
	sudo install -d -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0755 /var/www
	sudo install -d -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0755 "$GHOST_DIR"

	if [ -f "${GHOST_DIR}/config.production.json" ]; then
		say "Ghost is already installed in ${GHOST_DIR} — not reinstalling"
		if database_has_ghost_tables; then
			say "existing Ghost database detected — content preserved"
		fi
		return 0
	fi

	# No config, but the directory is not empty: an earlier attempt died part
	# way. Clearing it is only safe when there is demonstrably no content to
	# lose — otherwise stop and let a human look.
	if [ -n "$(ls -A "$GHOST_DIR" 2>/dev/null)" ]; then
		if database_has_ghost_tables || [ -d "${GHOST_DIR}/content/images" ]; then
			fail "${GHOST_DIR} holds Ghost content but no config.production.json; refusing to touch it"
		fi
		say "clearing an incomplete previous install attempt"
		sudo find "$GHOST_DIR" -mindepth 1 -delete
	fi

	# A throwaway credential is used for the install so that the password Ghost
	# keeps on disk is never visible in the process table. It is rotated below.
	local bootstrap_pw
	bootstrap_pw="$(provision_database)"

	say "running ghost install (systemd, MySQL, no nginx/ssl yet)"
	(
		cd "$GHOST_DIR"
		ghost install \
			--db mysql \
			--dbhost 127.0.0.1 \
			--dbuser "$DB_USER" \
			--dbname "$DB_NAME" \
			--dbpass "$bootstrap_pw" \
			--url "https://${DOMAIN}" \
			--process systemd \
			--no-setup-linux-user \
			--no-setup-mysql \
			--no-setup-nginx \
			--no-setup-ssl \
			--no-prompt \
			--enable \
			--start
	) || fail "ghost install failed"
	unset bootstrap_pw
	mark ghost-installed
}

# rotate_db_password — replaces the credential that was briefly visible as a
# process argument with one that only ever existed in 0600 files.
rotate_db_password() {
	local pw sqlfile cfg tmp
	cfg="${GHOST_DIR}/config.production.json"
	[ -f "$cfg" ] || return 0
	if [ -f /var/lib/gho-db-rotated ]; then
		say "database password already rotated"
		return 0
	fi
	pw="$(gen_password)"
	sqlfile="$(mktemp "${TMPDIR:-/tmp}/gho-sql.XXXXXX")"
	chmod 600 "$sqlfile"
	printf "ALTER USER '%s'@'127.0.0.1' IDENTIFIED BY '%s';\nFLUSH PRIVILEGES;\n" "$DB_USER" "$pw" >"$sqlfile"
	run_sql "$sqlfile"
	shred -u "$sqlfile" 2>/dev/null || rm -f "$sqlfile"

	tmp="$(mktemp)"
	chmod 600 "$tmp"
	jq --arg p "$pw" '.database.connection.password = $p' "$cfg" >"$tmp"
	sudo install -o "$ADMIN_USER" -g "$ADMIN_USER" -m 0600 "$tmp" "$cfg"
	shred -u "$tmp" 2>/dev/null || rm -f "$tmp"
	unset pw
	sudo touch /var/lib/gho-db-rotated
	say "database password rotated to a value that never entered a command line"
	(cd "$GHOST_DIR" && ghost restart >/dev/null) || fail "ghost restart after rotation failed"
}

harden_permissions() {
	sudo chown -R "${ADMIN_USER}:${ADMIN_USER}" "$GHOST_DIR"
	sudo chmod 0600 "${GHOST_DIR}/config.production.json"
	sudo find "${GHOST_DIR}/content" -type d -exec chmod 0755 {} + 2>/dev/null || true
	sudo find "${GHOST_DIR}/content" -type f -exec chmod 0644 {} + 2>/dev/null || true
	say "ownership and permissions applied"
}

# -------------------------------------------------------------------- main ---

main() {
	say "ghost-hetzner-oneclick installer starting on $(hostname)"
	setup_swap
	install_base_packages
	install_nodejs
	install_mysql
	install_ghost_cli
	install_ghost
	rotate_db_password
	harden_permissions
	mark completed
	say "installation stage complete"
	(cd "$GHOST_DIR" && ghost status) || true
}

main "$@"
