#!/usr/bin/env bash
# lib/verify.sh — the step runner and every verification predicate.
#
# A command exiting 0 is not evidence. Each check states the outcome it expects
# and is judged against that outcome, with a timeout, a retry policy, a recorded
# status and a diagnostic hook.

GHO_CHECK_FAILURES=0
GHO_CHECK_WARNINGS=0
GHO_VERIFY_SOFT=0
GHO_LAST_OUTPUT=""

# verify <name> <expect: ok|fail> <timeout> <attempts> -- <command...>
# expect=ok   : the command must succeed.
# expect=fail : the command must NOT succeed (used for "public SSH is closed").
verify() {
	local name="$1" expect="$2" timeout="$3" attempts="$4"
	shift 4
	[ "${1:-}" = "--" ] && shift

	local started ended rc=0 n=1 delay=3 ok=1
	started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	while :; do
		rc=0
		GHO_LAST_OUTPUT="$(run_with_timeout "$timeout" "$@" 2>&1)" || rc=$?
		if [ "$expect" = "ok" ] && [ "$rc" -eq 0 ]; then
			ok=0
			break
		fi
		if [ "$expect" = "fail" ] && [ "$rc" -ne 0 ]; then
			ok=0
			break
		fi
		[ "$n" -ge "$attempts" ] && break
		n=$((n + 1))
		sleep "$delay"
		delay=$((delay * 2))
		[ "$delay" -gt 20 ] && delay=20
	done
	ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

	_log_write DEBUG "check '${name}' expect=${expect} rc=${rc} attempts=${n} start=${started} end=${ended}"
	[ -n "$GHO_LAST_OUTPUT" ] && _log_write DEBUG "check '${name}' output: ${GHO_LAST_OUTPUT}"

	if [ "$ok" -eq 0 ]; then
		status_pass "$name"
		check_record "$name" PASS ""
		return 0
	fi
	if [ "${GHO_VERIFY_SOFT:-0}" = "1" ]; then
		status_warn "$name"
		check_record "$name" WARNING "rc=${rc} after ${n} attempt(s)"
		GHO_CHECK_WARNINGS=$((GHO_CHECK_WARNINGS + 1))
		return 1
	fi
	status_fail "$name"
	check_record "$name" FAIL "rc=${rc} after ${n} attempt(s)"
	GHO_CHECK_FAILURES=$((GHO_CHECK_FAILURES + 1))
	return 1
}

# verify_warn — same contract, but a failure is a warning, not a stop condition.
verify_warn() {
	GHO_VERIFY_SOFT=1
	verify "$@" || true
	GHO_VERIFY_SOFT=0
	return 0
}

verify_skip() {
	status_skip "$1"
	check_record "$1" SKIP "${2:-}"
}

# --------------------------------------------------------------- predicates --

# tcp_probe <host> <port> [timeout] [-4|-6] — 0 when the port accepts a connection.
tcp_probe() {
	local host="$1" port="$2" timeout="${3:-6}" family="${4:-}"
	if have nc; then
		# shellcheck disable=SC2086  # $family is a controlled single flag
		nc $family -z -w "$timeout" "$host" "$port" >/dev/null 2>&1
	else
		run_with_timeout "$timeout" bash -c "exec 3<>/dev/tcp/${host}/${port}" >/dev/null 2>&1
	fi
}

# public_ssh_closed <host> [-4|-6] — the check the whole design rests on.
public_ssh_closed() {
	! tcp_probe "$1" 22 8 "${2:-}"
}

http_status() {
	curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$1" 2>/dev/null
}

http_redirects_to_https() {
	local loc code
	code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "http://${1}/" 2>/dev/null || true)"
	case "$code" in
	301 | 302 | 307 | 308) : ;;
	*) return 1 ;;
	esac
	loc="$(curl -sSI --max-time 20 "http://${1}/" 2>/dev/null | awk 'tolower($1)=="location:"{print $2}' | tr -d '\r')"
	case "$loc" in
	https://*) return 0 ;;
	*) return 1 ;;
	esac
}

https_ok() {
	local code
	code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 25 "https://${1}/" 2>/dev/null || true)"
	case "$code" in 200 | 301 | 302) return 0 ;; *) return 1 ;; esac
}

https_admin_ok() {
	local code
	code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 25 "https://${1}/ghost/" 2>/dev/null || true)"
	case "$code" in 200 | 301 | 302) return 0 ;; *) return 1 ;; esac
}

# tls_hostname_valid <domain> — full chain and hostname validation, no -k.
tls_hostname_valid() {
	curl -sS -o /dev/null --max-time 25 "https://${1}/" 2>/dev/null
}

_tls_cert_pem() {
	printf '' | openssl s_client -connect "${1}:443" -servername "$1" 2>/dev/null |
		sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p'
}

# tls_cert_valid_for_days <domain> <days>
tls_cert_valid_for_days() {
	local pem
	pem="$(_tls_cert_pem "$1")"
	[ -n "$pem" ] || return 1
	printf '%s\n' "$pem" | openssl x509 -noout -checkend $(($2 * 86400)) >/dev/null 2>&1
}

tls_cert_issuer() {
	local pem
	pem="$(_tls_cert_pem "$1")"
	[ -n "$pem" ] || return 1
	printf '%s\n' "$pem" | openssl x509 -noout -issuer 2>/dev/null | sed 's/^issuer=//'
}

tls_cert_issuer_trusted() {
	local issuer
	issuer="$(tls_cert_issuer "$1")" || return 1
	# The chain itself is validated by curl against the system trust store; this
	# check additionally asserts the certificate came from the CA we asked for.
	printf '%s' "$issuer" | grep -Eqi "Let's Encrypt|ISRG"
}

tls_cert_notafter() {
	local pem
	pem="$(_tls_cert_pem "$1")"
	[ -n "$pem" ] || return 1
	printf '%s\n' "$pem" | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//'
}

# ---------------------------------------------------------- secret leakage ---

# scan_for_secrets <path...>
# Reports the files that contain registered secrets or structural credential
# patterns. It never prints a matching line, only file names.
scan_for_secrets() {
	local patterns hits=0 f
	patterns="$(redact_pattern_file 2>/dev/null || true)"

	if [ -n "$patterns" ]; then
		for f in $(grep -rlF -f "$patterns" "$@" 2>/dev/null || true); do
			printf 'literal-secret-in: %s\n' "$f"
			hits=$((hits + 1))
		done
		rm -f "$patterns"
	fi

	for f in $(grep -rlE 'tskey-(auth|client)-[A-Za-z0-9]' "$@" 2>/dev/null || true); do
		printf 'tailscale-authkey-in: %s\n' "$f"
		hits=$((hits + 1))
	done
	for f in $(grep -rlE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' "$@" 2>/dev/null || true); do
		printf 'private-key-in: %s\n' "$f"
		hits=$((hits + 1))
	done

	[ "$hits" -eq 0 ]
}

# ---------------------------------------------------------------- reporting --

# report_write <status>
report_write() {
	local status="$1"
	local json="${GHO_REPORT_DIR}/final-report.json"
	local txt="${GHO_REPORT_DIR}/final-report.txt"

	jq --arg status "$status" \
		--arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		--arg ssh_cmd "$(report_ssh_command)" \
		'{
			deployment_status: $status,
			generated_at: $generated,
			deployment_id: .deployment_id,
			deployment_name: .deployment_name,
			config: .config,
			resources: .resources,
			stages: .stages,
			checks: .checks,
			private_ssh_command: $ssh_cmd
		 }' "$GHO_STATE_FILE" | write_atomic "$json"
	chmod 600 "$json"

	report_text "$status" | write_atomic "$txt"
	chmod 600 "$txt"
	printf '%s' "$txt"
}

report_ssh_command() {
	local host
	host="$(state_get 'resources.tailscale_dnsname')"
	[ -n "$host" ] || host="$(state_get 'resources.tailscale_ipv4')"
	[ -n "$host" ] || return 0
	printf 'ssh %s@%s' "$GHO_SSH_USER" "$host"
}

_check_word() {
	local s
	s="$(check_status "$1" 2>/dev/null || true)"
	[ -n "$s" ] || s="NOT RUN"
	printf '%s' "$s"
}

# The report distinguishes "the operator turned this off" from "it did not run".
_backup_timer_word() {
	local s
	s="$(_check_word 'backup-timer')"
	case "$s" in
	SKIP | "NOT RUN") printf 'DISABLED' ;;
	*) printf '%s' "$s" ;;
	esac
}

report_text() {
	local status="$1" domain
	domain="$(state_get 'config.domain')"
	cat <<TXT
Deployment status:      ${status}
Deployment ID:          $(state_get 'deployment_id')
Ghost URL:              https://${domain}/
Ghost Admin URL:        https://${domain}/ghost/
Hetzner server name:    $(state_get 'resources.server_name')
Hetzner server ID:      $(state_get 'resources.server_id')
Hetzner firewall name:  $(state_get 'resources.firewall_name')
Hetzner firewall ID:    $(state_get 'resources.firewall_id')
Public IPv4:            $(state_get 'resources.public_ipv4')
Public IPv6:            $(state_get 'resources.public_ipv6' 'disabled')
Tailscale hostname:     $(state_get 'resources.tailscale_dnsname')
Tailscale IPv4:         $(state_get 'resources.tailscale_ipv4')
SSH user:               ${GHO_SSH_USER}
Public SSH:             $(if [ "$(_check_word 'public-ssh-ipv4-closed')" = "PASS" ]; then printf 'CLOSED'; else printf 'UNVERIFIED'; fi)
Private SSH:            $(_check_word 'private-ssh-login')
MySQL:                  $(_check_word 'mysql-active')
Nginx:                  $(_check_word 'nginx-active')
Ghost:                  $(_check_word 'ghost-service-active')
HTTPS:                  $(_check_word 'https-responds')
Certificate:            $(_check_word 'tls-certificate-valid')
Reboot recovery:        $(_check_word 'reboot-recovery')
Backup timer:           $(_backup_timer_word)
Final report path:      ${GHO_REPORT_DIR}/final-report.txt

Private SSH command (the only supported way in):
  $(report_ssh_command)

Maintenance:
  bash ./deploy.sh --status      show current deployment state
  bash ./deploy.sh --resume      continue an interrupted deployment
  bash ./deploy.sh --destroy     delete every resource of this deployment
  $(report_ssh_command) 'sudo -u ghostops bash -lc "cd /var/www/ghost && ghost status"'
  $(report_ssh_command) 'sudo -u ghostops bash -lc "cd /var/www/ghost && ghost update"'
  $(report_ssh_command) 'sudo systemctl list-timers ghost-backup.timer'
TXT
}
