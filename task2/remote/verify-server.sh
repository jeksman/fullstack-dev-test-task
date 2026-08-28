#!/usr/bin/env bash
# remote/verify-server.sh — server-side verification, machine readable.
# Usage: verify-server.sh <domain> <admin_user> <node_major>
#
# Prints a single JSON document to stdout:
#   {"checks":[{"name":..,"status":"PASS|FAIL|WARNING","detail":".."}],
#    "failed":N,"warnings":N}
# Detail strings are facts about configuration; no credential is ever emitted.

set -Eeuo pipefail

DOMAIN="${1:?domain required}"
ADMIN_USER="${2:?admin user required}"
NODE_MAJOR="${3:-22}"
GHOST_DIR=/var/www/ghost

FAILED=0
WARNINGS=0
FIRST=1

emit() {
	local name="$1" status="$2" detail="${3:-}"
	[ "$FIRST" = 1 ] || printf ',\n'
	FIRST=0
	# shellcheck disable=SC1003  # tr -d '"\\' strips quotes and backslashes
	printf '    {"name":"%s","status":"%s","detail":"%s"}' \
		"$name" "$status" "$(printf '%s' "$detail" | tr -d '"\\' | tr '\n' ' ')"
	[ "$status" = FAIL ] && FAILED=$((FAILED + 1))
	[ "$status" = WARNING ] && WARNINGS=$((WARNINGS + 1))
	return 0
}

# check <name> <detail> <command...>
check() {
	local name="$1" detail="$2"
	shift 2
	if "$@" >/dev/null 2>&1; then emit "$name" PASS "$detail"; else emit "$name" FAIL "$detail"; fi
}

ghost_unit() {
	systemctl list-units --type=service --all --no-legend 'ghost_*' 2>/dev/null |
		awk '{print $1}' | head -1
}

printf '{\n  "checks": [\n'

# --------------------------------------------------------------- runtime ----

if command -v node >/dev/null 2>&1; then
	NODE_V="$(node -v)"
	case "$NODE_V" in
	v${NODE_MAJOR}.*) emit node-version PASS "$NODE_V" ;;
	*) emit node-version FAIL "expected v${NODE_MAJOR}.x, found ${NODE_V}" ;;
	esac
else
	emit node-version FAIL "node not installed"
fi

if command -v ghost >/dev/null 2>&1; then
	emit ghost-cli-installed PASS "$(ghost version 2>/dev/null | head -1 | tr -d '"')"
else
	emit ghost-cli-installed FAIL "ghost-cli missing"
fi

# ----------------------------------------------------------------- mysql ----

check mysql-active "mysql.service" systemctl is-active --quiet mysql

MYSQL_LISTEN="$(ss -ltn 2>/dev/null | awk '$4 ~ /:3306$/ {print $4}' | paste -sd, -)"
if [ -z "$MYSQL_LISTEN" ]; then
	emit mysql-loopback-only WARNING "no listener found on 3306"
elif printf '%s' "$MYSQL_LISTEN" | grep -qv '^127\.0\.0\.1:'; then
	emit mysql-loopback-only FAIL "listening on ${MYSQL_LISTEN}"
else
	emit mysql-loopback-only PASS "${MYSQL_LISTEN}"
fi

# ----------------------------------------------------------------- nginx ----

check nginx-active "nginx.service" systemctl is-active --quiet nginx
check nginx-config-valid "nginx -t" sudo nginx -t

# ----------------------------------------------------------------- ghost ----

UNIT="$(ghost_unit)"
if [ -n "$UNIT" ]; then
	if systemctl is-active --quiet "$UNIT"; then emit ghost-service-active PASS "$UNIT"; else emit ghost-service-active FAIL "$UNIT not active"; fi
	if systemctl is-enabled --quiet "$UNIT"; then emit ghost-service-enabled PASS "$UNIT enabled at boot"; else emit ghost-service-enabled FAIL "$UNIT not enabled"; fi
	SVC_USER="$(systemctl show -p User --value "$UNIT" 2>/dev/null)"
	[ -n "$SVC_USER" ] || SVC_USER=root
	if [ "$SVC_USER" = root ]; then
		emit ghost-not-root FAIL "unit runs as root"
	else
		emit ghost-not-root PASS "runs as ${SVC_USER}"
	fi
else
	emit ghost-service-active FAIL "no ghost_* unit"
	emit ghost-service-enabled FAIL "no ghost_* unit"
	emit ghost-not-root FAIL "no ghost_* unit"
fi

GHOST_PROC_USER="$(ps -o user= -C node 2>/dev/null | sort -u | paste -sd, - || true)"
if printf '%s' "$GHOST_PROC_USER" | grep -qw root; then
	emit ghost-process-not-root FAIL "a node process runs as root"
else
	emit ghost-process-not-root PASS "node processes: ${GHOST_PROC_USER:-none}"
fi

if [ -f "${GHOST_DIR}/config.production.json" ]; then
	URL="$(sudo -u "$ADMIN_USER" jq -r '.url' "${GHOST_DIR}/config.production.json" 2>/dev/null || echo "")"
	case "$URL" in
	https://*) emit ghost-url-https PASS "$URL" ;;
	*) emit ghost-url-https FAIL "url is ${URL:-unset}" ;;
	esac
	PERM="$(stat -c %a "${GHOST_DIR}/config.production.json")"
	case "$PERM" in
	600 | 640) emit ghost-config-permissions PASS "mode ${PERM}" ;;
	*) emit ghost-config-permissions FAIL "mode ${PERM}" ;;
	esac
else
	emit ghost-url-https FAIL "no config.production.json"
	emit ghost-config-permissions FAIL "no config.production.json"
fi

if sudo -u "$ADMIN_USER" bash -lc "cd '${GHOST_DIR}' && ghost doctor" >/dev/null 2>&1; then
	emit ghost-doctor PASS "all checks passed"
else
	emit ghost-doctor WARNING "ghost doctor reported findings"
fi

if sudo -u "$ADMIN_USER" bash -lc "cd '${GHOST_DIR}' && ghost status" 2>/dev/null | grep -qi 'running'; then
	emit ghost-status-running PASS "ghost status reports running"
else
	emit ghost-status-running FAIL "ghost status does not report running"
fi

# -------------------------------------------------------- host firewall -----

if sudo ufw status verbose 2>/dev/null | grep -q 'Status: active'; then
	emit ufw-active PASS "ufw enabled"
else
	emit ufw-active FAIL "ufw not active"
fi

if sudo ufw status verbose 2>/dev/null | grep -q 'Default: deny (incoming)'; then
	emit ufw-default-deny PASS "default deny incoming"
else
	emit ufw-default-deny FAIL "incoming default is not deny"
fi

SSH_RULES="$(sudo ufw status 2>/dev/null | grep -E '(^|[[:space:]])22/tcp' || true)"
if [ -z "$SSH_RULES" ]; then
	emit ufw-ssh-tunnel-only FAIL "no SSH rule at all — the tunnel would break on reboot"
elif printf '%s\n' "$SSH_RULES" | grep -qv 'tailscale0'; then
	emit ufw-ssh-tunnel-only FAIL "an SSH rule exists that is not bound to tailscale0"
else
	emit ufw-ssh-tunnel-only PASS "22/tcp allowed on tailscale0 only"
fi

if sudo ufw status 2>/dev/null | grep -q '80/tcp' && sudo ufw status 2>/dev/null | grep -q '443/tcp'; then
	emit ufw-web-ports PASS "80/tcp and 443/tcp allowed"
else
	emit ufw-web-ports FAIL "web ports are not both allowed"
fi

if curl -fsS --max-time 15 -o /dev/null https://deb.nodesource.com/ 2>/dev/null ||
	curl -fsS --max-time 15 -o /dev/null https://api.github.com/ 2>/dev/null; then
	emit outbound-connectivity PASS "egress works"
else
	emit outbound-connectivity WARNING "could not verify egress"
fi

# ------------------------------------------------------------------ sshd ----

EFF="$(sudo sshd -T 2>/dev/null || true)"
for pair in "permitrootlogin no:sshd-no-root-login" \
	"passwordauthentication no:sshd-no-password-auth" \
	"permitemptypasswords no:sshd-no-empty-passwords" \
	"kbdinteractiveauthentication no:sshd-no-kbd-interactive"; do
	want="${pair%%:*}"
	name="${pair##*:}"
	if printf '%s\n' "$EFF" | grep -qi "^${want}$"; then
		emit "$name" PASS "${want}"
	else
		emit "$name" FAIL "effective sshd config does not set '${want}'"
	fi
done

REMOTE_USER="$(id -un)"
if [ "$REMOTE_USER" = "$ADMIN_USER" ]; then
	emit ssh-user-is-admin PASS "$REMOTE_USER"
else
	emit ssh-user-is-admin FAIL "connected as ${REMOTE_USER}"
fi

# ------------------------------------------------------------- tailscale ----

if systemctl is-active --quiet tailscaled; then
	emit tailscaled-active PASS "tailscaled running"
else
	emit tailscaled-active FAIL "tailscaled not running"
fi

TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"
if printf '%s' "$TS_IP" | grep -Eq '^100\.'; then
	emit tailscale-address PASS "$TS_IP"
else
	emit tailscale-address FAIL "no tailnet IPv4"
fi

# SSH_CONNECTION is "<client ip> <client port> <server ip> <server port>".
# The server-side address proves the session arrived over the tunnel.
DEST="$(printf '%s' "${SSH_CONNECTION:-}" | awk '{print $3}')"
if printf '%s' "$DEST" | grep -Eq '^100\.'; then
	emit ssh-arrived-over-tunnel PASS "server-side address ${DEST}"
elif [ -z "${SSH_CONNECTION:-}" ]; then
	emit ssh-arrived-over-tunnel WARNING "SSH_CONNECTION not set (not an interactive ssh session)"
else
	emit ssh-arrived-over-tunnel FAIL "server-side address ${DEST} is not a Tailscale address"
fi

# ----------------------------------------------------- automatic updates ----

if systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then
	emit auto-security-updates PASS "unattended-upgrades enabled"
else
	emit auto-security-updates FAIL "unattended-upgrades not enabled"
fi

# --------------------------------------------------- world-readable secrets --

LEAKY="$(sudo find /var/www/ghost /etc/ssh /root -maxdepth 2 \
	\( -name 'config.*.json' -o -name '*.key' -o -name 'id_*' -o -name '*authkey*' \) \
	-perm -o+r 2>/dev/null | paste -sd, - || true)"
if [ -n "$LEAKY" ]; then
	emit no-world-readable-secrets FAIL "world-readable: ${LEAKY}"
else
	emit no-world-readable-secrets PASS "none found"
fi

if sudo test -e /root/.gho-authkey || sudo test -e /run/gho-authkey; then
	emit bootstrap-key-destroyed FAIL "a Tailscale auth key file still exists"
else
	emit bootstrap-key-destroyed PASS "no auth key file remains"
fi

# ---------------------------------------------------------------- backups ---

if systemctl list-timers --all 2>/dev/null | grep -q ghost-backup.timer; then
	if systemctl is-enabled --quiet ghost-backup.timer; then
		emit backup-timer PASS "ghost-backup.timer enabled"
	else
		emit backup-timer WARNING "ghost-backup.timer present but not enabled"
	fi
fi

printf '\n  ],\n  "failed": %d,\n  "warnings": %d,\n  "domain": "%s"\n}\n' "$FAILED" "$WARNINGS" "$DOMAIN"

[ "$FAILED" -eq 0 ]
