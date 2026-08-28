#!/usr/bin/env bash
# lib/tailscale.sh — tunnel provider: Tailscale.
#
# This file is the whole tunnel provider surface. Everything above it talks to
# tunnel_* functions only, so a second provider can be added later without
# touching the orchestrator. Only Tailscale is implemented and tested in v1.

# shellcheck disable=SC2034  # consumed by reports and by the tunnel interface
GHO_TUNNEL_PROVIDER="tailscale"

ts() { "$GHO_TAILSCALE_BIN" "$@"; }

ts_version() { ts version 2>/dev/null | head -1; }

ts_status_json() { ts status --json 2>/dev/null; }

# The operator's own machine must be on the tailnet, otherwise there is no path
# to the server at all and we must not fall back to anything public.
ts_local_connected() {
	local st
	st="$(ts_status_json)" || return 1
	printf '%s' "$st" | jq -e '.BackendState == "Running"' >/dev/null
}

ts_local_tailnet() {
	ts_status_json | jq -r '.CurrentTailnet.Name // .MagicDNSSuffix // "unknown"'
}

# ts_node_ipv4 <hostname> — the node's 100.64.0.0/10 address, or nothing.
ts_node_ipv4() {
	ts_status_json | jq -r --arg h "$1" '
		[ (.Self // empty), (.Peer // {} | .[]) ]
		| map(select((.HostName == $h) or ((.DNSName // "") | startswith($h + "."))))
		| .[0].TailscaleIPs // []
		| map(select(test("^100\\.")))
		| .[0] // empty'
}

ts_node_dnsname() {
	ts_status_json | jq -r --arg h "$1" '
		[ (.Self // empty), (.Peer // {} | .[]) ]
		| map(select(.HostName == $h))
		| .[0].DNSName // empty' | sed 's/\.$//'
}

ts_node_online() {
	ts_status_json | jq -e --arg h "$1" '
		[ (.Peer // {} | .[]) ] | any(.HostName == $h and (.Online == true))' >/dev/null
}

# ts_wait_for_node <hostname> <timeout_seconds>
# Prints the discovered Tailscale IPv4 on success.
ts_wait_for_node() {
	local host="$1" timeout="$2" waited=0 ip=""
	while [ "$waited" -lt "$timeout" ]; do
		ip="$(ts_node_ipv4 "$host" 2>/dev/null || true)"
		if [ -n "$ip" ] && validate_tailscale_ipv4 "$ip"; then
			printf '%s' "$ip"
			return 0
		fi
		sleep 5
		waited=$((waited + 5))
		[ $((waited % 30)) -eq 0 ] && log_debug "waiting for tailnet node ${host} (${waited}s/${timeout}s)"
	done
	return 1
}

# ts_ping <ip> — a real tailnet-level ping, not ICMP over the public internet.
ts_ping() {
	ts ping -c 2 --timeout 8s "$1" >/dev/null 2>&1
}

# ------------------------------------------------------- provider interface --

tunnel_name() { printf 'Tailscale'; }
tunnel_local_ready() { ts_local_connected; }
tunnel_wait_for_node() { ts_wait_for_node "$@"; }
tunnel_node_address() { ts_node_ipv4 "$1"; }
tunnel_node_hostname() { ts_node_dnsname "$1"; }
tunnel_ping() { ts_ping "$1"; }

# tunnel_access_help <hostname> <ip>
# Printed when the tunnel is up but SSH over it is refused — almost always an
# ACL problem, and never a reason to open public SSH.
tunnel_access_help() {
	cat >&2 <<HELP
      The node is on the tailnet but TCP 22 is not reachable from this machine.

        node hostname : ${1}
        node address  : ${2}

      This is a tailnet access-policy (ACL) problem, not a server problem.
      Public SSH stays closed. In the Tailscale admin console, allow your user
      to reach port 22 on this node, for example:

        {"action":"accept","src":["autogroup:member"],"dst":["${1}:22"]}

      Then continue with:  bash ./deploy.sh --resume
HELP
}
