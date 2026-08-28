#!/usr/bin/env bash
# remote/configure-backups.sh — nightly local Ghost backups.
# Usage: configure-backups.sh <admin_user> <retention_count>
#
# These backups live on the same disk as the site. They protect against a bad
# update or a mistaken deletion. They do NOT protect against losing the server,
# and the deployment report says so explicitly.

set -Eeuo pipefail

ADMIN_USER="${1:?admin user required}"
RETENTION="${2:-7}"
BACKUP_DIR=/var/backups/ghost
GHOST_DIR=/var/www/ghost

say() { printf '::: %s\n' "$*"; }
fail() {
	printf '!!! %s\n' "$*" >&2
	exit 1
}

printf '%s' "$RETENTION" | grep -Eq '^[0-9]{1,3}$' || fail "retention must be a small integer"

sudo install -d -o root -g root -m 0700 "$BACKUP_DIR"

sudo tee /usr/local/sbin/ghost-backup.sh >/dev/null <<BACKUP
#!/usr/bin/env bash
# Nightly Ghost backup: database dump plus the content directory (themes,
# images, uploaded media, routes). Installed by ghost-hetzner-oneclick.
set -Eeuo pipefail

BACKUP_DIR="${BACKUP_DIR}"
GHOST_DIR="${GHOST_DIR}"
ADMIN_USER="${ADMIN_USER}"
RETENTION="${RETENTION}"

stamp="\$(date -u +%Y%m%dT%H%M%SZ)"
work="\$(mktemp -d "\${BACKUP_DIR}/.work.XXXXXX")"
chmod 700 "\$work"
trap 'rm -rf "\$work"' EXIT

cfg="\${GHOST_DIR}/config.production.json"
[ -f "\$cfg" ] || { echo "no Ghost config at \$cfg" >&2; exit 1; }

# Credentials are handed to mysqldump through a 0600 defaults file, never on the
# command line.
defaults="\$(mktemp)"
chmod 600 "\$defaults"
{
  printf '[client]\n'
  printf 'host=%s\n'     "\$(jq -r '.database.connection.host'     "\$cfg")"
  printf 'user=%s\n'     "\$(jq -r '.database.connection.user'     "\$cfg")"
  printf 'password=%s\n' "\$(jq -r '.database.connection.password' "\$cfg")"
} > "\$defaults"

db="\$(jq -r '.database.connection.database' "\$cfg")"
mysqldump --defaults-extra-file="\$defaults" --single-transaction --quick \
          --routines --triggers "\$db" > "\${work}/database.sql"
shred -u "\$defaults" 2>/dev/null || rm -f "\$defaults"

# Ghost's own supported export, when the site is running.
if sudo -u "\$ADMIN_USER" bash -lc "cd '\$GHOST_DIR' && ghost backup --output '\${work}'" >/dev/null 2>&1; then
  echo "ghost backup export included"
fi

tar -czf "\${work}/content.tar.gz" -C "\$GHOST_DIR" content

archive="\${BACKUP_DIR}/ghost-backup-\${stamp}.tar.gz"
tar -czf "\$archive" -C "\$work" .
chmod 600 "\$archive"

[ -s "\$archive" ] || { echo "backup archive is empty" >&2; exit 1; }

# Retention: keep the newest \$RETENTION archives, delete the rest.
ls -1t "\${BACKUP_DIR}"/ghost-backup-*.tar.gz 2>/dev/null | tail -n "+\$((RETENTION + 1))" |
  while read -r old; do rm -f "\$old"; done

echo "backup written: \$archive (\$(du -h "\$archive" | cut -f1))"
BACKUP
sudo chmod 0700 /usr/local/sbin/ghost-backup.sh

sudo tee /etc/systemd/system/ghost-backup.service >/dev/null <<'UNIT'
[Unit]
Description=Ghost local backup (database + content)
After=mysql.service
Wants=mysql.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ghost-backup.sh
Nice=10
IOSchedulingClass=idle
UNIT

sudo tee /etc/systemd/system/ghost-backup.timer >/dev/null <<'UNIT'
[Unit]
Description=Nightly Ghost local backup

[Timer]
OnCalendar=*-*-* 03:20:00
RandomizedDelaySec=900
Persistent=true

[Install]
WantedBy=timers.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now ghost-backup.timer >/dev/null

say "running the backup once to prove it works"
sudo systemctl start ghost-backup.service
sudo systemctl is-active --quiet ghost-backup.service ||
	sudo journalctl -u ghost-backup.service -n 30 --no-pager >&2

latest="$(sudo ls -1t "${BACKUP_DIR}"/ghost-backup-*.tar.gz 2>/dev/null | head -1 || true)"
[ -n "$latest" ] || fail "no backup archive was produced"
size="$(sudo stat -c %s "$latest")"
[ "$size" -gt 1024 ] || fail "backup archive is suspiciously small (${size} bytes)"

say "backup verified: ${latest} (${size} bytes), retention ${RETENTION}"
say "WARNING: these backups sit on the same disk as the site. They are not"
say "         disaster recovery. Copy them off the server for that."
