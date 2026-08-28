#!/usr/bin/env bash
# tests/run.sh — the whole non-live suite, plus linting when it is available.
#
#   bash tests/run.sh                 unit + security tests, ShellCheck, shfmt
#   RUN_LIVE_TESTS=1 bash tests/run.sh   additionally runs the live test, which
#                                        creates real, billable Hetzner resources
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

green=''
red=''
bold=''
dim=''
reset=''
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	green=$'\033[32m'
	red=$'\033[31m'
	bold=$'\033[1m'
	dim=$'\033[2m'
	reset=$'\033[0m'
fi

FILES_RUN=0
FILES_FAILED=0
FAILED_LIST=""

run_file() {
	local f="$1"
	FILES_RUN=$((FILES_RUN + 1))
	printf '\n%s==> %s%s\n' "$bold" "$f" "$reset"
	if bash "$f"; then
		return 0
	fi
	FILES_FAILED=$((FILES_FAILED + 1))
	FAILED_LIST="${FAILED_LIST} ${f}"
	return 0
}

printf '%sghost-hetzner-oneclick test suite%s\n' "$bold" "$reset"
printf '%sbash %s on %s%s\n' "$dim" "$BASH_VERSION" "$(uname -s)" "$reset"

for f in tests/unit/*.sh; do
	[ -f "$f" ] || continue
	run_file "$f"
done

for f in tests/security/*.sh; do
	[ -f "$f" ] || continue
	run_file "$f"
done

# ------------------------------------------------------------------ lint ----

printf '\n%s==> lint%s\n' "$bold" "$reset"
if command -v shellcheck >/dev/null 2>&1; then
	sc_ok=1
	# Production code is checked strictly. SC1091 only reports that sourced
	# files were not followed, which is inherent to a multi-file shell project.
	if ! shellcheck -s bash -e SC1091 deploy.sh lib/*.sh remote/*.sh; then
		sc_ok=0
	fi
	# Test and mock code is checked with the cross-file-visibility noise off:
	# these files set variables that the sourced libraries consume, and quote
	# jq/sed programs that shellcheck reads as shell expansions.
	if ! shellcheck -s bash -e SC1091,SC2034,SC2016,SC2012 \
		tests/run.sh tests/lib.sh tests/unit/*.sh tests/security/*.sh \
		tests/live/*.sh tests/mocks/bin/*; then
		sc_ok=0
	fi
	if [ "$sc_ok" = "1" ]; then
		printf '  %sok%s   shellcheck clean\n' "$green" "$reset"
	else
		printf '  %sFAIL%s shellcheck reported findings\n' "$red" "$reset"
		FILES_FAILED=$((FILES_FAILED + 1))
		FAILED_LIST="${FAILED_LIST} shellcheck"
	fi
else
	printf '  %sskip%s shellcheck is not installed\n' "$dim" "$reset"
fi

if command -v shfmt >/dev/null 2>&1; then
	if shfmt -d -ln bash -i 0 deploy.sh lib remote tests >/dev/null 2>&1; then
		printf '  %sok%s   shfmt formatting is clean\n' "$green" "$reset"
	else
		printf '  %sFAIL%s shfmt reports formatting differences (run: shfmt -w -ln bash -i 0 .)\n' "$red" "$reset"
		FILES_FAILED=$((FILES_FAILED + 1))
		FAILED_LIST="${FAILED_LIST} shfmt"
	fi
else
	printf '  %sskip%s shfmt is not installed\n' "$dim" "$reset"
fi

# ------------------------------------------------------------------ live ----

printf '\n%s==> live tests%s\n' "$bold" "$reset"
if [ "${RUN_LIVE_TESTS:-0}" = "1" ]; then
	for f in tests/live/*.sh; do
		[ -f "$f" ] || continue
		run_file "$f"
	done
else
	printf '  %sskip%s live tests are opt-in: RUN_LIVE_TESTS=1 bash tests/run.sh\n' "$dim" "$reset"
	printf '  %s     they create real, billable Hetzner resources%s\n' "$dim" "$reset"
fi

# ---------------------------------------------------------------- summary ---

printf '\n%s%s%s\n' "$bold" "----------------------------------------------------------------" "$reset"
if [ "$FILES_FAILED" -eq 0 ]; then
	printf '%sALL %d TEST FILES PASSED%s\n' "$green" "$FILES_RUN" "$reset"
	exit 0
fi
printf '%s%d of %d test files FAILED:%s%s\n' "$red" "$FILES_FAILED" "$FILES_RUN" "$FAILED_LIST" "$reset"
exit 1
