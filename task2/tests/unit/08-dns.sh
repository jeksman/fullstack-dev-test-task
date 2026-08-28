#!/usr/bin/env bash
# DNS result interpretation. A record that is missing, stale or only partially
# propagated must never be treated as ready: certificate issuance depends on it.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
load_libs
use_mocks

echo "unit: DNS verification"

export GHO_MOCK_DNS_A="203.0.113.42"
export GHO_MOCK_DNS_AAAA="2001:db8:1234:5678::1"

assert_eq "A record is read" "203.0.113.42" "$(dns_query blog.example.com A)"
assert_eq "AAAA record is read" "2001:db8:1234:5678::1" "$(dns_query blog.example.com AAAA)"

assert_ok "matching A record is accepted" dns_matches blog.example.com A "203.0.113.42" 1.1.1.1
assert_fail "a different A record is rejected" dns_matches blog.example.com A "198.51.100.9" 1.1.1.1
assert_ok "all resolvers agreeing is accepted" dns_check_all_resolvers blog.example.com A "203.0.113.42"
assert_fail "a stale address is rejected across resolvers" dns_check_all_resolvers blog.example.com A "198.51.100.9"

# A substring must not be mistaken for a match.
export GHO_MOCK_DNS_A="203.0.113.420"
assert_fail "a longer address is not a substring match" dns_check_all_resolvers blog.example.com A "203.0.113.42"

# Several answers, one of which is right, is a match: round-robin is legitimate.
export GHO_MOCK_DNS_A="198.51.100.9
203.0.113.42"
assert_ok "one correct answer among several is accepted" dns_check_all_resolvers blog.example.com A "203.0.113.42"

export GHO_MOCK_DNS_A=""
assert_fail "an empty answer is not a match" dns_check_all_resolvers blog.example.com A "203.0.113.42"

# Bounded waiting.
export GHO_MOCK_DNS_A="203.0.113.42"
assert_ok "dns_wait returns as soon as records are correct" dns_wait blog.example.com "203.0.113.42" "" 30
export GHO_MOCK_DNS_A="198.51.100.9"
start=$(date +%s)
assert_fail "dns_wait gives up within its budget" dns_wait blog.example.com "203.0.113.42" "" 10
elapsed=$(($(date +%s) - start))
assert_ok "dns_wait is bounded (took ${elapsed}s)" test "$elapsed" -lt 40

# IPv6 must be verified too when it is in play.
export GHO_MOCK_DNS_A="203.0.113.42"
export GHO_MOCK_DNS_AAAA="2001:db8:dead::1"
assert_fail "a wrong AAAA record blocks readiness" dns_wait blog.example.com "203.0.113.42" "2001:db8:1234:5678::1" 6

summary="$(dns_current_summary blog.example.com)"
assert_contains "the summary shows the A answer" "$summary" "203.0.113.42"
assert_contains "the summary shows the AAAA answer" "$summary" "2001:db8:dead::1"

finish
