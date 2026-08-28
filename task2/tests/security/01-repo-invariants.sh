#!/usr/bin/env bash
# Repository security invariants. These fail the build if the code ever grows a
# public SSH path, a hardcoded credential, or a weakened sshd directive.
#
# The forbidden strings are assembled at runtime so that this file does not
# itself contain the patterns it forbids.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

echo "security: repository invariants"

cd "$REPO_ROOT" || exit 1

# Production sources: everything that ships and runs. Tests are excluded here
# because they deliberately contain negative examples.
# Code and configuration that actually runs. Prose is scanned separately: the
# documentation legitimately names the directives it forbids.
PROD="deploy.sh lib remote templates versions.env"
ALL="deploy.sh lib remote templates tests docs versions.env README.md SECURITY.md CHANGELOG.md"

# shellcheck disable=SC2086  # $PROD and $ALL are deliberate path lists
prod_grep() { grep -rn "$@" $PROD 2>/dev/null; }
# shellcheck disable=SC2086
prose_grep() { grep -rn "$@" README.md SECURITY.md docs 2>/dev/null; }
# shellcheck disable=SC2086
all_grep() { grep -rn "$@" $ALL 2>/dev/null; }

BAD_PW="PasswordAuthentication $(printf 'yes')"
BAD_ROOT="PermitRootLogin $(printf 'yes')"
BAD_ROOT2="PermitRootLogin $(printf 'prohibit-password')"
BAD_EMPTY="PermitEmptyPasswords $(printf 'yes')"

hits="$(prod_grep -F "$BAD_PW" || true)"
assert_eq "no directive enabling SSH password authentication" "" "$hits"
hits="$(prod_grep -F "$BAD_ROOT" || true)"
assert_eq "no directive enabling root SSH login" "" "$hits"
hits="$(prod_grep -F "$BAD_ROOT2" || true)"
assert_eq "no directive permitting root with a key" "" "$hits"
hits="$(prod_grep -F "$BAD_EMPTY" || true)"
assert_eq "no directive permitting empty passwords" "" "$hits"

# The hardening we require must be present, not merely not-negated.
assert_ok "hardening sets PermitRootLogin no" \
	bash -c "grep -rqF 'PermitRootLogin no' templates remote"
assert_ok "hardening sets PasswordAuthentication no" \
	bash -c "grep -rqF 'PasswordAuthentication no' templates remote"
assert_ok "hardening sets PermitEmptyPasswords no" \
	bash -c "grep -rqF 'PermitEmptyPasswords no' templates remote"
assert_ok "hardening sets KbdInteractiveAuthentication no" \
	bash -c "grep -rqF 'KbdInteractiveAuthentication no' templates remote"

# Provider firewall: no inbound SSH, anywhere, in any rules file.
assert_ok "the shipped firewall policy has no inbound TCP 22" \
	jq -e 'all(.[]; (.direction!="in") or (.protocol!="tcp") or ((.port|tostring)!="22"))' \
	templates/hetzner-firewall.json
hits="$(grep -rn '"port"[[:space:]]*:[[:space:]]*"22"' templates 2>/dev/null || true)"
assert_eq "no template declares port 22" "" "$hits"

# Host firewall: SSH may only ever be allowed on the tunnel interface.
ufw_ssh="$(grep -rn 'ufw allow' templates remote 2>/dev/null | grep -E '(^|[^0-9])22(/tcp)?([^0-9]|$)|ufw allow ssh' || true)"
bad_ufw="$(printf '%s\n' "$ufw_ssh" | grep -v 'tailscale0' | grep -v '^$' || true)"
assert_eq "every ufw SSH rule is bound to tailscale0" "" "$bad_ufw"

# No shell tracing: it would echo secrets into the logs.
hits="$(all_grep -E '^[[:space:]]*set -[a-zA-Z]*x' || true)"
assert_eq "no shell tracing anywhere in the repository" "" "$hits"

# No private key material committed.
hits="$(all_grep -E -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' | grep -v 'redact\|verify\|02-redaction\|01-validation\|SECURITY.md' || true)"
assert_eq "no private key blocks in the repository" "" "$hits"

# No real Tailscale auth keys. Test fixtures use obviously fake values, and
# real keys have a 22+ character secret half.
hits="$(all_grep -E 'tskey-auth-k[A-Za-z0-9]{10,}CNTRL-[A-Za-z0-9]{22,}' | grep -v 'shouldneverappear\|neverregistered\|abcdefghijklmnopqrstuvwxyz' || true)"
assert_eq "no plausible Tailscale auth key is committed" "" "$hits"

# No hardcoded Hetzner-shaped tokens assigned to a variable.
hits="$(all_grep -E '(HCLOUD_TOKEN|CF_API_TOKEN|API_TOKEN|TOKEN)=["'"'"']?[A-Za-z0-9]{40,}' | grep -v 'FAKE' || true)"
assert_eq "no hardcoded API token assignments" "" "$hits"

# No hardcoded passwords.
hits="$(all_grep -iE '(password|passwd|dbpass)[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"'$][^"'"'"']{7,}["'"'"']' |
	grep -vi 'PasswordAuthentication\|password=%s\|password = \$\|placeholder\|mock\|example\|FAKE' || true)"
assert_eq "no hardcoded passwords" "" "$hits"

# SSH must never be aimed at a public address. Any ssh/scp invocation that
# references a public-IP state key is a design violation.
# The leading character class keeps identifiers like check_public_ssh_isolation
# from matching: only a real ssh/scp invocation counts.
hits="$(prod_grep -E '(^|[^A-Za-z_-])(ssh|scp) [^|;]*(public_ipv4|public_ipv6|PUBLIC_IP)' || true)"
assert_eq "no ssh/scp command targets a public address" "" "$hits"
hits="$(prose_grep -E '(^|[^A-Za-z_-])(ssh|scp) [^|;]*\$\{?(public_ipv4|PUBLIC_IP)' || true)"
assert_eq "no documented command targets a public address" "" "$hits"
hits="$(prod_grep -E 'StrictHostKeyChecking[= ]*no' || true)"
assert_eq "host key checking is never disabled" "" "$hits"
hits="$(prod_grep -E 'curl[^|;]*(-k|--insecure)( |$)' || true)"
assert_eq "TLS verification is never disabled" "$(printf '')" "$hits"

# The guard function that enforces the invariant must exist and be used.
assert_ok "the private-target guard exists" bash -c "grep -q 'ssh_assert_private_target' lib/ssh.sh"
assert_ok "rssh calls the guard" \
	bash -c "awk '/^rssh\(\)/,/^}/' lib/ssh.sh | grep -q ssh_assert_private_target"
assert_ok "rscp calls the guard" \
	bash -c "awk '/^rscp\(\)/,/^}/' lib/ssh.sh | grep -q ssh_assert_private_target"

# Secrets must not be written to the state file.
assert_ok "state_put refuses registered secrets" \
	bash -c "grep -q 'refusing to write a registered secret' lib/state.sh"

# Every shipped script must be executable and syntactically valid.
for f in deploy.sh remote/*.sh tests/run.sh; do
	assert_ok "executable: ${f}" test -x "$f"
	assert_ok "valid bash: ${f}" bash -n "$f"
done
for f in lib/*.sh; do
	assert_ok "valid bash: ${f}" bash -n "$f"
done

# Temporary files must be unpredictable.
hits="$(prod_grep -E '>[[:space:]]*/tmp/[a-z-]+\.(txt|json|key|sh)' || true)"
assert_eq "no predictable temporary file names" "" "$hits"

finish
