#!/usr/bin/env bash
# Firewall policy rendering. The single most important invariant in this
# project: the rendered policy must never contain an inbound SSH rule.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
load_libs
use_mocks

echo "unit: firewall policy rendering"

GHO_ROOT="$(make_sandbox)"
state_paths_init
GHO_DEPLOYMENT_ID="ghost-blog-deadbeef"
GHO_HCLOUD_TOKEN="mock"
TPL="${REPO_ROOT}/templates/hetzner-firewall.json"
OUT="${GHO_STATE_DIR}/firewall-rules.json"

assert_ok "template is valid JSON" jq -e . "$TPL"
assert_ok "template has no inbound TCP 22" \
	jq -e 'all(.[]; (.direction!="in") or (.protocol!="tcp") or ((.port|tostring)!="22"))' "$TPL"
assert_ok "template has no open-ended TCP port range" \
	jq -e 'all(.[]; (.protocol!="tcp") or ((.port|tostring|test("-")) | not))' "$TPL"
assert_ok "template has no any-port rule" \
	jq -e 'all(.[]; (.port // "") != "any")' "$TPL"

assert_ok "render with ICMP succeeds" hetzner_render_firewall_rules "$TPL" "$OUT" 1
assert_eq "three rules with ICMP" "3" "$(jq 'length' "$OUT")"
assert_ok "rendered policy has port 80" jq -e 'any(.[]; (.port|tostring)=="80")' "$OUT"
assert_ok "rendered policy has port 443" jq -e 'any(.[]; (.port|tostring)=="443")' "$OUT"
assert_ok "port 80 is open to IPv4 and IPv6" \
	jq -e '.[] | select((.port|tostring)=="80") | .source_ips | index("0.0.0.0/0") and index("::/0")' "$OUT"
assert_ok "rendered policy has NO port 22" \
	jq -e 'all(.[]; (.port // "" | tostring) != "22")' "$OUT"
assert_not_contains "the literal string 22 is absent from the rendered ports" \
	"$(jq -r '[.[].port // "none"] | join(",")' "$OUT")" "22"

assert_ok "render without ICMP succeeds" hetzner_render_firewall_rules "$TPL" "$OUT" 0
assert_eq "two rules without ICMP" "2" "$(jq 'length' "$OUT")"
assert_ok "still no port 22 without ICMP" \
	jq -e 'all(.[]; (.port // "" | tostring) != "22")' "$OUT"

# A tampered template must be refused rather than shipped to the provider.
BAD="${GHO_STATE_DIR}/tampered.json"
cat >"${GHO_STATE_DIR}/bad-template.json" <<'JSON'
[
  {"direction":"in","protocol":"tcp","port":"22","source_ips":["0.0.0.0/0"],"description":"temporary SSH"},
  {"direction":"in","protocol":"tcp","port":"443","source_ips":["0.0.0.0/0"],"description":"HTTPS"}
]
JSON
assert_fail "a template containing SSH is rejected" \
	hetzner_render_firewall_rules "${GHO_STATE_DIR}/bad-template.json" "$BAD" 1

cat >"${GHO_STATE_DIR}/range-template.json" <<'JSON'
[ {"direction":"in","protocol":"tcp","port":"1-65535","source_ips":["0.0.0.0/0"],"description":"everything"} ]
JSON
assert_fail "a template with a TCP range is rejected" \
	hetzner_render_firewall_rules "${GHO_STATE_DIR}/range-template.json" "$BAD" 1

# Provider-side assertions, driven from mocked hcloud output.
assert_ok "a good firewall passes the no-SSH check" hetzner_firewall_has_no_ssh "gho-ghost-blog-fw"
assert_fail "a firewall with SSH fails the no-SSH check" hetzner_firewall_has_no_ssh "gho-bad-fw"

hetzner_render_firewall_rules "$TPL" "$OUT" 1
assert_ok "provider rules match the intended policy" hetzner_firewall_matches_policy "gho-ghost-blog-fw" "$OUT"
assert_fail "a drifted provider policy is detected" hetzner_firewall_matches_policy "gho-bad-fw" "$OUT"

rm -rf "$GHO_ROOT"
finish
