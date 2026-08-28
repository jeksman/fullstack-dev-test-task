#!/usr/bin/env bash
# Report generation: correct content, correct permissions, no secrets, and a
# private SSH command that never mentions a public address.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
load_libs
use_mocks

echo "unit: report generation"

GHO_ROOT="$(make_sandbox)"
state_paths_init
GHO_DEPLOYMENT_ID="ghost-blog-deadbeef"
state_init "$GHO_DEPLOYMENT_ID" "ghost-blog"

state_put 'config.domain' 'blog.example.com'
state_put 'config.location' 'nbg1'
state_put 'config.server_type' 'cx23'
state_put 'resources.server_name' 'gho-ghost-blog'
state_put 'resources.server_id' '55512345'
state_put 'resources.firewall_name' 'gho-ghost-blog-fw'
state_put 'resources.firewall_id' '9911'
state_put 'resources.public_ipv4' '203.0.113.42'
state_put 'resources.public_ipv6' '2001:db8:1234:5678::1'
state_put 'resources.tailscale_ipv4' '100.87.65.43'
state_put 'resources.tailscale_dnsname' 'gho-ghost-blog.example-tailnet.ts.net'

for c in public-ssh-ipv4-closed private-ssh-login mysql-active nginx-active \
	ghost-service-active https-responds tls-certificate-valid reboot-recovery backup-timer; do
	check_record "$c" PASS ""
done

TXT="$(report_write SUCCESS)"
JSON="${GHO_REPORT_DIR}/final-report.json"

assert_ok "text report written" test -s "$TXT"
assert_ok "json report written" test -s "$JSON"
assert_ok "json report is valid JSON" jq -e . "$JSON"
assert_eq "text report is 0600" "-rw-------" "$(ls -l "$TXT" | cut -c1-10)"
assert_eq "json report is 0600" "-rw-------" "$(ls -l "$JSON" | cut -c1-10)"

body="$(cat "$TXT")"
assert_contains "status line" "$body" "Deployment status:      SUCCESS"
assert_contains "deployment id" "$body" "ghost-blog-deadbeef"
assert_contains "ghost url" "$body" "https://blog.example.com/"
assert_contains "ghost admin url" "$body" "https://blog.example.com/ghost/"
assert_contains "server name" "$body" "gho-ghost-blog"
assert_contains "server id" "$body" "55512345"
assert_contains "firewall id" "$body" "9911"
assert_contains "public ipv4" "$body" "203.0.113.42"
assert_contains "public ipv6" "$body" "2001:db8:1234:5678::1"
assert_contains "tailscale hostname" "$body" "gho-ghost-blog.example-tailnet.ts.net"
assert_contains "tailscale ipv4" "$body" "100.87.65.43"
assert_contains "ssh user" "$body" "SSH user:               ghostops"
assert_contains "public ssh reported closed" "$body" "Public SSH:             CLOSED"
assert_contains "private ssh pass" "$body" "Private SSH:            PASS"
assert_contains "mysql pass" "$body" "MySQL:                  PASS"
assert_contains "nginx pass" "$body" "Nginx:                  PASS"
assert_contains "ghost pass" "$body" "Ghost:                  PASS"
assert_contains "https pass" "$body" "HTTPS:                  PASS"
assert_contains "certificate pass" "$body" "Certificate:            PASS"
assert_contains "reboot recovery pass" "$body" "Reboot recovery:        PASS"
assert_contains "backup timer pass" "$body" "Backup timer:           PASS"
assert_contains "report path" "$body" "final-report.txt"
assert_contains "maintenance: resume" "$body" "bash ./deploy.sh --resume"
assert_contains "maintenance: destroy" "$body" "bash ./deploy.sh --destroy"
assert_contains "maintenance: ghost update" "$body" "ghost update"

# The single most important line in the report.
assert_contains "private ssh command uses the tailnet name" "$body" \
	"ssh ghostops@gho-ghost-blog.example-tailnet.ts.net"
ssh_lines="$(printf '%s\n' "$body" | grep '^ *ssh ' || true)"
assert_not_contains "no ssh command mentions the public IPv4" "$ssh_lines" "203.0.113.42"
assert_not_contains "no ssh command mentions the public IPv6" "$ssh_lines" "2001:db8"

# An unfinished deployment must not claim things passed.
check_record "https-responds" FAIL "unreachable"
partial="$(report_text FAILED)"
assert_contains "a failed deployment says so" "$partial" "Deployment status:      FAILED"
assert_contains "a failed check is reported as FAIL" "$partial" "HTTPS:                  FAIL"

# Checks that never ran must not be reported as passing.
state_init_fresh="$(mktemp -d "${TMPDIR:-/tmp}/gho-report2.XXXXXX")"
GHO_ROOT="$state_init_fresh"
state_paths_init
state_init "empty-000000" "empty"
empty_report="$(report_text FAILED)"
assert_contains "a check that never ran says NOT RUN" "$empty_report" "NOT RUN"
assert_not_contains "an unverified public SSH state is not reported as CLOSED" \
	"$(printf '%s\n' "$empty_report" | grep 'Public SSH:')" "CLOSED"
rm -rf "$state_init_fresh"

# A secret must never reach a report.
GHO_ROOT="$(make_sandbox)"
state_paths_init
state_init "leak-test-000" "leak-test"
redact_register "tskey-auth-kLEAK11CNTRL-shouldneverappear"
report_write SUCCESS >/dev/null
assert_ok "reports contain no registered secret" scan_for_secrets "$GHO_REPORT_DIR"

rm -rf "$GHO_ROOT"
finish
