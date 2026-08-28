#!/usr/bin/env bash
# State file: atomic writes, secret refusal, stage bookkeeping, resume logic.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
load_libs

echo "unit: state, resume and idempotency"

GHO_ROOT="$(make_sandbox)"
state_paths_init
GHO_DEPLOYMENT_ID="ghost-blog-deadbeef"
STAGES="preflight credentials settings firewall server bootstrap privatessh ghost dnshttps security reboot report"

state_init "$GHO_DEPLOYMENT_ID" "ghost-blog"
assert_ok "state file created" test -s "$GHO_STATE_FILE"
assert_ok "state file is valid JSON" jq -e . "$GHO_STATE_FILE"
assert_eq "deployment id round-trips" "ghost-blog-deadbeef" "$(state_get 'deployment_id')"

perm="$(ls -l "$GHO_STATE_FILE" | cut -c1-10)"
assert_eq "state file is not world readable" "-rw-------" "$perm"

# Re-initialising must not clobber an existing deployment.
state_put 'config.domain' 'blog.example.com'
state_init "different-id" "different-name"
assert_eq "state_init is a no-op when state exists" "ghost-blog-deadbeef" "$(state_get 'deployment_id')"
assert_eq "existing config survives" "blog.example.com" "$(state_get 'config.domain')"

# Atomicity: no temp file may be left behind, and the document stays parseable.
state_put 'config.location' 'nbg1'
leftovers="$(find "$GHO_STATE_DIR" -maxdepth 1 -name 'state.json.tmp.*' | wc -l | tr -d ' ')"
assert_eq "no temporary state files remain" "0" "$leftovers"
assert_ok "state is still valid JSON after an update" jq -e . "$GHO_STATE_FILE"

# Secret guard.
redact_register "tskey-auth-kSECRET11CNTRL-abcdefghijklmnop"
assert_fail "state_put refuses to store a registered secret" \
	bash -c '. "'"$REPO_ROOT"'/tests/lib.sh"; load_libs; GHO_ROOT="'"$GHO_ROOT"'"; state_paths_init;
	         redact_register "tskey-auth-kSECRET11CNTRL-abcdefghijklmnop";
	         state_put "config.oops" "tskey-auth-kSECRET11CNTRL-abcdefghijklmnop"'
assert_ok "the secret never reached the file" bash -c "! grep -q 'tskey-auth' '$GHO_STATE_FILE'"

# Stage bookkeeping.
assert_fail "an unfinished stage is not done" stage_is_done preflight
assert_ok "an unfinished stage should run" stage_should_run preflight
stage_mark preflight "done"
assert_ok "a finished stage is done" stage_is_done preflight
assert_fail "a finished stage is skipped" stage_should_run preflight

GHO_FORCE_STAGE=preflight
assert_ok "GHO_FORCE_STAGE overrides the skip" stage_should_run preflight
unset GHO_FORCE_STAGE

stage_mark credentials "done"
stage_mark settings "done"
assert_eq "resume points at the last completed stage" "settings" "$(state_last_done_stage "$STAGES")"
assert_ok "the next stage still runs" stage_should_run firewall

stage_mark firewall failed
assert_fail "a failed stage is not treated as done" stage_is_done firewall
assert_ok "a failed stage runs again on resume" stage_should_run firewall

# Checks.
check_record "public-ssh-ipv4-closed" PASS ""
check_record "https-responds" FAIL "connection refused"
check_record "https-responds" PASS ""
assert_eq "check_status returns the latest result" "PASS" "$(check_status 'https-responds')"
assert_eq "check history is retained" "3" "$(jq -r '.checks | length' "$GHO_STATE_FILE")"

# Locking.
state_lock
assert_ok "lock directory exists" test -d "$GHO_LOCK_DIR"
assert_eq "lock records our pid" "$$" "$(cat "${GHO_LOCK_DIR}/pid")"
state_unlock
assert_fail "unlock removes the lock" test -d "$GHO_LOCK_DIR"

# A lock held by a dead process must be reclaimed, not deadlock the tool.
mkdir -p "$GHO_LOCK_DIR"
printf '999999' >"${GHO_LOCK_DIR}/pid"
state_lock
assert_eq "stale lock is reclaimed" "$$" "$(cat "${GHO_LOCK_DIR}/pid")"
state_unlock

rm -rf "$GHO_ROOT"
finish
