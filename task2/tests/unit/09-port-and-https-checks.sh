#!/usr/bin/env bash
# Interpretation of port probes and HTTP/TLS checks. "Closed" must mean closed,
# and a check must not pass merely because a command exited zero.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
load_libs
use_mocks

echo "unit: port probes and HTTPS checks"

export GHO_MOCK_OPEN_PORTS="203.0.113.42:80 203.0.113.42:443 100.87.65.43:22"

assert_ok "an open port is detected as open" tcp_probe "203.0.113.42" 80 3
assert_fail "a closed port is detected as closed" tcp_probe "203.0.113.42" 22 3
assert_ok "public SSH is reported closed when it is closed" public_ssh_closed "203.0.113.42"
assert_ok "SSH on the tunnel address is open (that is the point)" tcp_probe "100.87.65.43" 22 3

# The containment trigger: if 22 answers on the public address, the check must fail.
export GHO_MOCK_OPEN_PORTS="203.0.113.42:22"
assert_fail "an open public SSH port is NOT reported closed" public_ssh_closed "203.0.113.42"
export GHO_MOCK_OPEN_PORTS="203.0.113.42:80 203.0.113.42:443"

# The step runner: expect=fail means the command must not succeed.
GHO_ROOT="$(make_sandbox)"
state_paths_init
GHO_DEPLOYMENT_ID="ghost-blog-deadbeef"
state_init "$GHO_DEPLOYMENT_ID" "ghost-blog"

verify "closed-port-expected-closed" fail 5 1 -- tcp_probe "203.0.113.42" 22 2 >/dev/null
assert_eq "expect=fail records PASS when the port is closed" "PASS" "$(check_status 'closed-port-expected-closed')"

verify "open-port-expected-closed" fail 5 1 -- tcp_probe "203.0.113.42" 80 2 >/dev/null
assert_eq "expect=fail records FAIL when the port is open" "FAIL" "$(check_status 'open-port-expected-closed')"

verify "open-port-expected-open" ok 5 1 -- tcp_probe "203.0.113.42" 80 2 >/dev/null
assert_eq "expect=ok records PASS for an open port" "PASS" "$(check_status 'open-port-expected-open')"

before="$GHO_CHECK_FAILURES"
verify_warn "soft-check" ok 5 1 -- tcp_probe "203.0.113.42" 22 2 >/dev/null
assert_eq "a soft failure is recorded as WARNING" "WARNING" "$(check_status 'soft-check')"
assert_eq "a soft failure does not increment the failure count" "$before" "$GHO_CHECK_FAILURES"

verify_skip "skipped-check" "not requested" >/dev/null
assert_eq "a skipped check is recorded as SKIP" "SKIP" "$(check_status 'skipped-check')"

# Retries must be bounded.
start=$(date +%s)
verify "always-fails" ok 3 3 -- false >/dev/null
elapsed=$(($(date +%s) - start))
assert_eq "a failing check is recorded as FAIL" "FAIL" "$(check_status 'always-fails')"
assert_ok "retries are bounded (took ${elapsed}s)" test "$elapsed" -lt 40

# Timeouts must actually fire.
start=$(date +%s)
rc=0
run_with_timeout 3 sleep 30 || rc=$?
elapsed=$(($(date +%s) - start))
assert_eq "a timeout returns 124" "124" "$rc"
assert_ok "the timeout fires close to the budget (${elapsed}s)" test "$elapsed" -lt 10

# HTTP / TLS interpretation.
export GHO_MOCK_HTTP_CODE=301
export GHO_MOCK_HTTPS_CODE=200
assert_ok "a 301 to https counts as a redirect" http_redirects_to_https blog.example.com
assert_ok "https 200 is accepted" https_ok blog.example.com
assert_ok "admin path is reachable" https_admin_ok blog.example.com

export GHO_MOCK_HTTP_CODE=200
assert_fail "a plain 200 over http is not a redirect" http_redirects_to_https blog.example.com
export GHO_MOCK_HTTP_CODE=301

export GHO_MOCK_HTTPS_CODE=502
assert_fail "a 502 over https is not success" https_ok blog.example.com
export GHO_MOCK_HTTPS_CODE=200

export GHO_MOCK_CERT_CHECKEND_RC=0
assert_ok "a certificate with enough life left passes" tls_cert_valid_for_days blog.example.com 20
export GHO_MOCK_CERT_CHECKEND_RC=1
assert_fail "a certificate about to expire fails" tls_cert_valid_for_days blog.example.com 20
export GHO_MOCK_CERT_CHECKEND_RC=0

assert_ok "a Let's Encrypt issuer is trusted" tls_cert_issuer_trusted blog.example.com
export GHO_MOCK_CERT_ISSUER="Definitely Not A Real CA"
assert_fail "an unexpected issuer is rejected" tls_cert_issuer_trusted blog.example.com

rm -rf "$GHO_ROOT"
finish
