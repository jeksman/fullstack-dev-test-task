# Security model

## Threat model

**Who this defends against**

| Adversary | Capability | Mitigation |
|---|---|---|
| Internet-wide scanners | Continuously probe every IPv4 and IPv6 address for open SSH, then brute-force or credential-stuff | TCP 22 is never open on a public address. There is no rule to find, so there is nothing to attack. |
| An attacker with a stolen SSH password | Password guessing against a known user | Password authentication is disabled at the sshd level, and there is no password to guess. Only `publickey` is accepted. |
| An attacker who reaches the host over HTTP/HTTPS | Exploit Ghost, Node or nginx | Ghost runs as `ghostops`, never root. MySQL listens on loopback only. The host firewall denies inbound by default. Security updates are applied unattended. |
| A compromised local shell history / process table | Read credentials from `ps` or `~/.bash_history` | Secrets are read with `read -s`, passed through 0600 files or environment variables, and never appear as command-line arguments. `set -x` appears nowhere in the repository, enforced by a test. |
| Someone who obtains the deployment logs or state file | Read credentials from artifacts | Everything written to a log passes through the redactor. `state_put` refuses to store any registered secret. A leakage scan runs as a deployment stage and as a repository test. |

**Who this does not defend against**

* A compromised Tailscale account. Whoever controls your tailnet controls
  administrative access to the server. Use SSO with MFA and tailnet ACLs.
* A compromised Hetzner API token with write scope. It can rewrite the firewall.
* A malicious or compromised upstream: Ubuntu archives, NodeSource, npm,
  `pkgs.tailscale.com`, `get.docker.com`-style installer scripts.
* Physical or hypervisor-level access at the provider.
* Data loss. Local backups sit on the same disk as the site. They are not
  disaster recovery.

## Trust boundaries

```
  operator's workstation  │  the only place secrets are typed
  ────────────────────────┼──────────────────────────────────────────
  Hetzner API             │  trusted with the token's write scope
  Hetzner Cloud Firewall  │  enforces the public port policy
  ────────────────────────┼──────────────────────────────────────────
  Tailscale control plane │  decides which devices are in the tailnet
  the tailnet             │  the administrative access path
  ────────────────────────┼──────────────────────────────────────────
  the VPS                 │  runs Ghost; holds the DB password
  the public internet     │  may reach only TCP 80 and 443
```

The VPS is not trusted with anything it does not need. It never receives the
Hetzner token, the Cloudflare token, or your personal SSH key. It receives one
public key and one auth key that stops working the moment it is used.

## Credential handling

| Credential | Where it is entered | Where it goes | Lifetime on disk |
|---|---|---|---|
| Hetzner API token | hidden prompt or `HCLOUD_TOKEN` | `HCLOUD_TOKEN` in the environment of `hcloud` child processes only | never written |
| Tailscale auth key | hidden prompt or `TS_AUTHKEY` | rendered into the 0600 cloud-init file; on the server into `/root/.gho-authkey` (0600) then `/run/gho-authkey` (tmpfs) | shredded by the bootstrap the moment the node joins |
| Cloudflare token | hidden prompt or `CF_API_TOKEN` | a 0600 `curl --config` file, deleted after each call | never written to state or logs |
| MySQL application password | generated **on the VPS** | `config.production.json`, mode 0600, owned by `ghostops` | permanent, never leaves the server |
| SSH private key | generated locally, or an existing key you name | stays on your workstation | `.ghost-hetzner/ssh/id_ed25519`, mode 0600 |

No secret is ever an argument to a command:

* `tailscale up --auth-key=file:/run/gho-authkey`
* `mysql < 0600-sql-file`, `mysqldump --defaults-extra-file=0600-file`
* `curl --config 0600-file` for the Cloudflare API
* the redactor builds its `sed` program in a 0600 file rather than passing the
  secret on the `sed` command line

### The one exception, and why it is bounded

`ghost install` accepts the database password only as `--dbpass`, so for the
duration of that single command it is visible in `/proc`. The installer works
around this: it installs with a throwaway generated credential, then rotates the
account to a second generated password using a 0600 SQL file and patches
`config.production.json` with `jq`. The password Ghost keeps on disk has never
been a process argument. This is documented in `remote/install-ghost.sh` at the
`rotate_db_password` function.

## cloud-init secret limitations

**This is the sharpest edge in the design. Read it.**

The Tailscale auth key has to reach the server before any private channel
exists, so it travels inside cloud-init user-data. That means:

1. It is stored by Hetzner as part of the server's configuration.
2. It is served, unauthenticated, to anything running **on that instance** at
   `http://169.254.169.254/hetzner/v1/userdata`, for the life of the server.
3. The bootstrap script shreds `/root/.gho-authkey` and `/run/gho-authkey`, and
   rewrites the on-disk cloud-init copies under `/var/lib/cloud` and
   `/run/cloud-init` to `REDACTED-BY-GHO-BOOTSTRAP`. It **cannot** scrub the
   provider's metadata service.

Therefore the key must be worthless by the time anyone could read it:

* **One-time / single-use.** It authenticates exactly one node and is then spent.
* **Ephemeral**, so the node is removed from the tailnet when it goes offline.
* **Pre-approved**, so no manual approval step stalls an unattended deployment.
* Short expiry — an hour is plenty.

Create it at <https://login.tailscale.com/admin/settings/keys>. `deploy.sh`
prints this warning at the credentials stage; it is not decoration.

If you need to eliminate even the spent-key exposure, revoke the key in the
Tailscale admin console after the deployment reports success.

## Provider firewall controls

Created **before** the server and attached **in the server-creation request**.
The machine never exists in an unfiltered state.

Inbound policy, and nothing else:

| Protocol | Port | Source |
|---|---|---|
| TCP | 80 | `0.0.0.0/0`, `::/0` |
| TCP | 443 | `0.0.0.0/0`, `::/0` |
| ICMP | — | `0.0.0.0/0`, `::/0` (optional) |

Outbound is unrestricted. A half-implemented egress policy that breaks apt, DNS,
NTP, ACME or the Tailscale relay is worse than none; this project does not ship
one it has not tested.

Three independent checks enforce the SSH invariant:

1. The renderer refuses to emit a policy containing an inbound TCP 22 rule or an
   open-ended TCP range — `hetzner_render_firewall_rules`.
2. After creation, the rules stored at Hetzner are read back and compared to the
   intended policy — `hetzner_firewall_matches_policy`.
3. A live TCP probe against the public IPv4 and IPv6 must **fail** — and is run
   again after Ghost is installed and again after the reboot.

## Host firewall controls

`ufw`, applied in cloud-init and re-asserted by `remote/configure-security.sh`:

```
default deny incoming
default allow outgoing
allow 80/tcp
allow 443/tcp
allow in on tailscale0 to any port 22 proto tcp
```

`configure-security.sh` actively deletes any SSH rule that is not bound to
`tailscale0`, then fails the deployment if one survives.

## SSH key management

* Default: a dedicated ed25519 key generated per deployment in
  `.ghost-hetzner/ssh/`, mode 0600. It authorises exactly this one server.
* You may name an existing key instead; only its public half is uploaded.
* The server's host key is pinned into `.ghost-hetzner/known_hosts` on first
  contact, with `StrictHostKeyChecking=yes` throughout.
  `StrictHostKeyChecking=no` appears nowhere in the repository, enforced by a
  test. Trust-on-first-use is acceptable here because the first contact already
  happens inside an authenticated WireGuard tunnel to a node the Tailscale
  control plane vouched for — there is no plaintext window to occupy.
* sshd accepts `AuthenticationMethods publickey` from `AllowUsers ghostops`
  only. Root login, passwords, keyboard-interactive and empty passwords are all
  refused, and the effective configuration is read back with `sshd -T` and
  asserted — not merely written to a file and hoped for.

## Secret rotation

| Secret | How to rotate |
|---|---|
| Tailscale auth key | Nothing to do: it is single-use and spent. Revoke it in the admin console for completeness. |
| Hetzner API token | Create a new one in the Hetzner console, delete the old one. This project stores nothing. |
| SSH key | Generate a new key, append the public half to `/home/ghostops/.ssh/authorized_keys` over the tunnel, verify you can log in with it, then remove the old line. |
| MySQL password | `ALTER USER 'ghost_app'@'127.0.0.1' IDENTIFIED BY '<new>';` from a 0600 SQL file, patch `config.production.json` with `jq`, `ghost restart`. This is exactly what `rotate_db_password` does. |
| TLS certificate | Renewed automatically by the acme.sh timer that Ghost-CLI installs. |

## Incident recovery

**If a check reports that public TCP 22 is reachable**, the deployment does not
continue. It powers the server off through the Hetzner API, reapplies the
deny-by-default firewall policy, marks the deployment failed, and stops.
`security_incident` in `deploy.sh` is the only code path that does this, and it
is triggered by: an open public 22, a firewall that is missing or detached, a
rendered policy containing SSH, a server-side firewall or sshd regression, or a
credential found in the state file or an artifact.

**If you suspect the server is compromised:**

1. `hcloud server poweroff gho-<name>` — stop it before investigating.
2. Revoke the Hetzner token and the Tailscale key.
3. Remove the node in the Tailscale admin console.
4. Take a snapshot for forensics if you need one.
5. Rebuild: `bash ./deploy.sh --destroy`, then `bash ./deploy.sh` with fresh
   credentials, and restore content from a backup you copied **off** the server.

## Verifying public SSH is closed, yourself

Do not take this project's word for it.

```bash
IP=$(jq -r .resources.public_ipv4 .ghost-hetzner/reports/final-report.json)

# Must time out or be refused.
nc -vz -w 8 "$IP" 22

# Must connect.
nc -vz -w 8 "$IP" 443

# The provider's own view of the policy — there must be no port 22 rule.
hcloud firewall describe gho-<name>-fw -o json | jq '.rules'

# The host's own view.
ssh ghostops@<tailnet-name> 'sudo ufw status verbose'
```

## Reporting a vulnerability

Open an issue describing the class of problem and the affected component. Do not
include working exploit code or extracted credentials.
