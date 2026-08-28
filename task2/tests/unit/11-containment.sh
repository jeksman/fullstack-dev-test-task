#!/usr/bin/env bash
# Failure containment: when the security posture is wrong, the machine is
# powered off and the restrictive policy is reapplied before anything else.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
load_libs
use_mocks

echo "unit: failure containment"

GHO_ROOT="$(make_sandbox)"
state_paths_init
GHO_DEPLOYMENT_ID="ghost-blog-deadbeef"
GHO_HCLOUD_TOKEN="mock-token-value"
state_init "$GHO_DEPLOYMENT_ID" "ghost-blog"

RULES="${GHO_STATE_DIR}/firewall-rules.json"
hetzner_render_firewall_rules "${REPO_ROOT}/templates/hetzner-firewall.json" "$RULES" 1

export GHO_MOCK_LOG="${GHO_STATE_DIR}/mock-calls.log"
: >"$GHO_MOCK_LOG"

hetzner_contain "gho-ghost-blog" "gho-ghost-blog-fw" "$RULES" >/dev/null 2>&1
calls="$(cat "$GHO_MOCK_LOG")"

assert_contains "containment powers the server off" "$calls" "server poweroff gho-ghost-blog"
assert_contains "containment reapplies the firewall rules" "$calls" "firewall replace-rules gho-ghost-blog-fw"
assert_ok "poweroff happens before the rule replacement" \
	bash -c "grep -n 'poweroff' '$GHO_MOCK_LOG' | head -1 | cut -d: -f1 | \
	         xargs -I{} test {} -lt \$(grep -n 'replace-rules' '$GHO_MOCK_LOG' | head -1 | cut -d: -f1)"
assert_not_contains "containment never deletes anything" "$calls" "server delete"
assert_not_contains "containment never opens a port" "$calls" "allow"

# The reapplied policy is the deny-by-default one, not whatever drifted.
assert_ok "the reapplied rules contain no SSH" \
	jq -e 'all(.[]; (.port // "" | tostring) != "22")' "$RULES"

# The SSH guard refuses public destinations even if state says otherwise.
state_put 'resources.public_ipv4' '203.0.113.42'
state_put 'resources.public_ipv6' '2001:db8:1234:5678::1'
assert_fail "SSH to the public IPv4 is refused" ssh_assert_private_target "203.0.113.42"
assert_fail "SSH to the public IPv6 is refused" ssh_assert_private_target "2001:db8:1234:5678::1"
assert_fail "SSH to an arbitrary public address is refused" ssh_assert_private_target "198.51.100.9"
assert_fail "SSH to an empty target is refused" ssh_assert_private_target ""
assert_fail "SSH to a hostname is refused" ssh_assert_private_target "blog.example.com"
assert_ok "SSH to the tailnet address is allowed" ssh_assert_private_target "100.87.65.43"

# rssh/rscp must refuse before they ever invoke ssh.
GHO_SSH_KEY="${GHO_STATE_DIR}/key"
GHO_SSH_TARGET="203.0.113.42"
: >"$GHO_MOCK_LOG"
assert_fail "rssh refuses a public target" rssh true
assert_eq "no ssh process was started for a public target" "" "$(cat "$GHO_MOCK_LOG")"

GHO_SSH_TARGET="100.87.65.43"
assert_ok "rssh works against the tunnel address" rssh true
assert_contains "the ssh mock was actually invoked" "$(cat "$GHO_MOCK_LOG")" "ssh "

rm -rf "$GHO_ROOT"
finish
