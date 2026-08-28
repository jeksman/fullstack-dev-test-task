#!/usr/bin/env bash
# remote/configure-security.sh — host hardening, applied and then re-asserted.
# Usage: configure-security.sh <admin_user>
#
# Everything here is idempotent: it describes the desired end state and makes
# the machine match it, whether it is the first run or the fifth.

set -Eeuo pipefail

ADMIN_USER="${1:?admin user required}"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

say() { printf '::: %s\n' "$*"; }
fail() {
	printf '!!! %s\n' "$*" >&2
	exit 1
}

# ------------------------------------------------------------------ sshd ----

configure_sshd() {
	sudo tee /etc/ssh/sshd_config.d/10-ghost-hetzner.conf >/dev/null <<CONF
# ghost-hetzner-oneclick SSH hardening
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
AuthenticationMethods publickey
PubkeyAuthentication yes
AllowUsers ${ADMIN_USER}
X11Forwarding no
AllowAgentForwarding no
MaxAuthTries 3
LoginGraceTime 20
ClientAliveInterval 60
ClientAliveCountMax 3
CONF
	sudo chmod 0644 /etc/ssh/sshd_config.d/10-ghost-hetzner.conf
	sudo sshd -t || fail "sshd configuration is invalid — not restarting"
	sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd

	# Assert the effective configuration, not the file we just wrote.
	local eff
	eff="$(sudo sshd -T 2>/dev/null)"
	printf '%s\n' "$eff" | grep -qi '^permitrootlogin no$' || fail "root SSH login is not disabled"
	printf '%s\n' "$eff" | grep -qi '^passwordauthentication no$' || fail "password authentication is not disabled"
	printf '%s\n' "$eff" | grep -qi '^permitemptypasswords no$' || fail "empty passwords are not disabled"
	printf '%s\n' "$eff" | grep -qi '^kbdinteractiveauthentication no$' || fail "keyboard-interactive auth is not disabled"
	say "sshd hardened and verified"
}

# ------------------------------------------------------------- firewall -----

configure_ufw() {
	sudo ufw --force enable >/dev/null
	sudo ufw default deny incoming >/dev/null
	sudo ufw default allow outgoing >/dev/null
	sudo ufw allow 80/tcp comment 'Ghost HTTP' >/dev/null
	sudo ufw allow 443/tcp comment 'Ghost HTTPS' >/dev/null
	sudo ufw allow in on tailscale0 to any port 22 proto tcp comment 'SSH over Tailscale only' >/dev/null

	# Remove any interface-agnostic SSH rule that may have crept in.
	local line
	while read -r line; do
		[ -n "$line" ] || continue
		say "removing an unrestricted SSH rule: ${line}"
		sudo ufw --force delete "$line" >/dev/null || true
	done < <(sudo ufw status numbered | awk '/22\/tcp/ && !/tailscale0/ {gsub(/[][]/,"",$1); print $1}' | sort -rn)

	sudo ufw status verbose | grep -q 'Status: active' || fail "ufw is not active"
	local ssh_rules
	ssh_rules="$(sudo ufw status | grep -E '(^|[[:space:]])22/tcp' || true)"
	if printf '%s\n' "$ssh_rules" | grep -q . &&
		printf '%s\n' "$ssh_rules" | grep -qv 'tailscale0'; then
		fail "ufw still allows SSH outside the tunnel"
	fi
	say "host firewall active: 80/443 public, 22 only on tailscale0"
}

# --------------------------------------------------- automatic updates ------

configure_auto_updates() {
	sudo apt-get install -y -qq unattended-upgrades apt-listchanges >/dev/null
	sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
CONF
	sudo tee /etc/apt/apt.conf.d/51ghost-unattended >/dev/null <<'CONF'
Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}-security";
        "${distro_id}ESMApps:${distro_codename}-apps-security";
        "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
CONF
	sudo systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true
	sudo unattended-upgrade --dry-run --debug >/dev/null 2>&1 ||
		say "WARNING: unattended-upgrades dry run reported a problem"
	systemctl is-enabled --quiet unattended-upgrades || fail "unattended-upgrades is not enabled"
	say "automatic security updates enabled"
}

# ------------------------------------------------------- file permissions ---

fix_permissions() {
	sudo chmod 0700 "/home/${ADMIN_USER}/.ssh" 2>/dev/null || true
	sudo chmod 0600 "/home/${ADMIN_USER}/.ssh/authorized_keys" 2>/dev/null || true
	sudo chown -R "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh" 2>/dev/null || true
	if [ -f /var/www/ghost/config.production.json ]; then
		sudo chmod 0600 /var/www/ghost/config.production.json
	fi
	# Nothing world-readable may hold a credential.
	local bad
	bad="$(sudo find /var/www/ghost -maxdepth 1 -name 'config.*.json' -perm -o+r 2>/dev/null || true)"
	if [ -n "$bad" ]; then
		fail "world-readable Ghost configuration: ${bad}"
	fi
	say "file ownership and permissions verified"
}

main() {
	configure_sshd
	configure_ufw
	configure_auto_updates
	fix_permissions
	say "security configuration complete"
}

main "$@"
