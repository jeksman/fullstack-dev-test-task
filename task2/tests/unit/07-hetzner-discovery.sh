#!/usr/bin/env bash
# Hetzner resource discovery and assertions, driven from mocked hcloud output.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
load_libs
use_mocks

echo "unit: hetzner resource discovery"

GHO_ROOT="$(make_sandbox)"
state_paths_init
GHO_DEPLOYMENT_ID="ghost-blog-deadbeef"
GHO_HCLOUD_TOKEN="mock-token-value"

assert_ok "token validation passes against the API" hetzner_validate_token
export GHO_MOCK_HCLOUD_FAIL=auth
assert_fail "a rejected token is detected" hetzner_validate_token
unset GHO_MOCK_HCLOUD_FAIL

locations="$(hetzner_locations | tr '\n' ' ')"
assert_contains "locations include nbg1" "$locations" "nbg1"
assert_contains "locations include ash" "$locations" "ash"
assert_contains "location description is human readable" "$(hetzner_location_describe nbg1)" "Nuremberg"

types="$(hetzner_suitable_server_types 2 x86 | tr '\n' ' ')"
assert_contains "cx22 offered (4GB x86)" "$types" "cx22"
assert_contains "cpx11 offered (2GB x86)" "$types" "cpx11"
assert_not_contains "arm types excluded when x86 is requested" "$types" "cax11"
assert_not_contains "deprecated types excluded" "$types" "cx11"

types4="$(hetzner_suitable_server_types 4 x86 | tr '\n' ' ')"
assert_not_contains "types below the memory floor excluded" "$types4" "cpx11"

assert_contains "server type info reports memory" "$(hetzner_server_type_info cx23)" "memory=4GB"
assert_contains "server type info reports architecture" "$(hetzner_server_type_info cx23)" "arch=x86"
assert_eq "architecture is read for the summary" "x86" "$(hetzner_server_type_arch cx23)"
assert_contains "pricing is surfaced when available" "$(hetzner_server_type_price cx23 nbg1)" "EUR/month"

assert_ok "the pinned image exists" hetzner_image_exists "ubuntu-24.04"
assert_fail "a nonexistent image is detected" hetzner_image_exists "ubuntu-99.04"

assert_ok "server describe works" hetzner_server_exists "gho-ghost-blog"
assert_fail "a nonexistent server is detected" hetzner_server_exists "no-such-server"
assert_eq "server status is read" "running" "$(hetzner_server_status gho-ghost-blog)"
assert_eq "public IPv4 is read" "203.0.113.42" "$(hetzner_server_ipv4 gho-ghost-blog)"
assert_eq "public IPv6 /64 is turned into a host address" "2001:db8:1234:5678::1" "$(hetzner_server_ipv6 gho-ghost-blog)"

assert_ok "labels identify our deployment" hetzner_server_label_ok "gho-ghost-blog"
assert_ok "the firewall is reported as applied" hetzner_server_has_firewall "gho-ghost-blog" "9911"
assert_fail "a different firewall id is not reported as applied" hetzner_server_has_firewall "gho-ghost-blog" "1234"

assert_fail "backups are correctly reported as disabled" hetzner_backups_enabled "gho-ghost-blog"

rm -rf "$GHO_ROOT"
finish
