#!/usr/bin/env bash
# lib/ui.sh — terminal presentation and interactive prompts.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
	C_RESET=$'\033[0m'
	C_BOLD=$'\033[1m'
	C_DIM=$'\033[2m'
	C_RED=$'\033[31m'
	C_GREEN=$'\033[32m'
	C_YELLOW=$'\033[33m'
	C_BLUE=$'\033[34m'
	C_CYAN=$'\033[36m'
else
	C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN=''
fi

GHO_TOTAL_STEPS="${GHO_TOTAL_STEPS:-12}"
GHO_CURRENT_STEP=""

banner() {
	printf '%s\n' "${C_BOLD}${C_CYAN}"
	cat <<'ART'
  ghost-hetzner-oneclick
  Ghost on Hetzner Cloud. Public SSH is never opened.
ART
	printf '%s\n' "${C_RESET}"
}

# step <index> <title>
step() {
	# shellcheck disable=SC2034  # read by deploy.sh error reporting
	GHO_CURRENT_STEP="$2"
	printf '\n%s[%02d/%02d]%s %s%s%s\n' \
		"$C_BLUE" "$1" "$GHO_TOTAL_STEPS" "$C_RESET" "$C_BOLD" "$2" "$C_RESET"
	_log_write INFO "STEP [$1/$GHO_TOTAL_STEPS] $2"
}

_status_line() {
	local color="$1" word="$2" text="$3"
	printf '      %s%-7s%s %s\n' "$color" "$word" "$C_RESET" "$text"
	_log_write INFO "$word: $text"
}

status_pass() { _status_line "$C_GREEN" "PASS" "$*"; }
status_fail() { _status_line "$C_RED" "FAIL" "$*"; }
status_skip() { _status_line "$C_DIM" "SKIP" "$*"; }
status_warn() { _status_line "$C_YELLOW" "WARNING" "$*"; }

note() { printf '      %s%s%s\n' "$C_DIM" "$(redact_text "$*")" "$C_RESET"; }

hr() { printf '      %s%s%s\n' "$C_DIM" "----------------------------------------------------------------" "$C_RESET"; }

# ------------------------------------------------------------------ input ---

_interactive() { [ "${GHO_NON_INTERACTIVE:-0}" != "1" ] && [ -t 0 ]; }

# ask <prompt> <default> <validator|""> -> value on stdout
ask() {
	local prompt="$1" default="${2:-}" validator="${3:-}" answer=""
	while :; do
		if ! _interactive; then
			answer="$default"
			[ -n "$answer" ] || die "non-interactive mode: no value supplied for '$prompt'"
		else
			if [ -n "$default" ]; then
				printf '      %s [%s]: ' "$prompt" "$default" >&2
			else
				printf '      %s: ' "$prompt" >&2
			fi
			IFS= read -r answer || answer=""
			[ -n "$answer" ] || answer="$default"
		fi
		if [ -z "$answer" ]; then
			printf '      %sA value is required.%s\n' "$C_RED" "$C_RESET" >&2
			_interactive || exit 1
			continue
		fi
		if [ -n "$validator" ] && ! "$validator" "$answer"; then
			printf '      %sInvalid value.%s\n' "$C_RED" "$C_RESET" >&2
			_interactive || exit 1
			continue
		fi
		printf '%s' "$answer"
		return 0
	done
}

# ask_secret <prompt> — hidden input, never echoed, never logged.
ask_secret() {
	local prompt="$1" answer=""
	_interactive || die "non-interactive mode: secret '$prompt' must come from the environment"
	while [ -z "$answer" ]; do
		printf '      %s (hidden): ' "$prompt" >&2
		# shellcheck disable=SC2162  # -r is set; -s suppresses echo
		if ! read -rs answer; then answer=""; fi
		printf '\n' >&2
		[ -n "$answer" ] || printf '      %sA value is required.%s\n' "$C_RED" "$C_RESET" >&2
	done
	printf '%s' "$answer"
}

# ask_yes_no <prompt> <default y|n>
ask_yes_no() {
	local prompt="$1" default="${2:-n}" answer hint
	case "$default" in y | Y) hint="Y/n" ;; *) hint="y/N" ;; esac
	while :; do
		if ! _interactive; then
			answer="$default"
		else
			printf '      %s [%s]: ' "$prompt" "$hint" >&2
			IFS= read -r answer || answer=""
			[ -n "$answer" ] || answer="$default"
		fi
		case "$(lower "$answer")" in
		y | yes) return 0 ;;
		n | no) return 1 ;;
		*) printf '      %sAnswer y or n.%s\n' "$C_RED" "$C_RESET" >&2 ;;
		esac
	done
}

# ask_choice <prompt> <default> <option>...
# Prints the chosen option. Options are shown as a numbered menu; typing the
# literal value is also accepted.
ask_choice() {
	local prompt="$1" default="$2"
	shift 2
	local opts="$*" i opt answer
	if ! _interactive; then
		printf '%s' "$default"
		return 0
	fi
	printf '      %s\n' "$prompt" >&2
	i=1
	for opt in $opts; do
		printf '        %2d) %s%s\n' "$i" "$opt" \
			"$([ "$opt" = "$default" ] && printf ' (default)' || true)" >&2
		i=$((i + 1))
	done
	while :; do
		printf '      Choice [%s]: ' "$default" >&2
		IFS= read -r answer || answer=""
		[ -n "$answer" ] || answer="$default"
		if printf '%s' "$answer" | grep -Eq '^[0-9]+$'; then
			i=1
			for opt in $opts; do
				if [ "$i" = "$answer" ]; then
					printf '%s' "$opt"
					return 0
				fi
				i=$((i + 1))
			done
		else
			for opt in $opts; do
				if [ "$opt" = "$answer" ]; then
					printf '%s' "$opt"
					return 0
				fi
			done
		fi
		printf '      %sNot one of the listed options.%s\n' "$C_RED" "$C_RESET" >&2
	done
}

# confirm_exact <expected> <prompt> — destructive-action guard.
confirm_exact() {
	local expected="$1" prompt="$2" answer
	_interactive || die "non-interactive mode: refusing to confirm '$expected' automatically"
	printf '      %s\n      Type %s%s%s to continue: ' "$prompt" "$C_BOLD" "$expected" "$C_RESET" >&2
	IFS= read -r answer || answer=""
	[ "$answer" = "$expected" ]
}

kv() { printf '      %-24s %s\n' "$1" "$(redact_text "$2")"; }
