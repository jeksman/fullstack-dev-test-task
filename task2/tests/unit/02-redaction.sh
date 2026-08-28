#!/usr/bin/env bash
# Secret redaction: registered values and structural credential patterns must
# never survive into anything a human or a log file sees.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
load_libs

echo "unit: secret redaction"

TOKEN="FAKEhcloudtoken1234567890abcdefABCDEF1234567890"
AUTHKEY="tskey-auth-kABCDEFGHIJ11CNTRL-abcdefghijklmnopqrstuvwxyz01"
DBPASS="FAKEdatabasePassword1234567890"

redact_register "$TOKEN"
redact_register "$AUTHKEY"
redact_register "$DBPASS"

out="$(printf 'token=%s key=%s pw=%s\n' "$TOKEN" "$AUTHKEY" "$DBPASS" | redact_stream)"
assert_not_contains "hetzner token is masked" "$out" "$TOKEN"
assert_not_contains "tailscale key is masked" "$out" "$AUTHKEY"
assert_not_contains "database password is masked" "$out" "$DBPASS"
assert_contains "the mask is visible" "$out" "***REDACTED***"

surrounding="$(printf 'prefix-%s-suffix\n' "$TOKEN" | redact_stream)"
assert_contains "surrounding text survives (prefix)" "$surrounding" "prefix-"
assert_contains "surrounding text survives (suffix)" "$surrounding" "-suffix"

# Structural patterns catch keys that were never registered.
redact_reset
GHO_SECRETS=()
unknown="$(printf 'leaked tskey-auth-kZZZZZZZZZ11CNTRL-neverregistered123\n' | redact_stream)"
assert_not_contains "unregistered tailscale keys are masked too" "$unknown" "neverregistered123"

pem="$(printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjE\n-----END OPENSSH PRIVATE KEY-----\n' | redact_stream)"
assert_not_contains "private key body is removed" "$pem" "b3BlbnNzaC1rZXktdjE"
assert_not_contains "private key header is removed" "$pem" "BEGIN OPENSSH PRIVATE KEY"

env_line="$(printf 'HCLOUD_TOKEN=someunregisteredvalue123\n' | redact_stream)"
assert_not_contains "assignment form is masked" "$env_line" "someunregisteredvalue123"

# Values with regex metacharacters must be masked literally, not treated as a
# pattern (and must not corrupt the sed program).
GHO_SECRETS=()
redact_reset
weird='pa$$w.rd*[]^\/&'
redact_register "$weird"
w="$(printf 'value=%s end\n' "$weird" | redact_stream)"
assert_not_contains "metacharacter-heavy secret is masked" "$w" "$weird"
assert_contains "line structure survives" "$w" "end"

# Short values are deliberately ignored: masking them would corrupt output.
GHO_SECRETS=()
redact_reset
redact_register "abc"
assert_eq "values under 8 characters are not registered" "0" "${#GHO_SECRETS[@]}"

# The scanner must report file names, never the secret itself.
GHO_SECRETS=()
redact_reset
redact_register "$TOKEN"
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/gho-scan.XXXXXX")"
printf 'nothing to see here\n' >"${sandbox}/clean.txt"
scan_out="$(scan_for_secrets "$sandbox" 2>&1 || true)"
assert_eq "clean tree scans clean" "" "$scan_out"
printf 'token: %s\n' "$TOKEN" >"${sandbox}/dirty.txt"
scan_out="$(scan_for_secrets "$sandbox" 2>&1 || true)"
assert_contains "leak is reported by file name" "$scan_out" "dirty.txt"
assert_not_contains "the scanner never prints the secret" "$scan_out" "$TOKEN"
rm -rf "$sandbox"
redact_reset

finish
