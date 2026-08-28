#!/usr/bin/env bash
# Input validation: everything that becomes a resource name, a DNS query, a
# cloud-init value or part of an SQL identifier is checked before use.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
load_libs

echo "unit: input validation"

for d in example.com blog.example.com a.b.c.example.co.uk xn--80ak6aa92e.com my-blog.example.io; do
	assert_ok "domain accepted: ${d}" validate_domain "$d"
done
for d in "" "example" "-example.com" "example-.com" "exa mple.com" "example..com" \
	"http://example.com" "example.com/path" "example.c" "example.com;rm -rf /" \
	'$(whoami).com' "exam\$ple.com"; do
	assert_fail "domain rejected: [${d}]" validate_domain "$d"
done

for e in a@b.co user.name+tag@example.com ops@sub.example.co.uk; do
	assert_ok "email accepted: ${e}" validate_email "$e"
done
for e in "" "a@b" "a b@c.com" "@example.com" "user@" "user@example" "user@exa mple.com"; do
	assert_fail "email rejected: [${e}]" validate_email "$e"
done

for n in ghost-blog my-blog blog1 ab1 ghost-blog-prod; do
	assert_ok "deployment name accepted: ${n}" validate_deployment_name "$n"
done
for n in "" "A" "ab" "1blog" "-blog" "blog-" "my--blog" "my blog" "my_blog" "my.blog" \
	"blog;rm" 'blog$(id)' "this-name-is-far-too-long-to-be-used-as-a-resource-name"; do
	assert_fail "deployment name rejected: [${n}]" validate_deployment_name "$n"
done

assert_ok "IPv4 accepted" validate_ipv4 "203.0.113.42"
assert_fail "IPv4 rejected: octet out of range" validate_ipv4 "203.0.113.999"
assert_fail "IPv4 rejected: not an address" validate_ipv4 "not-an-ip"

assert_ok "tailnet address accepted: 100.87.65.43" validate_tailscale_ipv4 "100.87.65.43"
assert_ok "tailnet address accepted: 100.64.0.1" validate_tailscale_ipv4 "100.64.0.1"
assert_ok "tailnet address accepted: 100.127.255.254" validate_tailscale_ipv4 "100.127.255.254"
assert_fail "tailnet address rejected: 100.63.0.1 (below CGNAT)" validate_tailscale_ipv4 "100.63.0.1"
assert_fail "tailnet address rejected: 100.128.0.1 (above CGNAT)" validate_tailscale_ipv4 "100.128.0.1"
assert_fail "tailnet address rejected: public IPv4" validate_tailscale_ipv4 "203.0.113.42"

assert_ok "ed25519 public key accepted" validate_ssh_pubkey \
	"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyMaterialAAAAAAAAAAAAAAAAAAAA operator@example"
assert_ok "rsa public key accepted" validate_ssh_pubkey \
	"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDExampleKeyMaterialAAAAAAAAAA"
assert_fail "private key rejected as a public key" validate_ssh_pubkey \
	"-----BEGIN OPENSSH PRIVATE KEY-----"
assert_fail "empty public key rejected" validate_ssh_pubkey ""

assert_ok "hetzner slug accepted" validate_hetzner_slug "cx23"
assert_fail "hetzner slug rejected: shell metacharacter" validate_hetzner_slug 'cx23;id'
assert_fail "hetzner slug rejected: space" validate_hetzner_slug "cx 23"

finish
