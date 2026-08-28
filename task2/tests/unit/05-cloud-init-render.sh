#!/usr/bin/env bash
# cloud-init rendering: every placeholder substituted, the file created 0600,
# and the hardening the bootstrap depends on actually present.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

SANDBOX="$(make_sandbox)"
GHO_ROOT="$REPO_ROOT"
GHO_LIB_ONLY=1
export GHO_LIB_ONLY
# shellcheck disable=SC1091
. "${REPO_ROOT}/deploy.sh"
set +e
trap - ERR
trap - EXIT

echo "unit: cloud-init rendering"

GHO_ROOT="$SANDBOX"
state_paths_init
GHO_DEPLOYMENT_ID="ghost-blog-deadbeef"
state_init "$GHO_DEPLOYMENT_ID" "ghost-blog"
state_put 'resources.tailscale_hostname' 'gho-ghost-blog'

GHO_TS_AUTHKEY="tskey-auth-kRENDER11CNTRL-abcdefghijklmnopqrstuvwxyz"
GHO_SSH_KEY="${SANDBOX}/id_ed25519"
ssh-keygen -t ed25519 -N '' -C 'test' -f "$GHO_SSH_KEY" >/dev/null 2>&1
PUBKEY="$(cat "${GHO_SSH_KEY}.pub")"

OUT="${SANDBOX}/user-data.yaml"
render_cloud_init "$OUT"

assert_ok "rendered file exists" test -s "$OUT"
assert_eq "rendered file is 0600" "-rw-------" "$(ls -l "$OUT" | cut -c1-10)"

body="$(cat "$OUT")"
for ph in __ADMIN_USER__ __SSH_PUBKEY__ __TS_AUTHKEY__ __TS_HOSTNAME__ __DEPLOYMENT_ID__; do
	assert_not_contains "placeholder ${ph} was substituted" "$body" "$ph"
done
assert_contains "the deployment public key is present" "$body" "$PUBKEY"
assert_contains "the auth key is present (it must reach the server once)" "$body" "$GHO_TS_AUTHKEY"
assert_contains "the tailnet hostname is deterministic" "$body" "hostname: gho-ghost-blog"
assert_contains "the admin user is ghostops" "$body" "name: ghostops"

# Hardening the rest of the design depends on.
assert_contains "root login disabled in the drop-in" "$body" "PermitRootLogin no"
assert_contains "password auth disabled in the drop-in" "$body" "PasswordAuthentication no"
assert_contains "empty passwords disabled" "$body" "PermitEmptyPasswords no"
assert_contains "keyboard-interactive disabled" "$body" "KbdInteractiveAuthentication no"
assert_contains "cloud-init disables root" "$body" "disable_root: true"
assert_contains "cloud-init disables password ssh" "$body" "ssh_pwauth: false"
assert_contains "SSH is restricted to the admin user" "$body" "AllowUsers ghostops"

assert_not_contains "no PasswordAuthentication yes anywhere" "$body" "PasswordAuthentication yes"
assert_not_contains "no PermitRootLogin yes anywhere" "$body" "PermitRootLogin yes"

# Host firewall shape.
assert_contains "default deny incoming" "$body" "ufw default deny incoming"
assert_contains "HTTP allowed" "$body" "ufw allow 80/tcp"
assert_contains "HTTPS allowed" "$body" "ufw allow 443/tcp"
assert_contains "SSH bound to the tunnel interface only" "$body" "ufw allow in on tailscale0 to any port 22 proto tcp"
assert_not_contains "no unrestricted ufw SSH rule" "$body" "ufw allow 22/tcp"
assert_not_contains "no ufw allow ssh alias" "$body" "ufw allow ssh"

# Auth key handling.
assert_contains "the key is handed over as a file reference" "$body" '--auth-key="file:${KEY_FILE}"'
assert_contains "the key file is destroyed" "$body" 'shred -u "$KEY_FILE"'
assert_contains "the persisted copy is destroyed" "$body" 'shred -u "$RAW_KEY"'
assert_contains "cloud-init copies are redacted" "$body" "REDACTED-BY-GHO-BOOTSTRAP"
assert_not_contains "no shell tracing anywhere in the bootstrap" "$body" "set -x"

# A machine-readable status file is what stage 7 waits on.
assert_contains "bootstrap writes a status file" "$body" "/var/lib/gho-bootstrap.json"
assert_contains "bootstrap writes a completion marker" "$body" "/var/lib/gho-bootstrap.done"

rm -f "$OUT"
rm -rf "$SANDBOX"
finish
