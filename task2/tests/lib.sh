#!/usr/bin/env bash
# tests/lib.sh — a very small assertion harness. No framework, no fixtures
# directory scanning, no magic: each test file is a script that sources this.

TESTS_RUN=0
TESTS_FAILED=0

_c_green=''
_c_red=''
_c_dim=''
_c_reset=''
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	_c_green=$'\033[32m'
	_c_red=$'\033[31m'
	_c_dim=$'\033[2m'
	_c_reset=$'\033[0m'
fi

pass() {
	TESTS_RUN=$((TESTS_RUN + 1))
	printf '  %sok%s   %s\n' "$_c_green" "$_c_reset" "$1"
}

fail() {
	TESTS_RUN=$((TESTS_RUN + 1))
	TESTS_FAILED=$((TESTS_FAILED + 1))
	printf '  %sFAIL%s %s\n' "$_c_red" "$_c_reset" "$1"
	[ -n "${2:-}" ] && printf '       %s%s%s\n' "$_c_dim" "$2" "$_c_reset"
	return 0
}

# assert_ok <description> <command...>
assert_ok() {
	local desc="$1"
	shift
	local out rc=0
	out="$("$@" 2>&1)" || rc=$?
	if [ "$rc" -eq 0 ]; then pass "$desc"; else fail "$desc" "exit ${rc}: ${out}"; fi
}

# assert_fail <description> <command...>
assert_fail() {
	local desc="$1"
	shift
	local out rc=0
	out="$("$@" 2>&1)" || rc=$?
	if [ "$rc" -ne 0 ]; then pass "$desc"; else fail "$desc" "expected failure, got success: ${out}"; fi
}

# assert_eq <description> <expected> <actual>
assert_eq() {
	if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

# assert_contains <description> <haystack> <needle>
assert_contains() {
	case "$2" in
	*"$3"*) pass "$1" ;;
	*) fail "$1" "[$3] not found in output" ;;
	esac
}

# assert_not_contains <description> <haystack> <needle>
assert_not_contains() {
	case "$2" in
	*"$3"*) fail "$1" "[$3] must not appear" ;;
	*) pass "$1" ;;
	esac
}

finish() {
	printf '  %s%d run, %d failed%s\n' "$_c_dim" "$TESTS_RUN" "$TESTS_FAILED" "$_c_reset"
	[ "$TESTS_FAILED" -eq 0 ]
}

# ------------------------------------------------------------- sandboxing ---

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# make_sandbox — a throwaway GHO_ROOT with the real templates linked in.
make_sandbox() {
	local dir
	dir="$(mktemp -d "${TMPDIR:-/tmp}/gho-test.XXXXXX")"
	ln -s "${REPO_ROOT}/templates" "${dir}/templates"
	ln -s "${REPO_ROOT}/lib" "${dir}/lib"
	ln -s "${REPO_ROOT}/remote" "${dir}/remote"
	printf '%s' "$dir"
}

# load_libs — source the project libraries against the current GHO_ROOT.
load_libs() {
	# shellcheck disable=SC1091
	. "${REPO_ROOT}/lib/redact.sh"
	# shellcheck disable=SC1091
	. "${REPO_ROOT}/lib/ui.sh"
	# shellcheck disable=SC1091
	. "${REPO_ROOT}/lib/common.sh"
	# shellcheck disable=SC1091
	. "${REPO_ROOT}/lib/state.sh"
	# shellcheck disable=SC1091
	. "${REPO_ROOT}/lib/tools.sh"
	# shellcheck disable=SC1091
	. "${REPO_ROOT}/lib/hetzner.sh"
	# shellcheck disable=SC1091
	. "${REPO_ROOT}/lib/tailscale.sh"
	# shellcheck disable=SC1091
	. "${REPO_ROOT}/lib/dns.sh"
	# shellcheck disable=SC1091
	. "${REPO_ROOT}/lib/ssh.sh"
	# shellcheck disable=SC1091
	. "${REPO_ROOT}/lib/verify.sh"
	# shellcheck disable=SC1091
	. "${REPO_ROOT}/versions.env"
}

use_mocks() {
	PATH="${REPO_ROOT}/tests/mocks/bin:${PATH}"
	export PATH
	export GHO_MOCK_FIXTURES="${REPO_ROOT}/tests/mocks/fixtures"
}
