#!/usr/bin/env bash
# lib/ssh.sh — private SSH over the tunnel. Never over a public address.

GHO_SSH_KEY="${GHO_SSH_KEY:-}"       # private key used for this deployment
GHO_SSH_TARGET="${GHO_SSH_TARGET:-}" # Tailscale IPv4 of the server
GHO_SSH_USER="${GHO_SSH_USER:-ghostops}"

# ssh_assert_private_target <address>
# Structural guard: refuses anything that is not a Tailscale CGNAT address, and
# explicitly refuses the server's recorded public addresses. A bug that tried to
# reach the box over the internet fails here instead of quietly succeeding.
ssh_assert_private_target() {
	local addr="${1:-}"
	[ -n "$addr" ] || {
		log_error "no SSH target set"
		return 1
	}
	local pub4 pub6
	pub4="$(state_get 'resources.public_ipv4')"
	pub6="$(state_get 'resources.public_ipv6')"
	if [ -n "$pub4" ] && [ "$addr" = "$pub4" ]; then
		log_error "refusing to SSH to the public IPv4 address"
		return 1
	fi
	if [ -n "$pub6" ] && [ "$addr" = "$pub6" ]; then
		log_error "refusing to SSH to the public IPv6 address"
		return 1
	fi
	validate_tailscale_ipv4 "$addr" || {
		log_error "SSH target ${addr} is not a Tailscale address"
		return 1
	}
	return 0
}

# ssh_opts_build — fills the GHO_SSH_OPTS array used by every remote call.
GHO_SSH_OPTS=()
ssh_opts_build() {
	GHO_SSH_OPTS=(
		-o "UserKnownHostsFile=${GHO_KNOWN_HOSTS}"
		-o "StrictHostKeyChecking=yes"
		-o "IdentitiesOnly=yes"
		-o "IdentityFile=${GHO_SSH_KEY}"
		-o "PasswordAuthentication=no"
		-o "KbdInteractiveAuthentication=no"
		-o "PubkeyAuthentication=yes"
		-o "BatchMode=yes"
		-o "ConnectTimeout=15"
		-o "ServerAliveInterval=15"
		-o "ServerAliveCountMax=4"
		-o "LogLevel=ERROR"
	)
}

# ssh_pin_hostkey <address>
# Trust-on-first-use, but the first use happens inside an already authenticated
# WireGuard tunnel to a node the Tailscale control plane vouched for, so there is
# no plaintext window for an attacker to occupy. StrictHostKeyChecking stays on.
ssh_pin_hostkey() {
	local addr="$1" tmp
	ssh_assert_private_target "$addr" || return 1
	if grep -q "^${addr} " "$GHO_KNOWN_HOSTS" 2>/dev/null; then
		return 0
	fi
	tmp="$(secure_temp keyscan)"
	if ! retry 12 5 -- ssh_keyscan_to "$addr" "$tmp"; then
		rm -f "$tmp"
		return 1
	fi
	cat "$tmp" >>"$GHO_KNOWN_HOSTS"
	chmod 600 "$GHO_KNOWN_HOSTS"
	rm -f "$tmp"
	log_debug "pinned host key for ${addr}"
}

ssh_keyscan_to() {
	ssh-keyscan -T 10 -t ed25519 "$1" >"$2" 2>/dev/null || return 1
	[ -s "$2" ]
}

# ssh_forget_hostkey <address> — used before a rebuild, never during a normal run.
ssh_forget_hostkey() {
	local addr="$1" tmp
	tmp="$(secure_temp knownhosts)"
	grep -v "^${addr} " "$GHO_KNOWN_HOSTS" >"$tmp" 2>/dev/null || true
	mv -f "$tmp" "$GHO_KNOWN_HOSTS"
	chmod 600 "$GHO_KNOWN_HOSTS"
}

# rssh <command...> — run a command on the server over the tunnel.
rssh() {
	ssh_assert_private_target "$GHO_SSH_TARGET" || return 1
	ssh_opts_build
	# shellcheck disable=SC2029  # the command is built here on purpose
	ssh "${GHO_SSH_OPTS[@]}" "${GHO_SSH_USER}@${GHO_SSH_TARGET}" "$@"
}

# rssh_script <local_script> [args...] — pipe a script to a remote bash.
rssh_script() {
	local script="$1"
	shift
	rssh "bash -s -- $*" <"$script"
}

# rscp <local_path> <remote_path>
rscp() {
	ssh_assert_private_target "$GHO_SSH_TARGET" || return 1
	ssh_opts_build
	scp "${GHO_SSH_OPTS[@]}" "$1" "${GHO_SSH_USER}@${GHO_SSH_TARGET}:${2}"
}

# ssh_generate_key <path> <comment>
ssh_generate_key() {
	local path="$1" comment="$2"
	[ -f "$path" ] && return 0
	mkdir -p "$(dirname "$path")"
	ssh-keygen -t ed25519 -a 100 -N '' -C "$comment" -f "$path" >/dev/null 2>&1 || return 1
	chmod 600 "$path"
	chmod 644 "${path}.pub"
}

ssh_pubkey_fingerprint() {
	ssh-keygen -lf "$1" 2>/dev/null | awk '{print $2}'
}
