#!/usr/bin/env bash
# remote/configure-https.sh — reverse proxy and Let's Encrypt certificate.
# Usage: configure-https.sh <domain> <letsencrypt_email> <admin_user>
#
# Split out of install-ghost.sh on purpose: certificate issuance can only run
# once public DNS points at this machine, which happens in a later stage.

set -Eeuo pipefail

DOMAIN="${1:?domain required}"
LE_EMAIL="${2:?letsencrypt email required}"
ADMIN_USER="${3:?admin user required}"
GHOST_DIR=/var/www/ghost

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

say() { printf '::: %s\n' "$*"; }
fail() {
	printf '!!! %s\n' "$*" >&2
	exit 1
}

[ "$(id -un)" = "$ADMIN_USER" ] || fail "must run as ${ADMIN_USER}, not $(id -un)"

setup_nginx() {
	if [ -f "/etc/nginx/sites-available/${DOMAIN}.conf" ]; then
		say "nginx site for ${DOMAIN} already configured"
		return 0
	fi
	say "configuring nginx reverse proxy for ${DOMAIN}"
	(cd "$GHOST_DIR" && ghost setup nginx --no-prompt) || fail "ghost setup nginx failed"
}

setup_ssl() {
	if [ -f "/etc/nginx/sites-available/${DOMAIN}-ssl.conf" ] &&
		sudo test -s "/etc/letsencrypt/${DOMAIN}/fullchain.cer"; then
		say "TLS certificate already present for ${DOMAIN}"
		return 0
	fi
	say "requesting a Let's Encrypt certificate for ${DOMAIN}"
	(cd "$GHOST_DIR" && ghost setup ssl --sslemail "$LE_EMAIL" --no-prompt) ||
		fail "ghost setup ssl failed — check that DNS points here and port 80 is reachable"
}

verify_stack() {
	sudo nginx -t || fail "nginx configuration test failed"
	sudo systemctl reload nginx
	systemctl is-active --quiet nginx || fail "nginx is not active"
	systemctl is-enabled --quiet nginx || sudo systemctl enable nginx >/dev/null

	# HTTP must redirect, not serve.
	local code
	code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -H "Host: ${DOMAIN}" http://127.0.0.1/ || true)"
	case "$code" in
	301 | 302 | 307 | 308) say "HTTP redirects to HTTPS (${code})" ;;
	*) fail "HTTP did not redirect to HTTPS (got ${code})" ;;
	esac

	# The canonical URL Ghost serves must be the HTTPS one.
	local url
	url="$(sudo -u "$ADMIN_USER" jq -r '.url' "${GHOST_DIR}/config.production.json")"
	case "$url" in
	https://*) say "Ghost canonical URL is ${url}" ;;
	*) fail "Ghost URL is not HTTPS: ${url}" ;;
	esac

	local unit
	unit="$(systemctl list-units --type=service --no-legend 'ghost_*' | awk '{print $1}' | head -1)"
	[ -n "$unit" ] || fail "no ghost systemd unit found"
	systemctl is-enabled --quiet "$unit" || sudo systemctl enable "$unit" >/dev/null
	say "systemd unit ${unit} is enabled for boot"

	# The certificate auto-renewal timer that ghost-cli installs must exist.
	if systemctl list-timers --all 2>/dev/null | grep -q 'acme\|certbot'; then
		say "certificate renewal timer present"
	elif sudo crontab -l 2>/dev/null | grep -q 'acme.sh'; then
		say "certificate renewal cron entry present"
	else
		say "WARNING: no certificate renewal timer detected — check acme.sh installation"
	fi
}

main() {
	setup_nginx
	setup_ssl
	verify_stack
	say "HTTPS configuration complete: https://${DOMAIN}/"
}

main "$@"
