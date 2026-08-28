#!/usr/bin/env bash
# lib/redact.sh — secret registry and output redaction.
#
# Nothing in this project may print a credential. Every value that is secret is
# registered here once, and all human-facing output plus every log file is piped
# through redact_stream. Secrets are never passed to sed/grep on the command
# line (that would expose them in `ps`), only through 0600 script files.

GHO_REDACT_MASK="***REDACTED***"

# Registered literal secrets. Bash 3.2 compatible plain array.
GHO_SECRETS=()

# redact_register <value>
# Values shorter than 8 characters are ignored: masking them would corrupt
# unrelated output without meaningfully protecting anything.
redact_register() {
	local value="${1:-}"
	[ ${#value} -ge 8 ] || return 0
	local existing
	for existing in ${GHO_SECRETS+"${GHO_SECRETS[@]}"}; do
		[ "$existing" = "$value" ] && return 0
	done
	GHO_SECRETS+=("$value")
}

# _redact_literal_bre <value>
# Turns an arbitrary string into a POSIX basic regular expression that matches
# it literally, by bracketing every character. Safe for BSD and GNU sed.
_redact_literal_bre() {
	printf '%s' "$1" | sed -e 's/[^^]/[&]/g' -e 's/\^/\\^/g'
}

# _redact_script_file
# Writes the sed program used for redaction into a 0600 file and echoes its
# path. Caller owns removal (or lets the global cleanup trap handle it).
_redact_script_file() {
	local f
	f="$(mktemp "${TMPDIR:-/tmp}/gho-redact.XXXXXX")" || return 1
	chmod 600 "$f"
	{
		# Structural patterns that hold even for values we never registered.
		printf '%s\n' 's/tskey-[A-Za-z0-9_-][A-Za-z0-9_-]*/tskey-'"$GHO_REDACT_MASK"'/g'
		# One rule per name: BSD sed has no \| alternation in basic regexes.
		local var
		for var in HCLOUD_TOKEN TS_AUTHKEY CF_API_TOKEN MYSQL_PWD SMTP_PASSWORD GHO_TS_AUTHKEY GHO_HCLOUD_TOKEN GHO_CF_TOKEN; do
			printf 's/%s=[^ ]*/%s=%s/g\n' "$var" "$var" "$GHO_REDACT_MASK"
		done
		# shellcheck disable=SC1003  # trailing backslash is sed's 'change' syntax
		printf '%s\n' '/-----BEGIN [A-Z ]*PRIVATE KEY-----/,/-----END [A-Z ]*PRIVATE KEY-----/c\'
		printf '%s\n' "$GHO_REDACT_MASK"
		local s bre
		for s in ${GHO_SECRETS+"${GHO_SECRETS[@]}"}; do
			bre="$(_redact_literal_bre "$s")"
			printf 's/%s/%s/g\n' "$bre" "$GHO_REDACT_MASK"
		done
	} >"$f"
	printf '%s' "$f"
}

# The sed program is rebuilt only when the secret registry changes, so logging
# a line costs one fork instead of three.
_GHO_REDACT_CACHE=""
_GHO_REDACT_CACHE_N="-1"

# redact_stream — filter stdin to stdout, masking every known secret.
redact_stream() {
	local n="${#GHO_SECRETS[@]}"
	if [ "$n" != "$_GHO_REDACT_CACHE_N" ] || [ ! -s "$_GHO_REDACT_CACHE" ]; then
		_GHO_REDACT_CACHE="$(_redact_script_file)" || {
			cat
			return 0
		}
		_GHO_REDACT_CACHE_N="$n"
	fi
	sed -f "$_GHO_REDACT_CACHE"
}

# redact_reset — drop the cached program (used by tests and by cleanup).
redact_reset() {
	[ -n "$_GHO_REDACT_CACHE" ] && rm -f "$_GHO_REDACT_CACHE"
	_GHO_REDACT_CACHE=""
	_GHO_REDACT_CACHE_N="-1"
	return 0
}

# redact_text <text> — masked single string on stdout.
redact_text() {
	printf '%s\n' "$1" | redact_stream
}

# redact_pattern_file — writes registered secrets (one per line) to a 0600 file
# for use with `grep -F -f`. Used by the leakage scanner so that no secret ever
# appears in a command line. Echoes the path; empty registry yields exit 1.
redact_pattern_file() {
	[ ${#GHO_SECRETS[@]} -gt 0 ] 2>/dev/null || return 1
	local f s
	f="$(mktemp "${TMPDIR:-/tmp}/gho-scan.XXXXXX")" || return 1
	chmod 600 "$f"
	for s in ${GHO_SECRETS+"${GHO_SECRETS[@]}"}; do
		printf '%s\n' "$s"
	done >"$f"
	printf '%s' "$f"
}
