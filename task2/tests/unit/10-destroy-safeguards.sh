#!/usr/bin/env bash
# Destruction safeguards: only resources carrying this project's labels AND the
# exact deployment id may ever be deleted.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
load_libs
use_mocks

echo "unit: destruction safeguards"

GHO_ROOT="$(make_sandbox)"
state_paths_init
GHO_HCLOUD_TOKEN="mock-token-value"

GHO_DEPLOYMENT_ID="ghost-blog-deadbeef"
assert_ok "our own server is recognised" hetzner_resource_belongs_to_deployment server "gho-ghost-blog"
assert_ok "our own firewall is recognised" hetzner_resource_belongs_to_deployment firewall "gho-ghost-blog-fw"
assert_ok "our own ssh key is recognised" hetzner_resource_belongs_to_deployment ssh-key "gho-ghost-blog-key"

assert_fail "an unrelated server is refused" \
	hetzner_resource_belongs_to_deployment server "someone-elses-server"
assert_fail "a nonexistent server is refused" \
	hetzner_resource_belongs_to_deployment server "no-such-server"

# Same labels, different deployment: still refused.
GHO_DEPLOYMENT_ID="ghost-blog-cafebabe"
assert_fail "a server from a different deployment id is refused" \
	hetzner_resource_belongs_to_deployment server "gho-ghost-blog"
assert_fail "a firewall from a different deployment id is refused" \
	hetzner_resource_belongs_to_deployment firewall "gho-ghost-blog-fw"
GHO_DEPLOYMENT_ID="ghost-blog-deadbeef"

# The confirmation gate is exact-match, and refuses in non-interactive mode.
GHO_NON_INTERACTIVE=1
assert_fail "confirm_exact refuses to self-confirm non-interactively" \
	confirm_exact "ghost-blog" "irreversible"
GHO_NON_INTERACTIVE=0

# The tty requirement is what makes the guard non-bypassable; to exercise the
# comparison itself we stub only that predicate.
try_confirm() {
	printf '%s\n' "$1" | bash -c '
		. "'"$REPO_ROOT"'/tests/lib.sh"; load_libs
		_interactive() { return 0; }
		confirm_exact "ghost-blog" "irreversible" >/dev/null 2>&1'
}
assert_ok "a correctly typed name confirms" try_confirm "ghost-blog"
assert_fail "a mistyped name does not confirm" try_confirm "ghost-blo"
assert_fail "a name with trailing text does not confirm" try_confirm "ghost-blog "
assert_fail "an empty answer does not confirm" try_confirm ""

# The label set applied to every created resource.
labels="$(hcloud_labels | tr '\n' ' ')"
assert_contains "managed-by label" "$labels" "managed-by=ghost-hetzner-oneclick"
assert_contains "deployment-id label" "$labels" "deployment-id=ghost-blog-deadbeef"
assert_contains "application label" "$labels" "application=ghost"
assert_contains "environment label" "$labels" "environment=production"

rm -rf "$GHO_ROOT"
finish
