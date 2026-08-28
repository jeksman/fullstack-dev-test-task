#!/usr/bin/env bash
# ghost-hetzner-oneclick — one command, one production Ghost blog on Hetzner
# Cloud, reachable administratively only through a private Tailscale tunnel.
#
#   bash ./deploy.sh              interactive deployment (default)
#   bash ./deploy.sh --resume     continue where an interrupted run stopped
#   bash ./deploy.sh --dry-run    render and validate everything, create nothing
#   bash ./deploy.sh --status     show the current deployment state
#   bash ./deploy.sh --destroy    delete every resource of this deployment
#
# Bash 3.2 compatible: macOS ships 3.2 and this must run there unmodified.

set -Eeuo pipefail

GHO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GHO_ROOT

# shellcheck source=lib/redact.sh
. "${GHO_ROOT}/lib/redact.sh"
# shellcheck source=lib/ui.sh
. "${GHO_ROOT}/lib/ui.sh"
# shellcheck source=lib/common.sh
. "${GHO_ROOT}/lib/common.sh"
# shellcheck source=lib/state.sh
. "${GHO_ROOT}/lib/state.sh"
# shellcheck source=lib/tools.sh
. "${GHO_ROOT}/lib/tools.sh"
# shellcheck source=lib/hetzner.sh
. "${GHO_ROOT}/lib/hetzner.sh"
# shellcheck source=lib/tailscale.sh
. "${GHO_ROOT}/lib/tailscale.sh"
# shellcheck source=lib/dns.sh
. "${GHO_ROOT}/lib/dns.sh"
# shellcheck source=lib/ssh.sh
. "${GHO_ROOT}/lib/ssh.sh"
# shellcheck source=lib/verify.sh
. "${GHO_ROOT}/lib/verify.sh"
# shellcheck source=versions.env
. "${GHO_ROOT}/versions.env"

GHO_MODE="deploy"
GHO_NON_INTERACTIVE="${GHO_NON_INTERACTIVE:-0}"
GHO_KEEP_ON_FAILURE=0
GHO_VERBOSE="${GHO_VERBOSE:-0}"
GHO_DEPLOYMENT_ID=""
GHO_HCLOUD_TOKEN=""
GHO_TS_AUTHKEY=""
GHO_FAILED_STAGE=""

GHO_STAGES="preflight credentials settings firewall server bootstrap privatessh ghost dnshttps security reboot report"
# These three establish the runtime session (tool paths, credentials, the
# resolved configuration). They are re-run on every invocation, including
# --resume, because skipping them would leave later stages without their inputs.
GHO_ALWAYS_STAGES="preflight credentials settings"

# ------------------------------------------------------------------ traps ---

cleanup() {
	local rc=$?
	# Temporary secret material never outlives the process.
	if [ -n "${GHO_TMP_DIR:-}" ] && [ -d "$GHO_TMP_DIR" ]; then
		find "$GHO_TMP_DIR" -type f -exec rm -f {} + 2>/dev/null || true
	fi
	rm -f "${TMPDIR:-/tmp}"/gho-redact.* "${TMPDIR:-/tmp}"/gho-scan.* 2>/dev/null || true
	state_unlock 2>/dev/null || true
	return $rc
}

on_error() {
	local rc=$? line="${1:-?}"
	trap - ERR
	printf '\n'
	status_fail "stage '${GHO_CURRENT_STEP:-unknown}' failed (exit ${rc}, deploy.sh line ${line})"
	[ -n "${GHO_FAILED_STAGE}" ] && stage_mark "$GHO_FAILED_STAGE" failed
	failure_report
	exit "$rc"
}

trap cleanup EXIT
trap 'on_error $LINENO' ERR

failure_report() {
	hr
	printf '      %sDeployment stopped. Nothing was opened up as a workaround.%s\n' "$C_BOLD" "$C_RESET"
	[ -n "${GHO_LOG_FILE:-}" ] && note "log (redacted): ${GHO_LOG_FILE}"
	[ -n "${GHO_STATE_FILE:-}" ] && [ -s "${GHO_STATE_FILE:-}" ] && note "state: ${GHO_STATE_FILE}"
	note "continue with:  bash ./deploy.sh --resume"
	if [ -n "$(state_get 'resources.server_name')" ] && [ "$GHO_KEEP_ON_FAILURE" = "0" ]; then
		hr
		note "Billable Hetzner resources from this run were kept."
		note "Remove them with:  bash ./deploy.sh --destroy"
	fi
}

# security_incident <message>
# Critical failure path: contain first, explain second, never continue.
security_incident() {
	trap - ERR
	printf '\n'
	status_fail "CRITICAL SECURITY FAILURE: $1"
	local server firewall rules
	server="$(state_get 'resources.server_name')"
	firewall="$(state_get 'resources.firewall_name')"
	rules="${GHO_STATE_DIR}/firewall-rules.json"
	if [ -n "$server" ] && [ -n "$firewall" ] && [ -f "$rules" ]; then
		hetzner_contain "$server" "$firewall" "$rules"
	fi
	if state_exists; then
		stage_mark "${GHO_FAILED_STAGE:-unknown}" security-failure
		state_put 'result' 'SECURITY_FAILURE'
		check_record "security-incident" FAIL "$1"
		report_write "SECURITY FAILURE" >/dev/null || true
	fi
	hr
	log_error "The deployment is marked failed and will not continue."
	log_error "Inspect the server in the Hetzner console before doing anything else."
	failure_report
	exit 2
}

# ------------------------------------------------------------------- args ---

usage() {
	cat <<'USAGE'
ghost-hetzner-oneclick

  bash ./deploy.sh                    interactive deployment (default)
  bash ./deploy.sh --resume           continue an interrupted deployment
  bash ./deploy.sh --dry-run          validate and render everything, create nothing
  bash ./deploy.sh --status           print the current deployment state
  bash ./deploy.sh --destroy          delete every resource of this deployment
  bash ./deploy.sh --non-interactive  take all answers from the environment
  bash ./deploy.sh --keep-on-failure  never offer to clean up after a failure
  bash ./deploy.sh --verbose          echo debug lines to the terminal
  bash ./deploy.sh --help             this text

Environment for --non-interactive:
  HCLOUD_TOKEN TS_AUTHKEY CF_API_TOKEN
  GHO_NAME GHO_LOCATION GHO_SERVER_TYPE GHO_DOMAIN GHO_LE_EMAIL
  GHO_DNS_MODE GHO_SSH_KEY GHO_HETZNER_BACKUPS GHO_LOCAL_BACKUPS
  GHO_REBOOT_TEST GHO_PROTECT
USAGE
}

parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		--resume) GHO_MODE="resume" ;;
		--dry-run) GHO_MODE="dry-run" ;;
		--destroy) GHO_MODE="destroy" ;;
		--status) GHO_MODE="status" ;;
		--non-interactive) GHO_NON_INTERACTIVE=1 ;;
		--keep-on-failure) GHO_KEEP_ON_FAILURE=1 ;;
		--verbose | -v) GHO_VERBOSE=1 ;;
		--help | -h)
			usage
			exit 0
			;;
		*)
			printf 'unknown option: %s\n\n' "$1" >&2
			usage >&2
			exit 64
			;;
		esac
		shift
	done
}

# ============================================================ 01 preflight ===

stage_preflight() {
	GHO_FAILED_STAGE=preflight
	step 1 "Checking local prerequisites"

	local bash_major="${BASH_VERSINFO[0]:-0}"
	note "control machine: $(uname -s) $(uname -m), bash ${BASH_VERSION}"
	if [ "$bash_major" -lt 3 ]; then
		status_fail "bash 3.2 or newer is required"
		return 1
	fi
	status_pass "bash ${BASH_VERSION} is supported"

	tools_init

	# jq first: state, JSON rendering and every provider call depend on it.
	if ! have jq; then
		note "jq is missing; it is required for state and JSON handling"
		if ask_yes_no "Download jq ${GHO_JQ_VERSION} into .tools/bin now?" y; then
			tool_install_jq || {
				status_fail "jq could not be installed"
				return 1
			}
		fi
	fi
	have jq || {
		status_fail "jq is required"
		return 1
	}
	status_pass "jq $(jq --version 2>/dev/null)"

	local missing=""
	local t
	for t in curl ssh scp ssh-keygen openssl; do
		have "$t" || missing="${missing} ${t}"
	done
	if [ -n "$missing" ]; then
		note "missing:${missing}"
		require_tool curl curl "HTTP client" || true
		require_tool ssh openssh-client "SSH client" || true
		require_tool openssl openssl "TLS inspection" || true
		missing=""
		for t in curl ssh scp ssh-keygen openssl; do
			have "$t" || missing="${missing} ${t}"
		done
		if [ -n "$missing" ]; then
			status_fail "still missing:${missing}"
			return 1
		fi
	fi
	status_pass "curl, ssh, scp, ssh-keygen, openssl present"

	if have nc; then
		status_pass "nc present (TCP reachability probes)"
	else
		status_warn "nc missing — falling back to bash /dev/tcp for port probes"
	fi

	if have dig; then
		status_pass "dig present (DNS verification)"
	elif have host; then
		status_warn "dig missing — using host(1) for DNS verification"
	else
		status_warn "dig missing — using DNS-over-HTTPS for DNS verification"
	fi

	if ! have hcloud; then
		note "the Hetzner CLI is missing"
		if ask_yes_no "Download hcloud ${GHO_HCLOUD_VERSION} into .tools/bin now?" y; then
			tool_install_hcloud || {
				status_fail "hcloud could not be installed"
				return 1
			}
		fi
	fi
	have hcloud || {
		status_fail "hcloud is required"
		return 1
	}
	status_pass "hcloud $(hcloud version 2>/dev/null | head -1)"

	GHO_TAILSCALE_BIN="$(tool_find_tailscale || true)"
	if [ -z "$GHO_TAILSCALE_BIN" ]; then
		note "the Tailscale CLI was not found in any known location"
		if ask_yes_no "Install Tailscale now?" y; then
			tool_install_tailscale || true
			GHO_TAILSCALE_BIN="$(tool_find_tailscale || true)"
		fi
	fi
	if [ -z "$GHO_TAILSCALE_BIN" ]; then
		status_fail "Tailscale is required — this deployment has no other way in"
		note "macOS: install the Tailscale app from https://tailscale.com/download/mac"
		note "Linux: curl -fsSL https://tailscale.com/install.sh | sh"
		return 1
	fi
	status_pass "Tailscale CLI: ${GHO_TAILSCALE_BIN} ($(ts_version))"

	if ! tunnel_local_ready; then
		status_fail "this machine is not connected to a tailnet"
		note "run: ${GHO_TAILSCALE_BIN} up"
		note "Administrative access to the new server exists only inside your tailnet."
		return 1
	fi
	status_pass "local tailnet connection is up ($(ts_local_tailnet))"
}

# ========================================================== 02 credentials ===

stage_credentials() {
	GHO_FAILED_STAGE=credentials
	step 2 "Validating credentials"

	if [ -n "${HCLOUD_TOKEN:-}" ]; then
		GHO_HCLOUD_TOKEN="$HCLOUD_TOKEN"
		note "using HCLOUD_TOKEN from the environment"
	else
		GHO_HCLOUD_TOKEN="$(ask_secret 'Hetzner Cloud API token (read/write)')"
	fi
	redact_register "$GHO_HCLOUD_TOKEN"
	if ! printf '%s' "$GHO_HCLOUD_TOKEN" | grep -Eq '^[A-Za-z0-9]{40,80}$'; then
		status_fail "that does not look like a Hetzner API token"
		return 1
	fi
	if ! hetzner_validate_token; then
		status_fail "the Hetzner API rejected the token"
		note "the token needs Read & Write permission on the target project"
		return 1
	fi
	status_pass "Hetzner API token accepted"

	if [ -n "${TS_AUTHKEY:-}" ]; then
		GHO_TS_AUTHKEY="$TS_AUTHKEY"
		note "using TS_AUTHKEY from the environment"
	else
		note "create a one-time, pre-approved, ephemeral auth key at:"
		note "  https://login.tailscale.com/admin/settings/keys"
		GHO_TS_AUTHKEY="$(ask_secret 'Tailscale one-time auth key')"
	fi
	redact_register "$GHO_TS_AUTHKEY"
	if ! printf '%s' "$GHO_TS_AUTHKEY" | grep -Eq '^tskey-auth-[A-Za-z0-9]+-[A-Za-z0-9]+$'; then
		status_fail "that does not look like a Tailscale auth key (expected tskey-auth-...)"
		return 1
	fi
	status_pass "Tailscale auth key format accepted"
	status_warn "the key is written into cloud-init user-data; it must be one-time and ephemeral"
}

# ============================================================= 03 settings ===

stage_settings() {
	GHO_FAILED_STAGE=settings
	step 3 "Collecting deployment settings"

	local name location server_type domain le_email dns_mode ssh_key resumed=0
	stage_is_done settings && resumed=1
	name="$(state_get 'deployment_name')"
	if [ -z "$name" ]; then
		name="$(ask 'Deployment name' "${GHO_NAME:-ghost-blog}" validate_deployment_name)"
	fi

	if [ -z "$GHO_DEPLOYMENT_ID" ]; then
		GHO_DEPLOYMENT_ID="$(state_get 'deployment_id')"
	fi
	if [ -z "$GHO_DEPLOYMENT_ID" ]; then
		GHO_DEPLOYMENT_ID="${name}-$(random_id 4)"
	fi
	state_init "$GHO_DEPLOYMENT_ID" "$name"
	state_put 'deployment_name' "$name"
	state_put 'deployment_id' "$GHO_DEPLOYMENT_ID"

	# --- location ---------------------------------------------------------
	location="$(state_get 'config.location')"
	if [ -z "$location" ]; then
		note "querying available Hetzner locations"
		local locations
		locations="$(hetzner_locations | tr '\n' ' ')"
		[ -n "$locations" ] || {
			status_fail "could not list Hetzner locations"
			return 1
		}
		# shellcheck disable=SC2086  # deliberate word splitting into menu entries
		location="$(ask_choice 'Hetzner location' "${GHO_LOCATION:-$GHO_DEFAULT_LOCATION}" $locations)"
	fi
	validate_hetzner_slug "$location" || {
		status_fail "invalid location"
		return 1
	}
	state_put 'config.location' "$location"
	status_pass "location ${location} — $(hetzner_location_describe "$location")"

	# --- server type ------------------------------------------------------
	server_type="$(state_get 'config.server_type')"
	if [ -z "$server_type" ]; then
		note "querying server types with at least ${GHO_MIN_MEMORY_GB} GB RAM (x86)"
		local types
		types="$(hetzner_suitable_server_types "$GHO_MIN_MEMORY_GB" x86 | head -8 | tr '\n' ' ')"
		[ -n "$types" ] || {
			status_fail "could not list suitable server types"
			return 1
		}
		# shellcheck disable=SC2086  # deliberate word splitting into menu entries
		server_type="$(ask_choice 'Hetzner server type' "${GHO_SERVER_TYPE:-$GHO_DEFAULT_SERVER_TYPE}" $types)"
	fi
	validate_hetzner_slug "$server_type" || {
		status_fail "invalid server type"
		return 1
	}
	state_put 'config.server_type' "$server_type"
	state_put 'config.architecture' "$(hetzner_server_type_arch "$server_type")"
	status_pass "server type ${server_type} — $(hetzner_server_type_info "$server_type")"

	# --- image ------------------------------------------------------------
	if ! hetzner_image_exists "$GHO_IMAGE"; then
		status_fail "image ${GHO_IMAGE} is not available in this project"
		return 1
	fi
	state_put 'config.image' "$GHO_IMAGE"
	status_pass "image ${GHO_IMAGE}"

	# --- domain and email -------------------------------------------------
	domain="$(state_get 'config.domain')"
	[ -n "$domain" ] || domain="$(ask 'Domain for the blog (e.g. blog.example.com)' "${GHO_DOMAIN:-}" validate_domain)"
	state_put 'config.domain' "$domain"

	le_email="$(state_get 'config.le_email')"
	[ -n "$le_email" ] || le_email="$(ask "Let's Encrypt notification email" "${GHO_LE_EMAIL:-}" validate_email)"
	state_put 'config.le_email' "$le_email"
	status_pass "site https://${domain}/ , certificate notices to ${le_email}"

	# --- DNS mode ---------------------------------------------------------
	dns_mode="$(state_get 'config.dns_mode')"
	if [ -z "$dns_mode" ]; then
		note "manual     — you add the A/AAAA records; this run waits and continues by itself"
		note "cloudflare — this run creates the records through the Cloudflare API"
		dns_mode="$(ask_choice 'DNS configuration mode' "${GHO_DNS_MODE:-manual}" manual cloudflare)"
	fi
	state_put 'config.dns_mode' "$dns_mode"

	# --- SSH key ----------------------------------------------------------
	ssh_key="$(state_get 'config.ssh_key_path')"
	if [ -z "$ssh_key" ]; then
		if [ -n "${GHO_SSH_KEY:-}" ]; then
			ssh_key="$GHO_SSH_KEY"
		elif ask_yes_no 'Create a dedicated SSH key for this deployment?' y; then
			ssh_key="${GHO_STATE_DIR}/ssh/id_ed25519"
		else
			ssh_key="$(ask 'Path to an existing SSH private key' "${HOME}/.ssh/id_ed25519")"
		fi
	fi
	case "$ssh_key" in "~"*) ssh_key="${HOME}${ssh_key#\~}" ;; esac
	if [ ! -f "$ssh_key" ]; then
		note "generating a dedicated ed25519 deployment key at ${ssh_key}"
		ssh_generate_key "$ssh_key" "ghost-hetzner-oneclick ${GHO_DEPLOYMENT_ID}" || {
			status_fail "could not generate an SSH key"
			return 1
		}
	fi
	if [ ! -f "${ssh_key}.pub" ]; then
		ssh-keygen -y -f "$ssh_key" >"${ssh_key}.pub" 2>/dev/null || {
			status_fail "no public key at ${ssh_key}.pub and it could not be derived"
			return 1
		}
	fi
	validate_ssh_pubkey "$(cat "${ssh_key}.pub")" || {
		status_fail "${ssh_key}.pub is not a valid OpenSSH public key"
		return 1
	}
	GHO_SSH_KEY="$ssh_key"
	state_put 'config.ssh_key_path' "$ssh_key"
	status_pass "SSH key ${ssh_key} ($(ssh_pubkey_fingerprint "${ssh_key}.pub"))"

	# --- optional features -------------------------------------------------
	if [ -z "$(state_get 'config.hetzner_backups')" ]; then
		note "Hetzner server backups are a paid feature (about 20% of the server price)"
		if ask_yes_no 'Enable Hetzner server backups?' "${GHO_HETZNER_BACKUPS:-n}"; then
			state_put 'config.hetzner_backups' yes
		else state_put 'config.hetzner_backups' no; fi
	fi
	if [ -z "$(state_get 'config.local_backups')" ]; then
		if ask_yes_no 'Enable a nightly local Ghost backup timer on the server?' "${GHO_LOCAL_BACKUPS:-y}"; then
			state_put 'config.local_backups' yes
		else state_put 'config.local_backups' no; fi
	fi
	if [ -z "$(state_get 'config.reboot_test')" ]; then
		if ask_yes_no 'Reboot the server at the end and verify full recovery?' "${GHO_REBOOT_TEST:-y}"; then
			state_put 'config.reboot_test' yes
		else state_put 'config.reboot_test' no; fi
	fi
	if [ -z "$(state_get 'config.protect')" ]; then
		if ask_yes_no 'Enable Hetzner deletion protection after a successful deployment?' "${GHO_PROTECT:-y}"; then
			state_put 'config.protect' yes
		else state_put 'config.protect' no; fi
	fi

	state_put 'config.admin_user' "$GHO_SSH_USER"
	state_put 'config.tunnel' "$(tunnel_name)"
	state_put 'resources.server_name' "gho-${name}"
	state_put 'resources.firewall_name' "gho-${name}-fw"
	state_put 'resources.ssh_key_name' "gho-${name}-key"
	state_put 'resources.tailscale_hostname' "gho-${name}"

	print_deployment_summary

	if [ "$GHO_MODE" != "dry-run" ] && [ "$resumed" = "0" ]; then
		ask_yes_no 'Create these billable Hetzner resources now?' y || {
			note "nothing was created"
			exit 0
		}
	fi

	stage_mark settings "done"
}

print_deployment_summary() {
	hr
	printf '      %sDeployment summary%s\n' "$C_BOLD" "$C_RESET"
	kv "Deployment ID" "$GHO_DEPLOYMENT_ID"
	kv "Server name" "$(state_get 'resources.server_name')"
	kv "Location" "$(state_get 'config.location') ($(hetzner_location_describe "$(state_get 'config.location')"))"
	kv "Server type" "$(state_get 'config.server_type') — $(hetzner_server_type_info "$(state_get 'config.server_type')")"
	kv "Price" "$(hetzner_server_type_price "$(state_get 'config.server_type')" "$(state_get 'config.location')")"
	kv "Image" "$(state_get 'config.image')"
	kv "Domain" "$(state_get 'config.domain')"
	kv "DNS mode" "$(state_get 'config.dns_mode')"
	kv "Hetzner backups" "$(state_get 'config.hetzner_backups')"
	kv "Local backup timer" "$(state_get 'config.local_backups')"
	kv "Reboot validation" "$(state_get 'config.reboot_test')"
	kv "Deletion protection" "$(state_get 'config.protect')"
	kv "Public inbound ports" "TCP 80, TCP 443, ICMP — no SSH, ever"
	kv "Tunnel provider" "$(tunnel_name)"
	kv "Administrative user" "$GHO_SSH_USER"
	kv "Tailscale hostname" "$(state_get 'resources.tailscale_hostname')"
	hr
}

# ============================================================= 04 firewall ===

stage_firewall() {
	GHO_FAILED_STAGE=firewall
	step 4 "Creating the Hetzner firewall"

	local rules fw_name fw_id
	rules="${GHO_STATE_DIR}/firewall-rules.json"
	fw_name="$(state_get 'resources.firewall_name')"

	hetzner_render_firewall_rules "${GHO_ROOT}/templates/hetzner-firewall.json" "$rules" 1 || {
		status_fail "firewall policy failed its own safety check"
		return 1
	}
	status_pass "policy rendered: $(jq -r '[.[] | "\(.protocol)/\(.port // "any")"] | join(", ")' "$rules")"

	if jq -e 'any(.[]; (.protocol=="tcp") and ((.port|tostring)=="22"))' "$rules" >/dev/null; then
		security_incident "the rendered firewall policy contains an inbound SSH rule"
	fi
	status_pass "no inbound TCP 22 rule in the policy"

	if [ "$GHO_MODE" = "dry-run" ]; then
		status_skip "dry run — the firewall was not created"
		return 0
	fi

	fw_id="$(hetzner_create_firewall "$fw_name" "$rules")" || {
		status_fail "could not create the firewall"
		return 1
	}
	state_put 'resources.firewall_id' "$fw_id"
	status_pass "firewall ${fw_name} (id ${fw_id}) exists"

	hetzner_firewall_matches_policy "$fw_name" "$rules" || {
		status_fail "the firewall at Hetzner does not match the intended policy"
		note "actual: $(hetzner_firewall_rules_json "$fw_name" | jq -c '.')"
		return 1
	}
	status_pass "firewall rules at Hetzner match the intended policy exactly"

	hetzner_firewall_has_no_ssh "$fw_name" ||
		security_incident "the Hetzner firewall exposes TCP 22"
	status_pass "Hetzner firewall has no inbound SSH rule"

	stage_mark firewall "done"
}

# =============================================================== 05 server ===

render_cloud_init() {
	local out="$1" pubkey tpl
	pubkey="$(cat "${GHO_SSH_KEY}.pub")"
	tpl="$(cat "${GHO_ROOT}/templates/cloud-init.yaml")"
	# Bash parameter substitution keeps the auth key out of argv and out of any
	# intermediate file. The only place it lands is $out, created 0600 below.
	tpl="${tpl//__ADMIN_USER__/$GHO_SSH_USER}"
	tpl="${tpl//__SSH_PUBKEY__/$pubkey}"
	tpl="${tpl//__TS_HOSTNAME__/$(state_get 'resources.tailscale_hostname')}"
	tpl="${tpl//__DEPLOYMENT_ID__/$GHO_DEPLOYMENT_ID}"
	tpl="${tpl//__TS_AUTHKEY__/$GHO_TS_AUTHKEY}"
	: >"$out"
	chmod 600 "$out"
	printf '%s\n' "$tpl" >"$out"
}

stage_server() {
	GHO_FAILED_STAGE=server
	step 5 "Creating the VPS"

	local name type image location fw_id udata key_name key_id ipv4 ipv6
	name="$(state_get 'resources.server_name')"
	type="$(state_get 'config.server_type')"
	image="$(state_get 'config.image')"
	location="$(state_get 'config.location')"
	fw_id="$(state_get 'resources.firewall_id')"
	key_name="$(state_get 'resources.ssh_key_name')"

	udata="$(secure_temp cloudinit)"
	render_cloud_init "$udata"
	if grep -q '__TS_AUTHKEY__\|__SSH_PUBKEY__\|__ADMIN_USER__\|__TS_HOSTNAME__\|__DEPLOYMENT_ID__' "$udata"; then
		rm -f "$udata"
		status_fail "cloud-init still contains unrendered placeholders"
		return 1
	fi
	status_pass "cloud-init rendered ($(wc -l <"$udata" | tr -d ' ') lines, mode 0600)"

	if [ "$GHO_MODE" = "dry-run" ]; then
		local preview="${GHO_REPORT_DIR}/cloud-init.dry-run.yaml"
		sed "s|${GHO_TS_AUTHKEY}|__TS_AUTHKEY_REDACTED__|g" "$udata" >"$preview" 2>/dev/null ||
			redact_stream <"$udata" >"$preview"
		chmod 600 "$preview"
		shred -u "$udata" 2>/dev/null || rm -f "$udata"
		status_skip "dry run — no server created; redacted cloud-init written to ${preview}"
		return 0
	fi

	if [ -z "$fw_id" ]; then
		status_fail "no firewall id in state — refusing to create an unprotected server"
		return 1
	fi

	# A dedicated Hetzner SSH key resource suppresses the emailed root password.
	key_id="$(hetzner_create_ssh_key "$key_name" "${GHO_SSH_KEY}.pub" 2>/dev/null || true)"
	if [ -n "$key_id" ]; then
		state_put 'resources.ssh_key_id' "$key_id"
		state_put 'resources.ssh_key_created' yes
		status_pass "Hetzner SSH key resource ${key_name} (id ${key_id})"
	else
		state_put 'resources.ssh_key_created' no
		status_warn "could not create a Hetzner SSH key resource; continuing without one"
		key_name=""
	fi

	note "creating ${name} (${type}, ${image}, ${location}) with the firewall attached"
	hetzner_create_server "$name" "$type" "$image" "$location" "$fw_id" "$udata" "$key_name" || {
		shred -u "$udata" 2>/dev/null || rm -f "$udata"
		status_fail "server creation failed"
		return 1
	}
	shred -u "$udata" 2>/dev/null || rm -f "$udata"
	status_pass "server creation request accepted; local cloud-init copy destroyed"

	verify "server-running" ok 30 12 -- test_server_running "$name" || return 1

	state_put 'resources.server_id' "$(hetzner_server_json "$name" | jq -r '.id')"
	ipv4="$(hetzner_server_ipv4 "$name")"
	ipv6="$(hetzner_server_ipv6 "$name")"
	state_put 'resources.public_ipv4' "$ipv4"
	[ -n "$ipv6" ] && state_put 'resources.public_ipv6' "$ipv6"
	status_pass "public IPv4 ${ipv4}${ipv6:+, IPv6 ${ipv6}}"

	verify "server-labels" ok 30 3 -- hetzner_server_label_ok "$name" || return 1
	verify "firewall-attached" ok 60 6 -- hetzner_server_has_firewall "$name" "$fw_id" ||
		security_incident "the firewall is not applied to the server"
	verify "server-image-and-arch" ok 30 3 -- test_server_image "$name" "$image" || return 1

	if [ "$(state_get 'config.hetzner_backups')" = "yes" ]; then
		if hetzner_enable_backups "$name" && hetzner_backups_enabled "$name"; then
			status_pass "Hetzner server backups enabled (billable)"
			check_record "hetzner-backups" PASS "enabled"
		else
			status_warn "could not enable Hetzner server backups"
			check_record "hetzner-backups" WARNING "could not be enabled"
		fi
	else
		verify_skip "hetzner-backups" "not requested"
	fi

	check_public_ssh_isolation "$ipv4" "$ipv6"

	stage_mark server "done"
}

test_server_running() { [ "$(hetzner_server_status "$1")" = "running" ]; }

test_server_image() {
	hetzner_server_json "$1" | jq -e --arg img "$2" \
		'.image.name == $img and (.server_type.architecture | length > 0)' >/dev/null
}

# check_public_ssh_isolation <ipv4> <ipv6>
# Two independent lines of evidence: a live TCP probe, and the provider firewall
# configuration itself. A successful probe is a containment event.
check_public_ssh_isolation() {
	local ipv4="$1" ipv6="${2:-}"
	local fw_name
	fw_name="$(state_get 'resources.firewall_name')"

	if ! verify "public-ssh-ipv4-closed" fail 15 2 -- tcp_probe "$ipv4" 22 8 -4; then
		security_incident "TCP 22 is reachable on the public IPv4 address ${ipv4}"
	fi
	if [ -n "$ipv6" ]; then
		if tcp_probe "$ipv6" 22 8 -6; then
			security_incident "TCP 22 is reachable on the public IPv6 address ${ipv6}"
		fi
		status_pass "public-ssh-ipv6-closed"
		check_record "public-ssh-ipv6-closed" PASS ""
	else
		verify_skip "public-ssh-ipv6-closed" "no public IPv6"
	fi

	verify "provider-firewall-has-no-ssh" ok 30 3 -- hetzner_firewall_has_no_ssh "$fw_name" ||
		security_incident "the Hetzner firewall gained an inbound SSH rule"

	# nginx is not installed yet at this point, so a closed port 80 is normal.
	verify_warn "public-http-reachable-early" ok 30 2 -- test_port_expected_open "$ipv4" 80
}

test_port_expected_open() { tcp_probe "$1" "$2" 6 -4; }

# ============================================================ 06 bootstrap ===

stage_bootstrap() {
	GHO_FAILED_STAGE=bootstrap
	step 6 "Waiting for cloud-init and Tailscale"

	if [ "$GHO_MODE" = "dry-run" ]; then
		status_skip "dry run — nothing to wait for"
		return 0
	fi

	local host ts_ip dnsname
	host="$(state_get 'resources.tailscale_hostname')"

	note "waiting for ${host} to join the tailnet (up to 10 minutes)"
	note "cloud-init is installing Tailscale and closing SSH on the public interfaces"
	ts_ip="$(tunnel_wait_for_node "$host" 600 || true)"
	if [ -z "$ts_ip" ]; then
		status_fail "the node never appeared on the tailnet"
		note "likely causes: the auth key was already used, was not pre-approved,"
		note "or device approval is required in your tailnet settings."
		note "Public SSH stays closed. Fix the key and run: bash ./deploy.sh --resume"
		return 1
	fi
	status_pass "tailnet node ${host} discovered at ${ts_ip}"

	validate_tailscale_ipv4 "$ts_ip" || {
		status_fail "${ts_ip} is not inside the Tailscale CGNAT range"
		return 1
	}
	status_pass "address is inside 100.64.0.0/10"

	state_put 'resources.tailscale_ipv4' "$ts_ip"
	dnsname="$(tunnel_node_hostname "$host")"
	[ -n "$dnsname" ] && state_put 'resources.tailscale_dnsname' "$dnsname"

	verify "tailscale-node-online" ok 60 6 -- ts_node_online "$host" ||
		status_warn "the control plane does not report the node as online yet"
	verify "tailscale-ping" ok 60 8 -- tunnel_ping "$ts_ip" || {
		tunnel_access_help "$dnsname" "$ts_ip"
		return 1
	}

	stage_mark bootstrap "done"
}

# =========================================================== 07 privatessh ===

stage_privatessh() {
	GHO_FAILED_STAGE=privatessh
	step 7 "Verifying private SSH"

	if [ "$GHO_MODE" = "dry-run" ]; then
		status_skip "dry run — no server to connect to"
		return 0
	fi

	GHO_SSH_TARGET="$(state_get 'resources.tailscale_ipv4')"
	GHO_SSH_KEY="$(state_get 'config.ssh_key_path')"
	ssh_assert_private_target "$GHO_SSH_TARGET" || return 1

	verify "ssh-host-key-pinned" ok 120 3 -- ssh_pin_hostkey "$GHO_SSH_TARGET" || {
		tunnel_access_help "$(state_get 'resources.tailscale_dnsname')" "$GHO_SSH_TARGET"
		return 1
	}

	verify "private-ssh-login" ok 60 10 -- rssh true || {
		tunnel_access_help "$(state_get 'resources.tailscale_dnsname')" "$GHO_SSH_TARGET"
		return 1
	}

	verify "remote-user-is-ghostops" ok 30 3 -- test_remote_user || return 1
	verify "remote-sudo-works" ok 30 3 -- rssh 'sudo -n id -u' || return 1
	verify "ssh-destination-is-tailscale" ok 30 3 -- test_ssh_destination_private || return 1
	verify "root-ssh-refused" fail 30 1 -- ssh_try_root
	verify "password-ssh-refused" fail 30 1 -- ssh_try_password
	verify "bootstrap-completed" ok 300 20 -- rssh 'test -f /var/lib/gho-bootstrap.done' || return 1
	verify "scp-over-tunnel" ok 60 3 -- test_scp_roundtrip || return 1

	stage_mark privatessh "done"
}

test_remote_user() { [ "$(rssh 'id -un' 2>/dev/null)" = "$GHO_SSH_USER" ]; }

test_ssh_destination_private() {
	local dest
	# shellcheck disable=SC2016  # SSH_CONNECTION must expand on the server
	dest="$(rssh 'printf "%s" "${SSH_CONNECTION}"' 2>/dev/null | awk '{print $3}')"
	[ -n "$dest" ] || return 1
	validate_tailscale_ipv4 "$dest"
}

ssh_try_root() {
	ssh -o "UserKnownHostsFile=${GHO_KNOWN_HOSTS}" -o StrictHostKeyChecking=yes \
		-o IdentitiesOnly=yes -o "IdentityFile=${GHO_SSH_KEY}" -o BatchMode=yes \
		-o ConnectTimeout=10 -o LogLevel=ERROR \
		"root@${GHO_SSH_TARGET}" true 2>/dev/null
}

ssh_try_password() {
	ssh -o "UserKnownHostsFile=${GHO_KNOWN_HOSTS}" -o StrictHostKeyChecking=yes \
		-o PubkeyAuthentication=no -o PreferredAuthentications=password \
		-o NumberOfPasswordPrompts=0 -o BatchMode=yes -o ConnectTimeout=10 \
		-o LogLevel=ERROR "${GHO_SSH_USER}@${GHO_SSH_TARGET}" true 2>/dev/null
}

test_scp_roundtrip() {
	local probe
	probe="$(secure_temp scpprobe)"
	printf 'ghost-hetzner-oneclick scp probe %s\n' "$GHO_DEPLOYMENT_ID" >"$probe"
	rscp "$probe" "/tmp/gho-scp-probe" || {
		rm -f "$probe"
		return 1
	}
	rm -f "$probe"
	rssh "grep -q '${GHO_DEPLOYMENT_ID}' /tmp/gho-scp-probe && rm -f /tmp/gho-scp-probe"
}

# ================================================================ 08 ghost ===

stream_remote() {
	local line
	while IFS= read -r line; do
		printf '      %s%s%s\n' "$C_DIM" "$line" "$C_RESET"
		_log_write REMOTE "$line"
	done
}

upload_remote_scripts() {
	rssh 'mkdir -p /tmp/gho && chmod 700 /tmp/gho' || return 1
	local f
	for f in install-ghost.sh configure-security.sh configure-https.sh configure-backups.sh verify-server.sh; do
		rscp "${GHO_ROOT}/remote/${f}" "/tmp/gho/${f}" || return 1
	done
	rssh 'chmod 700 /tmp/gho/*.sh'
}

stage_ghost() {
	GHO_FAILED_STAGE=ghost
	step 8 "Installing Ghost"

	if [ "$GHO_MODE" = "dry-run" ]; then
		status_skip "dry run — Ghost was not installed"
		return 0
	fi

	GHO_SSH_TARGET="$(state_get 'resources.tailscale_ipv4')"
	GHO_SSH_KEY="$(state_get 'config.ssh_key_path')"

	verify "remote-scripts-uploaded" ok 120 3 -- upload_remote_scripts || return 1

	local domain
	domain="$(state_get 'config.domain')"

	note "installing Node.js ${GHO_NODE_MAJOR}, MySQL, nginx, ghost-cli and Ghost"
	note "this takes several minutes; output is streamed below"
	rssh "bash /tmp/gho/install-ghost.sh '${domain}' '${GHO_SSH_USER}' '${GHO_NODE_MAJOR}' '${GHO_GHOST_CLI_SPEC}' '${GHO_MYSQL_PACKAGE}'" 2>&1 |
		stream_remote || {
		status_fail "the Ghost installer failed on the server"
		note "diagnostics: $(report_ssh_command) 'sudo journalctl -n 100 --no-pager'"
		return 1
	}
	status_pass "Ghost installed"

	note "applying host hardening"
	rssh "bash /tmp/gho/configure-security.sh '${GHO_SSH_USER}'" 2>&1 | stream_remote || {
		status_fail "host hardening failed"
		return 1
	}
	status_pass "host hardening applied and re-asserted"

	if [ "$(state_get 'config.local_backups')" = "yes" ]; then
		note "configuring the nightly local backup timer"
		if rssh "bash /tmp/gho/configure-backups.sh '${GHO_SSH_USER}' 7" 2>&1 | stream_remote; then
			status_pass "backup timer installed and test run verified"
			check_record "backup-timer" PASS "nightly, 7 retained"
		else
			status_warn "the backup timer could not be verified"
			check_record "backup-timer" WARNING "setup did not verify"
		fi
	else
		verify_skip "backup-timer" "not requested"
	fi

	stage_mark ghost "done"
}

# ============================================================= 09 dns+https ===

stage_dnshttps() {
	GHO_FAILED_STAGE=dnshttps
	step 9 "Configuring DNS and HTTPS"

	if [ "$GHO_MODE" = "dry-run" ]; then
		status_skip "dry run — no DNS changes and no certificate request"
		return 0
	fi

	local domain ipv4 ipv6 mode
	domain="$(state_get 'config.domain')"
	ipv4="$(state_get 'resources.public_ipv4')"
	ipv6="$(state_get 'resources.public_ipv6')"
	mode="$(state_get 'config.dns_mode')"

	case "$mode" in
	cloudflare) dns_mode_cloudflare "$domain" "$ipv4" "$ipv6" || return 1 ;;
	*) dns_mode_manual "$domain" "$ipv4" "$ipv6" || return 1 ;;
	esac

	verify "dns-a-record" ok 30 3 -- dns_check_all_resolvers "$domain" A "$ipv4" || return 1
	if [ -n "$ipv6" ]; then
		verify_warn "dns-aaaa-record" ok 30 2 -- dns_check_all_resolvers "$domain" AAAA "$ipv6"
	fi

	GHO_SSH_TARGET="$(state_get 'resources.tailscale_ipv4')"
	GHO_SSH_KEY="$(state_get 'config.ssh_key_path')"
	note "configuring nginx and requesting a Let's Encrypt certificate"
	rssh "bash /tmp/gho/configure-https.sh '${domain}' '$(state_get 'config.le_email')' '${GHO_SSH_USER}'" 2>&1 |
		stream_remote || {
		status_fail "nginx or certificate configuration failed"
		return 1
	}

	verify "http-redirects-to-https" ok 30 6 -- http_redirects_to_https "$domain" || return 1
	verify "https-responds" ok 30 6 -- https_ok "$domain" || return 1
	verify "tls-hostname-validates" ok 30 3 -- tls_hostname_valid "$domain" || return 1
	verify "tls-certificate-valid" ok 30 3 -- tls_cert_valid_for_days "$domain" 20 || return 1
	verify "tls-issuer-trusted" ok 30 3 -- tls_cert_issuer_trusted "$domain" || return 1
	verify "ghost-admin-reachable" ok 30 3 -- https_admin_ok "$domain" || return 1

	state_put 'resources.certificate_expires' "$(tls_cert_notafter "$domain")"
	status_pass "certificate issued by $(tls_cert_issuer "$domain"), valid until $(tls_cert_notafter "$domain")"

	if [ "$mode" = "cloudflare" ] && [ "$(state_get 'config.cf_proxy_offered')" != "yes" ]; then
		state_put 'config.cf_proxy_offered' yes
		if ask_yes_no 'Enable Cloudflare proxying (orange cloud) now that HTTPS works?' n; then
			if cf_record_upsert "$(state_get 'resources.cf_zone_id')" A "$domain" "$ipv4" true; then
				status_pass "Cloudflare proxying enabled"
			else
				status_warn "could not enable Cloudflare proxying"
			fi
		fi
	fi

	stage_mark dnshttps "done"
}

dns_mode_manual() {
	local domain="$1" ipv4="$2" ipv6="$3"
	hr
	printf '      %sAdd these DNS records now:%s\n' "$C_BOLD" "$C_RESET"
	kv "A" "${domain}  ->  ${ipv4}"
	[ -n "$ipv6" ] && kv "AAAA" "${domain}  ->  ${ipv6}"
	kv "TTL" "as low as your provider allows (60-300s)"
	hr
	note "this run keeps waiting and continues by itself as soon as the records resolve"

	while :; do
		if dns_wait "$domain" "$ipv4" "$ipv6" 900; then
			status_pass "DNS resolves to this server on all of: ${GHO_DNS_RESOLVERS}"
			return 0
		fi
		status_warn "DNS did not resolve within 15 minutes"
		note "current: $(dns_current_summary "$domain" | tr '\n' ' ')"
		ask_yes_no 'Keep waiting?' y || {
			status_fail "DNS was never configured"
			return 1
		}
	done
}

dns_mode_cloudflare() {
	local domain="$1" ipv4="$2" ipv6="$3" zone existing
	if [ -n "${CF_API_TOKEN:-}" ]; then
		GHO_CF_TOKEN="$CF_API_TOKEN"
		note "using CF_API_TOKEN from the environment"
	else
		note "the token needs Zone:DNS:Edit on the target zone only"
		GHO_CF_TOKEN="$(ask_secret 'Cloudflare API token')"
	fi
	redact_register "$GHO_CF_TOKEN"

	verify "cloudflare-token-valid" ok 30 2 -- cf_validate_token || return 1

	zone="$(cf_zone_id "$domain" || true)"
	[ -n "$zone" ] || {
		status_fail "no active Cloudflare zone found for ${domain}"
		return 1
	}
	state_put 'resources.cf_zone_id' "$zone"
	status_pass "Cloudflare zone ${zone}"

	existing="$(cf_record_lookup "$zone" A "$domain" || true)"
	if [ -n "$existing" ]; then
		hr
		note "an A record already exists for ${domain}:"
		kv "current value" "$(printf '%s' "$existing" | cut -f2)"
		kv "new value" "$ipv4"
		hr
		ask_yes_no "Overwrite the existing A record?" n || {
			status_fail "declined to overwrite the existing DNS record"
			return 1
		}
	fi

	# DNS-only until the certificate exists; a proxied record breaks http-01.
	verify "cloudflare-a-record-written" ok 30 3 -- cf_record_upsert "$zone" A "$domain" "$ipv4" false || return 1
	if [ -n "$ipv6" ]; then
		verify_warn "cloudflare-aaaa-record-written" ok 30 2 -- cf_record_upsert "$zone" AAAA "$domain" "$ipv6" false
	fi

	note "waiting for public DNS propagation"
	dns_wait "$domain" "$ipv4" "$ipv6" 600 || {
		status_fail "the records were written but public DNS has not caught up"
		return 1
	}
	status_pass "DNS resolves to this server on all of: ${GHO_DNS_RESOLVERS}"
}

# ============================================================= 10 security ===

stage_security() {
	GHO_FAILED_STAGE=security
	step 10 "Running security checks"

	if [ "$GHO_MODE" = "dry-run" ]; then
		status_skip "dry run — no live server to inspect"
		return 0
	fi

	GHO_SSH_TARGET="$(state_get 'resources.tailscale_ipv4')"
	GHO_SSH_KEY="$(state_get 'config.ssh_key_path')"

	local domain out line st nm dt failed
	domain="$(state_get 'config.domain')"

	out="$(rssh "bash /tmp/gho/verify-server.sh '${domain}' '${GHO_SSH_USER}' '${GHO_NODE_MAJOR}'" 2>/dev/null || true)"
	if ! printf '%s' "$out" | jq -e '.checks' >/dev/null 2>&1; then
		status_fail "the server-side verifier did not return usable JSON"
		note "raw output was written to the log"
		_log_write ERROR "verify-server output: ${out}"
		return 1
	fi

	printf '%s' "$out" | jq -r '.checks[] | "\(.status)\t\(.name)\t\(.detail)"' >"${GHO_TMP_DIR}/remote-checks.tsv"
	while IFS="$(printf '\t')" read -r st nm dt; do
		[ -n "$nm" ] || continue
		case "$st" in
		PASS) status_pass "${nm} — ${dt}" ;;
		WARNING)
			status_warn "${nm} — ${dt}"
			GHO_CHECK_WARNINGS=$((GHO_CHECK_WARNINGS + 1))
			;;
		*)
			status_fail "${nm} — ${dt}"
			GHO_CHECK_FAILURES=$((GHO_CHECK_FAILURES + 1))
			;;
		esac
		check_record "$nm" "$st" "$dt"
	done <"${GHO_TMP_DIR}/remote-checks.tsv"
	rm -f "${GHO_TMP_DIR}/remote-checks.tsv"

	failed="$(printf '%s' "$out" | jq -r '.failed')"
	if [ "${failed:-1}" != "0" ]; then
		# A firewall or SSH regression is a containment event, not a retry.
		if printf '%s' "$out" | jq -e '[.checks[] | select(.status=="FAIL") | .name] |
			any(. == "ufw-ssh-tunnel-only" or . == "sshd-no-root-login" or . == "sshd-no-password-auth")' >/dev/null; then
			security_incident "the server-side security posture regressed"
		fi
		status_fail "${failed} server-side checks failed"
		return 1
	fi
	status_pass "$(printf '%s' "$out" | jq -r '.checks | length') server-side checks passed"

	# Re-assert the invariant from outside, after everything has been installed.
	check_public_ssh_isolation "$(state_get 'resources.public_ipv4')" "$(state_get 'resources.public_ipv6')"

	verify "state-file-has-no-secrets" ok 30 1 -- state_has_no_secrets || {
		security_incident "the state file contains credential material"
	}

	verify "no-secret-leakage-in-artifacts" ok 60 1 -- scan_local_artifacts || {
		note "$(scan_local_artifacts 2>&1 || true)"
		security_incident "a credential was found in a local artifact"
	}

	stage_mark security "done"
}

state_has_no_secrets() {
	local s
	for s in ${GHO_SECRETS+"${GHO_SECRETS[@]}"}; do
		grep -qF "$s" "$GHO_STATE_FILE" 2>/dev/null && return 1
	done
	grep -qE 'tskey-auth-|-----BEGIN [A-Z ]*PRIVATE KEY-----' "$GHO_STATE_FILE" 2>/dev/null && return 1
	return 0
}

# Scans exactly the artifacts this project produces or ships. The .tools cache
# and .git are excluded on purpose: they contain no deployment output.
scan_local_artifacts() {
	local targets=""
	local p
	for p in "$GHO_STATE_FILE" "$GHO_LOG_DIR" "$GHO_REPORT_DIR" "$GHO_TMP_DIR" \
		"${GHO_ROOT}/deploy.sh" "${GHO_ROOT}/lib" "${GHO_ROOT}/remote" \
		"${GHO_ROOT}/templates" "${GHO_ROOT}/docs" "${GHO_ROOT}/tests" \
		"${GHO_ROOT}/README.md" "${GHO_ROOT}/SECURITY.md" "${GHO_ROOT}/versions.env"; do
		[ -e "$p" ] && targets="${targets} ${p}"
	done
	# shellcheck disable=SC2086  # deliberate: build the path list
	scan_for_secrets $targets
}

# =============================================================== 11 reboot ===

stage_reboot() {
	GHO_FAILED_STAGE=reboot
	step 11 "Rebooting and testing recovery"

	if [ "$GHO_MODE" = "dry-run" ]; then
		status_skip "dry run — no reboot"
		return 0
	fi
	if [ "$(state_get 'config.reboot_test')" != "yes" ]; then
		verify_skip "reboot-recovery" "the operator chose to skip reboot validation"
		stage_mark reboot "done"
		return 0
	fi

	GHO_SSH_TARGET="$(state_get 'resources.tailscale_ipv4')"
	GHO_SSH_KEY="$(state_get 'config.ssh_key_path')"

	local server domain boot_before
	server="$(state_get 'resources.server_name')"
	domain="$(state_get 'config.domain')"

	boot_before="$(rssh 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null || true)"
	[ -n "$boot_before" ] || {
		status_fail "could not read the current boot id"
		return 1
	}
	note "boot id before reboot: ${boot_before}"

	hetzner_reboot "$server" || {
		status_fail "the reboot request failed"
		return 1
	}
	status_pass "reboot requested through the Hetzner API"

	note "waiting for the machine to come back on the tailnet"
	verify "reboot-tailscale-ping" ok 420 1 -- wait_reboot_ping "$GHO_SSH_TARGET" || return 1
	verify "reboot-new-boot-id" ok 420 1 -- wait_new_boot_id "$boot_before" || return 1
	status_pass "the server rebooted and rejoined the tailnet at the same address"

	verify "reboot-private-ssh" ok 60 5 -- rssh true || return 1
	verify "reboot-mysql-active" ok 60 6 -- rssh 'systemctl is-active --quiet mysql' || return 1
	verify "reboot-nginx-active" ok 60 6 -- rssh 'systemctl is-active --quiet nginx' || return 1
	verify "reboot-ghost-active" ok 120 8 -- rssh 'systemctl list-units --type=service --no-legend "ghost_*" | grep -q running' || return 1
	verify "reboot-https-responds" ok 60 8 -- https_ok "$domain" || return 1
	verify "reboot-tls-valid" ok 30 3 -- tls_hostname_valid "$domain" || return 1

	if tcp_probe "$(state_get 'resources.public_ipv4')" 22 8 -4; then
		security_incident "public TCP 22 became reachable after the reboot"
	fi
	status_pass "public SSH is still closed after the reboot"
	check_record "reboot-public-ssh-closed" PASS ""
	check_record "reboot-recovery" PASS "tailnet, SSH, MySQL, Nginx, Ghost and HTTPS all recovered"

	stage_mark reboot "done"
}

wait_reboot_ping() {
	# Give the machine a moment to actually go down before declaring success.
	sleep 20
	wait_until 380 10 tunnel_ping "$1"
}

wait_new_boot_id() {
	local before="$1"
	wait_until 380 10 boot_id_changed "$before"
}

boot_id_changed() {
	local now
	now="$(rssh 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null || true)"
	[ -n "$now" ] && [ "$now" != "$1" ]
}

# =============================================================== 12 report ===

stage_report() {
	GHO_FAILED_STAGE=report
	step 12 "Creating the final report"

	if [ "$GHO_MODE" = "dry-run" ]; then
		status_skip "dry run — no report for a deployment that was not made"
		return 0
	fi

	local server
	server="$(state_get 'resources.server_name')"

	if [ "$(state_get 'config.protect')" = "yes" ]; then
		if hetzner_enable_protection "$server"; then
			status_pass "deletion protection enabled on ${server}"
			state_put 'resources.delete_protection' enabled
		else
			status_warn "could not enable deletion protection"
		fi
	else
		verify_skip "deletion-protection" "not requested"
	fi

	rssh 'rm -rf /tmp/gho' 2>/dev/null || true

	state_put 'result' 'SUCCESS'
	stage_mark report "done"

	local path
	path="$(report_write SUCCESS)"
	print_final_report "$path"
}

print_final_report() {
	printf '\n'
	hr
	printf '      %s%sDEPLOYMENT SUCCESSFUL%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
	hr
	report_text SUCCESS | sed 's/^/      /'
	hr
	printf '      %sOpen the admin URL and create the owner account now.%s\n' "$C_BOLD" "$C_RESET"
	printf '      Ghost does not create it for you, and the first visitor to that\n'
	printf '      page becomes the owner.\n'
	hr
	note "JSON report: ${GHO_REPORT_DIR}/final-report.json"
	note "Text report: ${1}"
	if [ "$GHO_CHECK_WARNINGS" -gt 0 ]; then
		status_warn "${GHO_CHECK_WARNINGS} check(s) finished with a warning — see the report"
	fi
}

# ================================================================= status ====

cmd_status() {
	banner
	if ! state_exists; then
		note "no deployment state found in ${GHO_STATE_DIR}"
		note "start one with:  bash ./deploy.sh"
		return 0
	fi
	GHO_DEPLOYMENT_ID="$(state_get 'deployment_id')"
	hr
	printf '      %sDeployment state%s\n' "$C_BOLD" "$C_RESET"
	kv "Deployment ID" "$(state_get 'deployment_id')"
	kv "Result" "$(state_get 'result' 'in progress')"
	kv "Created" "$(state_get 'created_at')"
	kv "Updated" "$(state_get 'updated_at')"
	kv "Last stage" "$(state_get 'stage')"
	hr
	local s
	for s in $GHO_STAGES; do
		if _stage_always_runs "$s"; then
			status_skip "${s} (session setup, runs every invocation)"
		elif stage_is_done "$s"; then
			status_pass "$s"
		else
			status_skip "${s} (pending)"
		fi
	done
	hr
	kv "Server" "$(state_get 'resources.server_name') (id $(state_get 'resources.server_id'))"
	kv "Firewall" "$(state_get 'resources.firewall_name') (id $(state_get 'resources.firewall_id'))"
	kv "Public IPv4" "$(state_get 'resources.public_ipv4')"
	kv "Public IPv6" "$(state_get 'resources.public_ipv6' 'disabled')"
	kv "Tailscale IPv4" "$(state_get 'resources.tailscale_ipv4')"
	kv "Tailscale name" "$(state_get 'resources.tailscale_dnsname')"
	kv "Domain" "$(state_get 'config.domain')"
	hr
	local failed
	failed="$(jq -r '[.checks[] | select(.status=="FAIL")] | length' "$GHO_STATE_FILE")"
	kv "Recorded checks" "$(jq -r '.checks | length' "$GHO_STATE_FILE") total, ${failed} failed"
	[ -n "$(report_ssh_command)" ] && kv "Private SSH" "$(report_ssh_command)"
	[ -f "${GHO_REPORT_DIR}/final-report.txt" ] && note "report: ${GHO_REPORT_DIR}/final-report.txt"
	return 0
}

# ================================================================ destroy ====

cmd_destroy() {
	banner
	state_exists || die "no deployment state found in ${GHO_STATE_DIR}"

	GHO_DEPLOYMENT_ID="$(state_get 'deployment_id')"
	local name server firewall sshkey sshkey_created
	name="$(state_get 'deployment_name')"
	server="$(state_get 'resources.server_name')"
	firewall="$(state_get 'resources.firewall_name')"
	sshkey="$(state_get 'resources.ssh_key_name')"
	sshkey_created="$(state_get 'resources.ssh_key_created')"

	if [ -n "${HCLOUD_TOKEN:-}" ]; then
		GHO_HCLOUD_TOKEN="$HCLOUD_TOKEN"
	else
		GHO_HCLOUD_TOKEN="$(ask_secret 'Hetzner Cloud API token')"
	fi
	redact_register "$GHO_HCLOUD_TOKEN"
	hetzner_validate_token || die "the Hetzner API rejected the token"

	hr
	printf '      %sThese resources will be permanently deleted:%s\n' "$C_BOLD" "$C_RESET"
	local to_delete=0
	if [ -n "$server" ] && hetzner_server_exists "$server"; then
		if hetzner_resource_belongs_to_deployment server "$server"; then
			kv "server" "${server} (id $(state_get 'resources.server_id'))"
			to_delete=$((to_delete + 1))
		else
			status_warn "server ${server} does not carry deployment id ${GHO_DEPLOYMENT_ID} — it will NOT be touched"
			server=""
		fi
	else
		server=""
	fi
	if [ -n "$firewall" ] && hetzner_firewall_exists "$firewall"; then
		if hetzner_resource_belongs_to_deployment firewall "$firewall"; then
			kv "firewall" "${firewall} (id $(state_get 'resources.firewall_id'))"
			to_delete=$((to_delete + 1))
		else
			status_warn "firewall ${firewall} does not carry deployment id ${GHO_DEPLOYMENT_ID} — it will NOT be touched"
			firewall=""
		fi
	else
		firewall=""
	fi
	if [ "$sshkey_created" = "yes" ] && [ -n "$sshkey" ] && hetzner_ssh_key_exists "$sshkey"; then
		if hetzner_resource_belongs_to_deployment ssh-key "$sshkey"; then
			kv "ssh key" "$sshkey"
			to_delete=$((to_delete + 1))
		else
			sshkey=""
		fi
	else
		[ "$sshkey_created" = "yes" ] || note "the Hetzner SSH key was not created by this project; leaving it alone"
		sshkey=""
	fi
	hr

	if [ "$to_delete" -eq 0 ]; then
		note "nothing belonging to deployment ${GHO_DEPLOYMENT_ID} is left at Hetzner"
	else
		note "the local domain, DNS records and Tailscale node are NOT removed by this command"
		confirm_exact "$name" "This cannot be undone." ||
			die "the deployment name did not match; nothing was deleted"
	fi

	if [ -n "$server" ]; then
		hetzner_disable_protection "$server" || true
		note "deleting server ${server}"
		if hetzner_delete_server "$server"; then status_pass "server deleted"; else status_fail "server deletion failed"; fi
	fi
	if [ -n "$firewall" ]; then
		note "deleting firewall ${firewall}"
		if retry 6 5 -- hetzner_delete_firewall "$firewall"; then
			status_pass "firewall deleted"
		else status_fail "firewall deletion failed"; fi
	fi
	if [ -n "$sshkey" ]; then
		if hetzner_delete_ssh_key "$sshkey"; then status_pass "ssh key deleted"; else status_fail "ssh key deletion failed"; fi
	fi

	# Local state goes only after the remote resources are gone. Logs and
	# reports are preserved unless the operator asks for them to go too.
	rm -f "$GHO_STATE_FILE"
	rm -rf "$GHO_TMP_DIR"
	status_pass "local deployment state removed"
	note "logs kept in ${GHO_LOG_DIR}"
	note "reports kept in ${GHO_REPORT_DIR}"
	if ask_yes_no 'Also delete local logs and reports?' n; then
		rm -rf "$GHO_LOG_DIR" "$GHO_REPORT_DIR"
		status_pass "local logs and reports removed"
	fi
	note "remove the stale node from your tailnet admin console if it is still listed"
	return 0
}

# =================================================================== main ====

_stage_always_runs() {
	local a
	for a in $GHO_ALWAYS_STAGES; do
		[ "$a" = "$1" ] && return 0
	done
	return 1
}

run_stages() {
	local s
	for s in $GHO_STAGES; do
		if ! _stage_always_runs "$s" && ! stage_should_run "$s"; then
			printf '\n%s[--/%02d]%s %s%s%s %s(already done)%s\n' \
				"$C_DIM" "$GHO_TOTAL_STEPS" "$C_RESET" "$C_DIM" "$s" "$C_RESET" "$C_DIM" "$C_RESET"
			continue
		fi
		"stage_${s}" || return 1
	done
}

main() {
	parse_args "$@"
	state_paths_init
	GHO_LOG_FILE="${GHO_LOG_DIR}/deploy-$(date -u +%Y%m%dT%H%M%SZ).log"
	GHO_EVENT_LOG="${GHO_LOG_DIR}/events-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
	: >"$GHO_LOG_FILE"
	: >"$GHO_EVENT_LOG"
	chmod 600 "$GHO_LOG_FILE" "$GHO_EVENT_LOG"

	case "$GHO_MODE" in
	status)
		cmd_status
		return $?
		;;
	esac

	state_lock

	case "$GHO_MODE" in
	destroy)
		cmd_destroy
		return $?
		;;
	esac

	banner
	if [ "$GHO_MODE" = "resume" ]; then
		state_exists || die "nothing to resume: no state in ${GHO_STATE_DIR}"
		GHO_DEPLOYMENT_ID="$(state_get 'deployment_id')"
		note "resuming deployment ${GHO_DEPLOYMENT_ID}"
		note "last completed stage: $(state_last_done_stage "$GHO_STAGES" || echo none)"
	fi
	if [ "$GHO_MODE" = "dry-run" ]; then
		note "DRY RUN: credentials are validated and every artifact is rendered,"
		note "but no Hetzner resource is created and nothing is changed."
	fi

	run_stages || {
		trap - ERR
		failure_report
		exit 1
	}

	if [ "$GHO_MODE" = "dry-run" ]; then
		hr
		status_pass "dry run complete — nothing was created"
		note "run it for real with:  bash ./deploy.sh"
	fi
	return 0
}

# GHO_LIB_ONLY lets the test suite source this file and exercise the real stage
# functions without starting a deployment.
if [ "${GHO_LIB_ONLY:-0}" != "1" ]; then
	main "$@"
fi
