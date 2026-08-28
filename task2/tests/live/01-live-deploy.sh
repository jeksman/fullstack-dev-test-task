#!/usr/bin/env bash
# tests/live/01-live-deploy.sh — opt-in end-to-end test against real Hetzner.
#
# THIS TEST CREATES REAL, BILLABLE RESOURCES.
#
# It only runs when all of the following are true:
#   RUN_LIVE_TESTS=1
#   LIVE_TEST_CONFIRM=I-ACCEPT-HETZNER-CHARGES
#   HCLOUD_TOKEN, TS_AUTHKEY, GHO_DOMAIN, GHO_LE_EMAIL are set
#
# It never runs as part of `bash tests/run.sh` on its own.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"

echo "live: end-to-end deployment"

if [ "${RUN_LIVE_TESTS:-0}" != "1" ]; then
	printf '  skip  RUN_LIVE_TESTS is not 1\n'
	exit 0
fi
if [ "${LIVE_TEST_CONFIRM:-}" != "I-ACCEPT-HETZNER-CHARGES" ]; then
	printf '  skip  LIVE_TEST_CONFIRM is not set to I-ACCEPT-HETZNER-CHARGES\n'
	printf '        This test would create a billable server. Refusing.\n'
	exit 0
fi
for v in HCLOUD_TOKEN TS_AUTHKEY GHO_DOMAIN GHO_LE_EMAIL; do
	eval "value=\${$v:-}"
	if [ -z "$value" ]; then
		printf '  skip  %s is not set\n' "$v"
		exit 0
	fi
done

export GHO_NAME="${GHO_NAME:-ghost-livetest}"
export GHO_DNS_MODE="${GHO_DNS_MODE:-cloudflare}"
export GHO_HETZNER_BACKUPS=n
export GHO_LOCAL_BACKUPS=y
export GHO_REBOOT_TEST=y
export GHO_PROTECT=n

printf '  running a real deployment as %s for %s\n' "$GHO_NAME" "$GHO_DOMAIN"
assert_ok "deploy.sh completes non-interactively" \
	bash "${REPO_ROOT}/deploy.sh" --non-interactive

REPORT="${REPO_ROOT}/.ghost-hetzner/reports/final-report.json"
assert_ok "a JSON report was produced" test -s "$REPORT"
assert_eq "the deployment reports success" "SUCCESS" "$(jq -r '.deployment_status' "$REPORT")"
assert_eq "no check failed" "0" "$(jq -r '[.checks[] | select(.status=="FAIL")] | length' "$REPORT")"

IPV4="$(jq -r '.resources.public_ipv4' "$REPORT")"
assert_fail "public TCP 22 is closed on the real server" nc -z -w 8 "$IPV4" 22
assert_ok "public TCP 443 is open on the real server" nc -z -w 8 "$IPV4" 443

TSIP="$(jq -r '.resources.tailscale_ipv4' "$REPORT")"
assert_ok "the tailnet address is a CGNAT address" bash -c "case '$TSIP' in 100.*) exit 0;; *) exit 1;; esac"

DOMAIN="$(jq -r '.config.domain' "$REPORT")"
assert_ok "HTTPS serves the site" curl -fsS -o /dev/null --max-time 25 "https://${DOMAIN}/"
assert_ok "the admin page responds" curl -fsS -o /dev/null --max-time 25 "https://${DOMAIN}/ghost/"

printf '\n  The live deployment is still running and still billable.\n'
printf '  Remove it with:  bash ./deploy.sh --destroy\n\n'

finish
