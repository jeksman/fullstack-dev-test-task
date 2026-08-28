# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-08-28

First release.

### Added

* **One-command deployment.** `bash ./deploy.sh` runs an interactive twelve-stage
  wizard from an empty Hetzner project to a working Ghost blog with HTTPS. No
  configuration file to edit and no second command.
* **Public SSH is never opened.** The Hetzner Cloud Firewall is created before
  the server and attached in the create request. Its inbound policy is TCP 80,
  TCP 443 and ICMP; there is no port 22 rule at any point, including during
  bootstrap.
* **Tailscale bootstrap through cloud-init.** Stage 1 creates `ghostops`,
  installs its key, hardens sshd, configures `ufw` so TCP 22 is reachable only on
  `tailscale0`, joins the tailnet with a one-time key passed as
  `--auth-key=file:`, and then shreds every copy of that key it can reach.
* **Stage 2 entirely over the tunnel.** Node discovery from
  `tailscale status --json`, host-key pinning into a deployment-specific
  `known_hosts`, and `scp`/`ssh` to the `100.64.0.0/10` address only.
  `ssh_assert_private_target` makes a public-IP fallback structurally impossible.
* **Production Ghost stack.** Ubuntu 24.04, Node 22 LTS, MySQL 8.0 bound to
  loopback, nginx, systemd, Let's Encrypt with HTTP→HTTPS redirect. Ghost runs as
  `ghostops`, never root and never as a user named `ghost`.
* **Database password rotation.** The credential Ghost keeps on disk is never a
  process argument: install uses a throwaway password, then the account is
  rotated through 0600 SQL and config files.
* **Verification after every stage.** A step runner with explicit expected
  outcomes, timeouts, bounded retries and recorded status. The public-SSH-closed
  check is an expected *failure* and runs three times: after creation, after
  installation, and after the reboot.
* **Reboot recovery validation.** Reboots through the Hetzner API and verifies
  the tailnet, SSH, MySQL, nginx, Ghost, HTTPS and the still-closed public 22.
* **Containment on critical failure.** An open public 22, a detached firewall, a
  server-side sshd or firewall regression, or a leaked credential powers the
  machine off, reapplies the restrictive policy and stops.
* **Secret redaction everywhere.** A registry plus structural patterns, applied
  to all terminal output and every log line. No secret is ever a command-line
  argument; `set -x` appears nowhere in the repository.
* **State, resume, status, dry-run and destroy.** Atomic state writes, a
  deployment lock with stale-owner reclamation, per-stage idempotency, and a
  destroy path that refuses anything not carrying the current deployment id.
* **DNS modes.** Manual with multi-resolver polling that continues by itself, or
  Cloudflare through a scoped token with explicit confirmation before overwriting
  an existing record.
* **Optional backups.** Hetzner server backups, and a nightly local timer that is
  executed and verified once during deployment.
* **Local dependency management.** `jq` and the `hcloud` CLI are downloaded into
  `.tools/bin` with the publisher's checksum verified. The Tailscale CLI is
  located, including the macOS app bundle path.
* **Test suite.** 14 test files, 378 assertions, all external commands mocked.
  Repository security invariants, ShellCheck and shfmt run as part of it. The
  live test is opt-in and double-gated.
* **Documentation.** README, SECURITY.md, and docs for architecture (with a
  Mermaid sequence diagram), the security model's rationale, the pinned version
  matrix with its verification date, and troubleshooting.

### Security notes

* The Tailscale auth key necessarily transits cloud-init user-data, which
  Hetzner's metadata service continues to serve to the instance. The key must
  therefore be one-time, ephemeral and pre-approved. This is documented in
  SECURITY.md and warned about at the credentials stage.
* Outbound traffic is deliberately unrestricted. An untested egress allow-list
  that breaks certificate renewal is worse than none.

### Known limitations

See the "Known limitations" section of the README.
