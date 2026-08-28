#!/usr/bin/env bash
# lib/hetzner.sh — every Hetzner Cloud interaction lives here.
#
# All calls go through the official hcloud CLI. The token is passed via the
# HCLOUD_TOKEN environment variable only, never on a command line.

GHO_LABEL_MANAGED="managed-by=ghost-hetzner-oneclick"

hcloud_labels() {
	printf '%s\n%s\n%s\n%s' \
		"$GHO_LABEL_MANAGED" \
		"deployment-id=${GHO_DEPLOYMENT_ID}" \
		"application=ghost" \
		"environment=production"
}

# hc <args...> — hcloud with the token supplied through the environment.
hc() {
	HCLOUD_TOKEN="$GHO_HCLOUD_TOKEN" hcloud "$@"
}

hetzner_validate_token() {
	# A cheap authenticated read. Any auth problem surfaces here, before we
	# create anything billable.
	hc server list -o json >/dev/null 2>&1
}

hetzner_locations() {
	hc location list -o json | jq -r '.[].name' | sort
}

hetzner_location_describe() {
	hc location list -o json | jq -r --arg n "$1" '.[] | select(.name==$n) | "\(.city), \(.country) (\(.network_zone))"'
}

hetzner_server_types_json() {
	hc server-type list -o json
}

# hetzner_suitable_server_types <min_gb> <architecture>
hetzner_suitable_server_types() {
	hetzner_server_types_json | jq -r --argjson gb "$1" --arg arch "$2" '
		[ .[]
		  | select((.deprecation // null) == null)
		  | select(.architecture == $arch)
		  | select(.memory >= $gb)
		] | sort_by(.memory, .cores) | .[].name'
}

hetzner_server_type_info() {
	hetzner_server_types_json | jq -r --arg n "$1" '
		.[] | select(.name==$n)
		| "cores=\(.cores) memory=\(.memory)GB disk=\(.disk)GB arch=\(.architecture) cpu=\(.cpu_type)"'
}

hetzner_server_type_price() {
	hetzner_server_types_json | jq -r --arg n "$1" --arg loc "$2" '
		.[] | select(.name==$n) | .prices[]? | select(.location==$loc)
		| "\(.price_monthly.gross) EUR/month gross"' 2>/dev/null | head -1
}

hetzner_server_type_arch() {
	hetzner_server_types_json | jq -r --arg n "$1" '.[] | select(.name==$n) | .architecture'
}

hetzner_image_exists() {
	hc image list -o json --type system 2>/dev/null |
		jq -e --arg n "$1" 'any(.[]; .name == $n)' >/dev/null
}

# ---------------------------------------------------------------- firewall --

# hetzner_render_firewall_rules <template> <out> <allow_icmp:0|1>
hetzner_render_firewall_rules() {
	local tpl="$1" out="$2" icmp="${3:-1}"
	local rendered
	if [ "$icmp" = "1" ]; then
		rendered="$(jq '.' "$tpl")"
	else
		rendered="$(jq '[ .[] | select(.protocol != "icmp") ]' "$tpl")"
	fi
	# Hard invariant: the rendered policy may never expose SSH, and may never
	# contain an open-ended TCP port range.
	printf '%s\n' "$rendered" | jq -e '
		all(.[]; (.direction != "in") or (.protocol != "tcp") or
		         ((.port | tostring) != "22" and (.port | tostring | test("^(any|.*-.*)$") | not)))
	' >/dev/null || {
		log_error "refusing to render a firewall policy that exposes SSH or a TCP range"
		return 1
	}
	printf '%s\n' "$rendered" >"$out"
}

hetzner_firewall_exists() {
	hc firewall describe "$1" -o json >/dev/null 2>&1
}

hetzner_create_firewall() {
	local name="$1" rules_file="$2" label
	if hetzner_firewall_exists "$name"; then
		log_info "firewall ${name} already exists, reusing"
	else
		set -- firewall create --name "$name" --rules-file "$rules_file"
		for label in $(hcloud_labels); do set -- "$@" --label "$label"; done
		hc "$@" >/dev/null || return 1
	fi
	hc firewall describe "$name" -o json | jq -r '.id'
}

hetzner_firewall_rules_json() {
	hc firewall describe "$1" -o json | jq '.rules'
}

# hetzner_firewall_has_no_ssh <name>
hetzner_firewall_has_no_ssh() {
	hetzner_firewall_rules_json "$1" | jq -e '
		all(.[]; (.direction != "in") or (.protocol != "tcp") or ((.port|tostring) != "22"))
	' >/dev/null
}

# hetzner_firewall_matches_policy <name> <expected_rules_file>
# Compares the inbound policy set actually stored at Hetzner against what we
# intended to apply, ignoring key ordering and description text.
hetzner_firewall_matches_policy() {
	local name="$1" expected="$2" a b
	a="$(hetzner_firewall_rules_json "$name" |
		jq -S '[ .[] | select(.direction=="in") | {protocol, port: (.port // null | tostring), source_ips: (.source_ips|sort)} ] | sort')"
	b="$(jq -S '[ .[] | select(.direction=="in") | {protocol, port: (.port // null | tostring), source_ips: (.source_ips|sort)} ] | sort' "$expected")"
	[ "$a" = "$b" ]
}

hetzner_firewall_applied_to() {
	hc firewall describe "$1" -o json |
		jq -r '.applied_to[]? | select(.type=="server") | .server.id // .server' 2>/dev/null
}

# ------------------------------------------------------------------ ssh key -

hetzner_ssh_key_exists() { hc ssh-key describe "$1" -o json >/dev/null 2>&1; }

hetzner_create_ssh_key() {
	local name="$1" pubkey_file="$2" label
	if ! hetzner_ssh_key_exists "$name"; then
		set -- ssh-key create --name "$name" --public-key-from-file "$pubkey_file"
		for label in $(hcloud_labels); do set -- "$@" --label "$label"; done
		hc "$@" >/dev/null || return 1
	fi
	hc ssh-key describe "$name" -o json | jq -r '.id'
}

# ------------------------------------------------------------------- server -

hetzner_server_exists() { hc server describe "$1" -o json >/dev/null 2>&1; }

hetzner_server_json() { hc server describe "$1" -o json; }

hetzner_server_status() { hetzner_server_json "$1" | jq -r '.status'; }

hetzner_server_ipv4() { hetzner_server_json "$1" | jq -r '.public_net.ipv4.ip // empty'; }

hetzner_server_ipv6() {
	# Hetzner assigns a /64; the usable host address we publish is ::1 in it.
	hetzner_server_json "$1" | jq -r '.public_net.ipv6.ip // empty' |
		sed -e 's|/64$||' -e 's|::$|::1|'
}

# hetzner_create_server <name> <type> <image> <location> <firewall_id>
#                       <user_data_file> <ssh_key_name_or_empty>
hetzner_create_server() {
	local name="$1" type="$2" image="$3" location="$4" fw="$5" udata="$6" sshkey="${7:-}"
	local label
	if hetzner_server_exists "$name"; then
		log_info "server ${name} already exists, reusing"
		return 0
	fi
	# The firewall is attached as part of the create request: the server has no
	# window of existence during which it is unfiltered.
	set -- server create \
		--name "$name" \
		--type "$type" \
		--image "$image" \
		--location "$location" \
		--firewall "$fw" \
		--user-data-from-file "$udata" \
		--start-after-create
	[ -n "$sshkey" ] && set -- "$@" --ssh-key "$sshkey"
	for label in $(hcloud_labels); do set -- "$@" --label "$label"; done
	hc "$@" >/dev/null
}

hetzner_server_has_firewall() {
	hetzner_server_json "$1" | jq -e --arg fw "$2" \
		'any(.public_net.firewalls[]?; (.id|tostring) == $fw and .status == "applied")' >/dev/null
}

hetzner_server_label_ok() {
	hetzner_server_json "$1" | jq -e --arg id "$GHO_DEPLOYMENT_ID" \
		'.labels["managed-by"] == "ghost-hetzner-oneclick" and .labels["deployment-id"] == $id' >/dev/null
}

hetzner_enable_backups() { hc server enable-backup "$1" >/dev/null 2>&1; }

hetzner_backups_enabled() {
	hetzner_server_json "$1" | jq -e '.backup_window != null and .backup_window != ""' >/dev/null
}

hetzner_enable_protection() { hc server enable-protection "$1" delete >/dev/null 2>&1; }
hetzner_disable_protection() { hc server disable-protection "$1" delete >/dev/null 2>&1; }

hetzner_poweroff() { hc server poweroff "$1" >/dev/null 2>&1; }
hetzner_reboot() { hc server reboot "$1" >/dev/null 2>&1; }

hetzner_delete_server() { hc server delete "$1" >/dev/null; }
hetzner_delete_firewall() { hc firewall delete "$1" >/dev/null; }
hetzner_delete_ssh_key() { hc ssh-key delete "$1" >/dev/null; }

# hetzner_resource_belongs_to_deployment <kind> <name>
# Destruction safeguard: nothing is deleted unless it carries our labels and the
# exact deployment id of the state file we are acting on.
hetzner_resource_belongs_to_deployment() {
	hc "$1" describe "$2" -o json 2>/dev/null | jq -e --arg id "$GHO_DEPLOYMENT_ID" \
		'.labels["managed-by"] == "ghost-hetzner-oneclick" and .labels["deployment-id"] == $id' >/dev/null
}

# ---------------------------------------------------------------- containment

# hetzner_contain <server> <firewall> <rules_file>
# Critical-security-failure response: stop the machine, then make sure the
# provider policy is the deny-by-default one we intended.
hetzner_contain() {
	local server="$1" fw="$2" rules="$3"
	log_error "CONTAINMENT: powering off ${server}"
	hetzner_poweroff "$server" || log_error "poweroff failed — do this manually in the Hetzner console"
	log_error "CONTAINMENT: reapplying restrictive firewall rules to ${fw}"
	hc firewall replace-rules "$fw" --rules-file "$rules" >/dev/null 2>&1 ||
		log_error "could not reapply firewall rules — check the Hetzner console immediately"
}
