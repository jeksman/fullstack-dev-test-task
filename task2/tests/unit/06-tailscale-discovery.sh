#!/usr/bin/env bash
# Tunnel node discovery from mocked `tailscale status --json`.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
load_libs
use_mocks

echo "unit: tailscale node discovery"

GHO_TAILSCALE_BIN="$(command -v tailscale)"

assert_ok "local tailnet reported as connected" tunnel_local_ready
assert_eq "tailnet name is read" "example-tailnet.ts.net" "$(ts_local_tailnet)"
assert_eq "provider is Tailscale" "Tailscale" "$(tunnel_name)"

assert_eq "peer address discovered by hostname" "100.87.65.43" "$(ts_node_ipv4 'gho-ghost-blog')"
assert_eq "discovered address is inside CGNAT" "0" "$(validate_tailscale_ipv4 "$(ts_node_ipv4 'gho-ghost-blog')" && echo 0 || echo 1)"
assert_eq "MagicDNS name discovered" "gho-ghost-blog.example-tailnet.ts.net" "$(ts_node_dnsname 'gho-ghost-blog')"
assert_eq "own node is also findable" "100.101.102.103" "$(ts_node_ipv4 'operator-laptop')"
assert_eq "unknown host yields nothing" "" "$(ts_node_ipv4 'does-not-exist')"
assert_eq "IPv6 tailnet addresses are not returned as IPv4" "100.87.65.43" "$(ts_node_ipv4 'gho-ghost-blog')"

assert_ok "online peer reported online" ts_node_online 'gho-ghost-blog'
assert_fail "offline peer reported offline" ts_node_online 'some-other-node'
assert_fail "unknown peer is not online" ts_node_online 'does-not-exist'

export GHO_MOCK_TS_DOWN=1
assert_fail "a stopped local backend is detected" tunnel_local_ready
unset GHO_MOCK_TS_DOWN

export GHO_MOCK_TS_EMPTY=1
assert_eq "an empty tailnet yields no address" "" "$(ts_node_ipv4 'gho-ghost-blog')"
start=$(date +%s)
assert_fail "waiting for a node that never appears times out" ts_wait_for_node 'gho-ghost-blog' 6
elapsed=$(($(date +%s) - start))
assert_ok "the wait is bounded (took ${elapsed}s for a 6s budget)" test "$elapsed" -lt 20
unset GHO_MOCK_TS_EMPTY

assert_eq "waiting returns immediately once the node is there" "100.87.65.43" "$(ts_wait_for_node 'gho-ghost-blog' 30)"

assert_ok "tunnel ping succeeds" tunnel_ping "100.87.65.43"
export GHO_MOCK_TS_PING_FAIL=1
assert_fail "tunnel ping failure is surfaced" tunnel_ping "100.87.65.43"
unset GHO_MOCK_TS_PING_FAIL

help_text="$(tunnel_access_help 'gho-ghost-blog.example-tailnet.ts.net' '100.87.65.43' 2>&1)"
assert_contains "ACL guidance names the node" "$help_text" "gho-ghost-blog.example-tailnet.ts.net"
assert_contains "ACL guidance names the address" "$help_text" "100.87.65.43"
assert_contains "ACL guidance says public SSH stays closed" "$help_text" "Public SSH stays closed"
assert_contains "ACL guidance explains how to resume" "$help_text" "--resume"

finish
