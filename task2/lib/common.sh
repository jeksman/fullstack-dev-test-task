#!/usr/bin/env bash
# lib/common.sh — logging, validation, retries, timeouts, temp handling.
# Bash 3.2 compatible (macOS ships 3.2 and we must run there unmodified).

GHO_ROOT="${GHO_ROOT:-}"
GHO_STATE_DIR="${GHO_STATE_DIR:-}"
GHO_LOG_FILE="${GHO_LOG_FILE:-}"
GHO_EVENT_LOG="${GHO_EVENT_LOG:-}"
GHO_TMP_DIR="${GHO_TMP_DIR:-}"

# ---------------------------------------------------------------- logging ---

_log_write() {
	local level="$1" msg="$2" ts
	ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	if [ -n "$GHO_LOG_FILE" ]; then
		printf '%s [%s] %s\n' "$ts" "$level" "$msg" | redact_stream >>"$GHO_LOG_FILE"
	fi
	if [ -n "$GHO_EVENT_LOG" ]; then
		printf '{"ts":"%s","level":"%s","msg":%s}\n' "$ts" "$level" "$(json_string "$msg")" |
			redact_stream >>"$GHO_EVENT_LOG"
	fi
}

log_debug() {
	_log_write DEBUG "$*"
	[ "${GHO_VERBOSE:-0}" = "1" ] && printf '      %s\n' "$(redact_text "$*")" >&2
	return 0
}
log_info() {
	_log_write INFO "$*"
	printf '      %s\n' "$(redact_text "$*")" >&2
}
log_warn() {
	_log_write WARN "$*"
	printf '      %s%s%s\n' "${C_YELLOW:-}" "$(redact_text "$*")" "${C_RESET:-}" >&2
}
log_error() {
	_log_write ERROR "$*"
	printf '      %s%s%s\n' "${C_RED:-}" "$(redact_text "$*")" "${C_RESET:-}" >&2
}

die() {
	log_error "$*"
	exit 1
}

# ------------------------------------------------------------------- json ---

# json_string <text> — emit a JSON string literal (quotes included).
json_string() {
	if command -v jq >/dev/null 2>&1; then
		printf '%s' "$1" | jq -Rs .
	else
		# Minimal fallback: escape backslash, quote and control characters.
		printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037')"
	fi
}

# --------------------------------------------------------------- validation -

validate_domain() {
	printf '%s' "${1:-}" |
		grep -Eq '^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$'
}

validate_email() {
	printf '%s' "${1:-}" |
		grep -Eq '^[A-Za-z0-9._%+-]+@([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'
}

# Deployment names become Hetzner resource names, a Tailscale hostname and part
# of a MySQL identifier, so the character set is deliberately narrow.
validate_deployment_name() {
	printf '%s' "${1:-}" | grep -Eq '^[a-z][a-z0-9-]{1,30}[a-z0-9]$' || return 1
	case "${1:-}" in
	*--*) return 1 ;;
	esac
	return 0
}

validate_hetzner_slug() {
	printf '%s' "${1:-}" | grep -Eq '^[a-z0-9][a-z0-9._-]{0,62}$'
}

validate_ipv4() {
	printf '%s' "${1:-}" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
	local o
	for o in $(printf '%s' "$1" | tr '.' ' '); do
		[ "$o" -le 255 ] 2>/dev/null || return 1
	done
	return 0
}

validate_tailscale_ipv4() {
	validate_ipv4 "${1:-}" || return 1
	# Tailscale CGNAT range is 100.64.0.0/10 -> 100.64.x.x .. 100.127.x.x
	printf '%s' "$1" | grep -Eq '^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.'
}

validate_ssh_pubkey() {
	printf '%s' "${1:-}" |
		grep -Eq '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com) [A-Za-z0-9+/=]{20,}( .*)?$'
}

# --------------------------------------------------------------- execution --

# run_with_timeout <seconds> <command...>
# Portable replacement for coreutils `timeout`, which macOS does not ship.
# Returns 124 on timeout.
run_with_timeout() {
	local secs="$1"
	shift
	"$@" &
	local pid=$! waited=0
	while kill -0 "$pid" 2>/dev/null; do
		if [ "$waited" -ge "$secs" ]; then
			kill -TERM "$pid" 2>/dev/null || true
			sleep 1
			kill -KILL "$pid" 2>/dev/null || true
			wait "$pid" 2>/dev/null || true
			return 124
		fi
		sleep 1
		waited=$((waited + 1))
	done
	wait "$pid"
}

# retry <attempts> <base_delay_seconds> -- <command...>
# Bounded exponential backoff, capped at 30s between attempts. Never loops
# forever: the attempt count is the only exit condition besides success.
retry() {
	local attempts="$1" delay="$2"
	shift 2
	[ "${1:-}" = "--" ] && shift
	local n=1 rc=0
	while :; do
		rc=0
		"$@" || rc=$?
		[ "$rc" -eq 0 ] && return 0
		if [ "$n" -ge "$attempts" ]; then
			log_debug "retry: giving up after ${n} attempts (rc=${rc}): $1"
			return "$rc"
		fi
		log_debug "retry: attempt ${n}/${attempts} failed (rc=${rc}), sleeping ${delay}s"
		sleep "$delay"
		delay=$((delay * 2))
		[ "$delay" -gt 30 ] && delay=30
		n=$((n + 1))
	done
}

# wait_until <timeout_seconds> <poll_interval> <command...>
# Real readiness check instead of a blind sleep.
wait_until() {
	local timeout="$1" interval="$2"
	shift 2
	local waited=0
	while [ "$waited" -lt "$timeout" ]; do
		if "$@"; then return 0; fi
		sleep "$interval"
		waited=$((waited + interval))
	done
	return 1
}

# ------------------------------------------------------------------ files ---

# write_atomic <path> — content on stdin, written via temp file + rename.
write_atomic() {
	local target="$1" tmp
	tmp="${target}.tmp.$$"
	cat >"$tmp"
	chmod 600 "$tmp"
	mv -f "$tmp" "$target"
}

# secure_temp <label> — 0600 file inside the deployment tmp dir.
secure_temp() {
	local f
	f="$(mktemp "${GHO_TMP_DIR:-${TMPDIR:-/tmp}}/${1:-gho}.XXXXXX")"
	chmod 600 "$f"
	printf '%s' "$f"
}

# ------------------------------------------------------------------- misc ---

lower() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }

# detect_os -> darwin | linux
detect_os() { lower "$(uname -s)"; }

# detect_arch -> amd64 | arm64
detect_arch() {
	case "$(uname -m)" in
	x86_64 | amd64) printf 'amd64' ;;
	arm64 | aarch64) printf 'arm64' ;;
	*) printf '%s' "$(uname -m)" ;;
	esac
}

# random_id <bytes> — lowercase hex, from the OS CSPRNG.
random_id() {
	local n="${1:-4}"
	if command -v openssl >/dev/null 2>&1; then
		openssl rand -hex "$n"
	else
		od -An -tx1 -N "$n" /dev/urandom | tr -d ' \n'
	fi
}
