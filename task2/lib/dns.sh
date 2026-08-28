#!/usr/bin/env bash
# lib/dns.sh — public DNS verification and optional Cloudflare automation.

GHO_DNS_RESOLVERS="1.1.1.1 8.8.8.8 9.9.9.9"

# dns_query <domain> <type A|AAAA> [resolver]
# dig is preferred; host/nslookup and DNS-over-HTTPS are equivalent fallbacks so
# a control machine without bind-utils still works.
dns_query() {
	local name="$1" rrtype="$2" resolver="${3:-}"
	if have dig; then
		if [ -n "$resolver" ]; then
			dig +short +time=3 +tries=2 "@${resolver}" "$rrtype" "$name" 2>/dev/null |
				grep -Ev '^;|^$' || true
			return 0
		fi
		dig +short +time=3 +tries=2 "$rrtype" "$name" 2>/dev/null | grep -Ev '^;|^$' || true
		return 0
	fi
	if have host; then
		host -t "$rrtype" "$name" ${resolver:+"$resolver"} 2>/dev/null |
			awk '/has address|has IPv6 address/{print $NF}' || true
		return 0
	fi
	# DNS-over-HTTPS fallback. Uses the resolver's JSON API.
	local doh="https://1.1.1.1/dns-query"
	[ "$resolver" = "8.8.8.8" ] && doh="https://8.8.8.8/resolve"
	[ "$resolver" = "9.9.9.9" ] && doh="https://9.9.9.9:5053/dns-query"
	curl -fsS --max-time 8 -H 'accept: application/dns-json' \
		"${doh}?name=${name}&type=${rrtype}" 2>/dev/null |
		jq -r --arg t "$rrtype" '.Answer[]? | select(.type == (if $t=="A" then 1 else 28 end)) | .data' || true
}

# dns_matches <domain> <type> <expected> <resolver>
dns_matches() {
	local got
	got="$(dns_query "$1" "$2" "$4")"
	printf '%s\n' "$got" | grep -Fxq "$3"
}

# dns_check_all_resolvers <domain> <type> <expected>
# Every configured public resolver must agree, otherwise propagation is not done
# and Let's Encrypt would very likely fail validation.
dns_check_all_resolvers() {
	local r
	for r in $GHO_DNS_RESOLVERS; do
		dns_matches "$1" "$2" "$3" "$r" || return 1
	done
	return 0
}

# dns_wait <domain> <ipv4> <ipv6|""> <timeout_seconds>
dns_wait() {
	local domain="$1" v4="$2" v6="$3" timeout="$4" waited=0
	while [ "$waited" -lt "$timeout" ]; do
		if dns_check_all_resolvers "$domain" A "$v4"; then
			if [ -z "$v6" ] || dns_check_all_resolvers "$domain" AAAA "$v6"; then
				return 0
			fi
		fi
		sleep 10
		waited=$((waited + 10))
		[ $((waited % 60)) -eq 0 ] &&
			log_info "still waiting for DNS to propagate (${waited}s/${timeout}s)"
	done
	return 1
}

dns_current_summary() {
	local domain="$1"
	printf 'A:    %s\n' "$(dns_query "$domain" A | tr '\n' ' ')"
	printf 'AAAA: %s\n' "$(dns_query "$domain" AAAA | tr '\n' ' ')"
}

# --------------------------------------------------------------- Cloudflare --

GHO_CF_TOKEN=""

# _cf_curl <method> <path> [json_body]
# The token goes into a 0600 curl config file, so it never appears in `ps`
# output or in a shell history.
_cf_curl() {
	local method="$1" path="$2" body="${3:-}" cfg out rc
	cfg="$(secure_temp cfcurl)"
	{
		printf 'header = "Authorization: Bearer %s"\n' "$GHO_CF_TOKEN"
		printf 'header = "Content-Type: application/json"\n'
		printf 'silent\nshow-error\nfail-with-body\n'
		printf 'request = "%s"\n' "$method"
		printf 'max-time = 30\n'
		printf 'url = "https://api.cloudflare.com/client/v4%s"\n' "$path"
		[ -n "$body" ] && printf 'data = "%s"\n' "$(printf '%s' "$body" | sed 's/"/\\"/g')"
	} >"$cfg"
	rc=0
	out="$(curl -K "$cfg" 2>&1)" || rc=$?
	rm -f "$cfg"
	printf '%s' "$out"
	[ "$rc" -eq 0 ] || return "$rc"
	printf '%s' "$out" | jq -e '.success == true' >/dev/null
}

cf_validate_token() {
	_cf_curl GET /user/tokens/verify >/dev/null 2>&1
}

# cf_zone_id <domain> — walks up the labels until a zone matches.
cf_zone_id() {
	local name="$1" resp id
	while [ -n "$name" ] && printf '%s' "$name" | grep -q '\.'; do
		resp="$(_cf_curl GET "/zones?name=${name}&status=active" 2>/dev/null || true)"
		id="$(printf '%s' "$resp" | jq -r '.result[0].id // empty' 2>/dev/null || true)"
		if [ -n "$id" ]; then
			printf '%s' "$id"
			return 0
		fi
		name="${name#*.}"
	done
	return 1
}

# cf_record_lookup <zone_id> <type> <name> -> "<id>\t<content>\t<proxied>"
cf_record_lookup() {
	_cf_curl GET "/zones/${1}/dns_records?type=${2}&name=${3}" 2>/dev/null |
		jq -r '.result[0] | select(.) | "\(.id)\t\(.content)\t\(.proxied)"'
}

# cf_record_upsert <zone_id> <type> <name> <content> <proxied true|false>
cf_record_upsert() {
	local zone="$1" rrtype="$2" name="$3" content="$4" proxied="$5"
	local body existing rec_id
	body="$(jq -nc --arg t "$rrtype" --arg n "$name" --arg c "$content" \
		--argjson p "$proxied" '{type:$t,name:$n,content:$c,ttl:120,proxied:$p}')"
	existing="$(cf_record_lookup "$zone" "$rrtype" "$name")"
	if [ -n "$existing" ]; then
		rec_id="$(printf '%s' "$existing" | cut -f1)"
		_cf_curl PUT "/zones/${zone}/dns_records/${rec_id}" "$body" >/dev/null
	else
		_cf_curl POST "/zones/${zone}/dns_records" "$body" >/dev/null
	fi
}
