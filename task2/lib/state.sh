#!/usr/bin/env bash
# lib/state.sh — atomic deployment state, locking, stage bookkeeping.
#
# The state file is the resume contract. It holds identifiers and decisions and
# never holds a credential: state_put refuses to store any value that has been
# registered as a secret.

GHO_STATE_FILE=""
GHO_LOCK_DIR=""

state_paths_init() {
	GHO_STATE_DIR="${GHO_ROOT}/.ghost-hetzner"
	GHO_STATE_FILE="${GHO_STATE_DIR}/state.json"
	GHO_LOCK_DIR="${GHO_STATE_DIR}/lock"
	GHO_TMP_DIR="${GHO_STATE_DIR}/tmp"
	GHO_LOG_DIR="${GHO_STATE_DIR}/logs"
	GHO_REPORT_DIR="${GHO_STATE_DIR}/reports"
	GHO_KNOWN_HOSTS="${GHO_STATE_DIR}/known_hosts"

	mkdir -p "$GHO_STATE_DIR" "$GHO_TMP_DIR" "$GHO_LOG_DIR" "$GHO_REPORT_DIR"
	chmod 700 "$GHO_STATE_DIR" "$GHO_TMP_DIR" "$GHO_LOG_DIR" "$GHO_REPORT_DIR"
	[ -f "$GHO_KNOWN_HOSTS" ] || : >"$GHO_KNOWN_HOSTS"
	chmod 600 "$GHO_KNOWN_HOSTS"
}

# ------------------------------------------------------------------- lock ---

state_lock() {
	local waited=0
	while ! mkdir "$GHO_LOCK_DIR" 2>/dev/null; do
		local owner=""
		[ -f "${GHO_LOCK_DIR}/pid" ] && owner="$(cat "${GHO_LOCK_DIR}/pid" 2>/dev/null || true)"
		if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
			log_warn "removing stale deployment lock from pid ${owner}"
			rm -rf "$GHO_LOCK_DIR"
			continue
		fi
		[ "$waited" -ge 30 ] && die "another deployment holds the lock (${GHO_LOCK_DIR}); pid ${owner:-unknown}"
		sleep 2
		waited=$((waited + 2))
	done
	printf '%s' "$$" >"${GHO_LOCK_DIR}/pid"
}

state_unlock() {
	[ -n "$GHO_LOCK_DIR" ] || return 0
	[ -f "${GHO_LOCK_DIR}/pid" ] || return 0
	[ "$(cat "${GHO_LOCK_DIR}/pid" 2>/dev/null || true)" = "$$" ] || return 0
	rm -rf "$GHO_LOCK_DIR"
}

# ------------------------------------------------------------------- data ---

state_exists() { [ -s "$GHO_STATE_FILE" ]; }

state_init() {
	local deployment_id="$1" name="$2"
	state_exists && return 0
	jq -n --arg id "$deployment_id" --arg name "$name" \
		--arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
			schema: 1,
			deployment_id: $id,
			deployment_name: $name,
			created_at: $ts,
			updated_at: $ts,
			stage: "init",
			stages: {},
			config: {},
			resources: {},
			checks: []
		}' | write_atomic "$GHO_STATE_FILE"
}

_state_write() {
	# stdin: jq filter applied to the current document.
	local filter="$1"
	shift
	local out
	out="$(jq "$@" "$filter" "$GHO_STATE_FILE")" ||
		die "failed to update state file"
	printf '%s\n' "$out" | jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.updated_at = $ts' |
		write_atomic "$GHO_STATE_FILE"
}

# state_put <dotted.path> <value>   — string value, secret-guarded.
state_put() {
	local path="$1" value="$2" s
	for s in ${GHO_SECRETS+"${GHO_SECRETS[@]}"}; do
		[ "$value" = "$s" ] && die "refusing to write a registered secret into the state file (${path})"
	done
	_state_write ".${path} = \$v" --arg v "$value"
}

# state_put_raw <dotted.path> <json>  — numbers, booleans, objects.
state_put_raw() {
	_state_write ".${1} = \$v" --argjson v "$2"
}

# state_get <dotted.path> [default]
state_get() {
	local v
	state_exists || {
		printf '%s' "${2:-}"
		return 0
	}
	v="$(jq -r ".${1} // empty" "$GHO_STATE_FILE" 2>/dev/null || true)"
	[ -n "$v" ] || v="${2:-}"
	printf '%s' "$v"
}

# ----------------------------------------------------------------- stages ---

stage_mark() {
	state_exists || return 0
	_state_write ".stages[\$k] = \$v | .stage = \$k" --arg k "$1" --arg v "$2"
}

stage_is_done() { [ "$(state_get "stages.\"${1}\"")" = "done" ]; }

# stage_should_run <stage>
# Idempotency gate: a completed stage is skipped unless GHO_FORCE_STAGE names it.
stage_should_run() {
	[ "${GHO_FORCE_STAGE:-}" = "$1" ] && return 0
	stage_is_done "$1" && return 1
	return 0
}

state_last_done_stage() {
	local ordered="$1" s last=""
	for s in $ordered; do
		stage_is_done "$s" && last="$s"
	done
	printf '%s' "$last"
}

# ----------------------------------------------------------------- checks ---

# check_record <name> <status> <detail>
check_record() {
	state_exists || return 0
	# shellcheck disable=SC2016  # $n/$s/$d/$t are jq variables, not shell ones
	_state_write '.checks += [{name:$n, status:$s, detail:$d, ts:$t}]' \
		--arg n "$1" --arg s "$2" --arg d "$3" \
		--arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

check_status() {
	state_exists || return 1
	jq -r --arg n "$1" '[.checks[] | select(.name==$n)] | last | .status // empty' "$GHO_STATE_FILE"
}
