# ghost-hetzner-oneclick

A production Ghost blog on a fresh Hetzner Cloud VPS, from one command, with
**public SSH never opened at any point** — not during bootstrap, not
temporarily, not for your own IP.

```bash
bash ./deploy.sh
```

That is the whole deployment. No configuration file to edit, no manual SSH, no
commands to copy out of this README, no second command afterwards.

---

## What it deploys

| | |
|---|---|
| **Server** | Hetzner Cloud VPS, Ubuntu 24.04 LTS, x86, ≥ 2 GB RAM (default `cx23`) |
| **Blog** | Ghost 6.x on Node 22 LTS, MySQL 8.0, nginx reverse proxy, systemd |
| **TLS** | Let's Encrypt certificate, HTTP → HTTPS redirect, automatic renewal |
| **Access** | OpenSSH over Tailscale only, as the unprivileged user `ghostops` |
| **Hardening** | ufw default-deny, root and password SSH disabled, MySQL on loopback, unattended security updates, Ghost never runs as root |
| **Optional** | Hetzner server backups (billable), a nightly local backup timer, deletion protection |

Public inbound: **TCP 80, TCP 443, and ICMP. Nothing else. Ever.**

---

## The security model in one paragraph

The Hetzner Cloud Firewall is created *before* the server and attached *in the
same API call that creates it*, so the machine never exists in an unfiltered
state. Its inbound policy has no port 22 rule and never gains one. cloud-init
installs Tailscale, joins your tailnet with a one-time key, and configures ufw so
that TCP 22 is reachable only on `tailscale0`. Everything after that — uploading
scripts, installing Ghost, issuing the certificate, rebooting, verifying —
happens over the tunnel, to a `100.64.0.0/10` address. `rssh` and `rscp` refuse
any other destination, so there is no code path that can fall back to the public
IP. A live probe of public TCP 22 must **fail** three separate times: after
server creation, after installation, and after the final reboot. If it ever
succeeds, the deployment powers the server off and stops.

Full detail: [SECURITY.md](SECURITY.md) and [docs/security-model.md](docs/security-model.md).

---

## What you need

| | |
|---|---|
| **Hetzner Cloud** | A project and an API token with **Read & Write** |
| **Tailscale** | An account, this machine signed in, and one **one-time, pre-approved, ephemeral** auth key |
| **A domain** | A real registered domain or subdomain you control the DNS for |
| **A control machine** | macOS or Linux with bash 3.2+ |

Create the Tailscale key at <https://login.tailscale.com/admin/settings/keys>
with **Reusable: off**, **Ephemeral: on**, **Pre-approved: on**, and a short
expiry. This matters — see "cloud-init secret limitations" in SECURITY.md.

`deploy.sh` handles the rest of the tooling itself. If `jq` or `hcloud` are
missing it offers to download them into a repository-local `.tools/bin`,
verifying the publisher's checksum first. You are never told to install
something and start over.

---

## Deploy

```bash
git clone <this repo>
cd ghost-hetzner-oneclick
bash ./deploy.sh
```

The wizard runs twelve stages, each ending in `PASS`, `FAIL`, `SKIP` or
`WARNING`:

```
[01/12] Checking local prerequisites
[02/12] Validating credentials
[03/12] Collecting deployment settings
[04/12] Creating the Hetzner firewall
[05/12] Creating the VPS
[06/12] Waiting for cloud-init and Tailscale
[07/12] Verifying private SSH
[08/12] Installing Ghost
[09/12] Configuring DNS and HTTPS
[10/12] Running security checks
[11/12] Rebooting and testing recovery
[12/12] Creating the final report
```

It asks for: the Hetzner token and Tailscale key (hidden input), a deployment
name, a location, a server type, your domain, a Let's Encrypt email, the DNS
mode, whether to create a dedicated SSH key, and four yes/no options (Hetzner
backups, a nightly local backup timer, the final reboot test, deletion
protection). Then it prints a summary — including the monthly price — and asks
once before creating anything billable.

Roughly 12–20 minutes, most of it Ghost's install and certificate issuance.

### After it finishes

The report ends with the admin URL. **Open it and create the owner account.**
Ghost does not create it for you, and the first person to reach that page becomes
the owner — so do it now, not tomorrow.

---

## Commands

```bash
bash ./deploy.sh                    # interactive deployment (the default)
bash ./deploy.sh --resume           # continue an interrupted deployment
bash ./deploy.sh --status           # what state is this deployment in
bash ./deploy.sh --dry-run          # validate and render everything, create nothing
bash ./deploy.sh --destroy          # delete every resource of this deployment
bash ./deploy.sh --non-interactive  # take every answer from the environment
bash ./deploy.sh --keep-on-failure  # never offer cleanup after a failure
bash ./deploy.sh --verbose          # echo debug lines to the terminal
```

### Non-interactive environment

```bash
export HCLOUD_TOKEN=...            # required
export TS_AUTHKEY=tskey-auth-...   # required
export CF_API_TOKEN=...            # only for GHO_DNS_MODE=cloudflare
export GHO_DOMAIN=blog.example.com # required
export GHO_LE_EMAIL=ops@example.com # required
export GHO_NAME=ghost-blog         # default: ghost-blog
export GHO_LOCATION=nbg1           # default: nbg1
export GHO_SERVER_TYPE=cx23        # default: cx23
export GHO_DNS_MODE=manual         # manual | cloudflare
export GHO_SSH_KEY=~/.ssh/id_ed25519
export GHO_HETZNER_BACKUPS=n GHO_LOCAL_BACKUPS=y GHO_REBOOT_TEST=y GHO_PROTECT=y

bash ./deploy.sh --non-interactive
```

---

## DNS

**Manual (default).** The deployment prints the exact A (and AAAA) records,
then keeps running and polls 1.1.1.1, 8.8.8.8 and 9.9.9.9. It continues by
itself the moment all three agree. If fifteen minutes pass it asks whether to
keep waiting — you never have to restart.

**Cloudflare.** Supply a token scoped to `Zone:DNS:Edit` on that zone only. The
deployment finds the zone, shows any existing record and asks before
overwriting, writes the records **DNS-only** (proxying breaks ACME `http-01`),
verifies propagation, and offers to turn proxying on once HTTPS works.

The token is entered hidden, passed to `curl` through a 0600 config file, and
never stored.

---

## What gets created at Hetzner

| Resource | Name | Notes |
|---|---|---|
| Firewall | `gho-<name>-fw` | Created first. 80, 443, ICMP. No SSH. |
| Server | `gho-<name>` | Firewall attached in the create request. |
| SSH key | `gho-<name>-key` | Optional; suppresses the emailed root password. |

Every one carries:

```
managed-by=ghost-hetzner-oneclick
deployment-id=<generated>
application=ghost
environment=production
```

`--destroy` refuses to touch anything that does not carry the current
deployment id.

---

## Connecting afterwards

```bash
ssh ghostops@gho-ghost-blog.your-tailnet.ts.net
# or
ssh ghostops@100.x.y.z
```

The exact command, with your actual names, is printed in the final report and
stored in `.ghost-hetzner/reports/final-report.txt`.

There is no command that uses the public IP, because there is nothing listening
there. If you lose tailnet access, the Hetzner web console (VNC) is the recovery
path — that is the intended trade-off.

### How the tunnel access works

Your workstation and the server are both nodes in your tailnet. The server dials
out to Tailscale; nothing dials in. SSH travels inside that WireGuard session to
the server's `100.64.0.0/10` address. The host firewall allows 22 on the
`tailscale0` interface only, so even a misconfigured provider firewall would not
expose it.

If your tailnet ACL does not let you reach port 22, the deployment says so
precisely, prints the node name and address and a sample ACL rule, and preserves
state so `--resume` continues once you have fixed it. It does not open public
SSH as a workaround.

---

## Maintenance

### Updating Ghost

```bash
ssh ghostops@<tailnet-name>
cd /var/www/ghost
ghost backup            # always, first
ghost update
ghost status
```

Roll back with `ghost update --rollback`. Ghost 6 requires Node 22; a major Node
change is a separate, deliberate operation — do not let an unrelated upgrade
move it.

### Backups

Two independent things, both optional, both offered during the wizard:

**Hetzner server backups** — billable, roughly 20% of the server price. Whole-disk
snapshots managed by the provider. Restore from the Hetzner console.

**Local nightly backups** — free, `/var/backups/ghost`, root-owned, 0600, seven
retained by default. Each archive holds a `mysqldump` and the entire `content`
directory (themes, images, uploaded media, routes), plus Ghost's own export when
the site is running. A `systemd` timer runs it at 03:20 with a randomised delay,
and the deployment runs it once and verifies the archive is non-empty before
declaring success.

```bash
ssh ghostops@<tailnet-name> 'sudo systemctl list-timers ghost-backup.timer'
ssh ghostops@<tailnet-name> 'sudo systemctl start ghost-backup.service'
ssh ghostops@<tailnet-name> 'sudo ls -lh /var/backups/ghost'
```

**These live on the same disk as the site.** If the server is lost, they are lost
with it. Copy them somewhere else:

```bash
scp ghostops@<tailnet-name>:/var/backups/ghost/ghost-backup-*.tar.gz ./
```

To restore:

```bash
tar -xzf ghost-backup-<stamp>.tar.gz
ssh ghostops@<tailnet-name> 'cd /var/www/ghost && ghost stop'
# restore the dump, then the content directory, then:
ssh ghostops@<tailnet-name> 'cd /var/www/ghost && ghost start'
```

Or import `content/data/*.json` through Ghost Admin → Settings → Import.

---

## Local files

```
.ghost-hetzner/
├── state.json          deployment state — never contains a credential
├── known_hosts         host keys pinned for this deployment only
├── ssh/                the dedicated deployment key, if you chose one
├── logs/               redacted human logs and JSONL event logs
├── reports/            final-report.json and final-report.txt
└── tmp/                emptied on exit
```

Everything is mode 0600 in a 0700 directory. `.ghost-hetzner/` and `.tools/` are
git-ignored.

---

## Tests

```bash
bash tests/run.sh
```

Runs the unit suite, the repository security invariants, ShellCheck and shfmt.
No credentials required — every external command is mocked. The live test is
opt-in and creates real billable resources:

```bash
RUN_LIVE_TESTS=1 LIVE_TEST_CONFIRM=I-ACCEPT-HETZNER-CHARGES bash tests/run.sh
```

The security tests fail the build if the repository ever gains
`PasswordAuthentication yes`, `PermitRootLogin yes`, a firewall rule for port
22, a `ufw` SSH rule not bound to `tailscale0`, `StrictHostKeyChecking=no`, a
`curl -k`, a hardcoded token or password, a private key block, `set -x`, or an
ssh/scp command aimed at a public address.

---

## Costs

You are creating billable resources.

| | |
|---|---|
| Server | roughly €4–6/month for the default `cx23` — the exact gross price for your chosen type and location is shown in the summary before anything is created |
| Hetzner backups | +20% of the server price, only if you enable them |
| Traffic | included in the server allowance for normal blog use |
| Tailscale | free for personal use |
| Let's Encrypt | free |

`bash ./deploy.sh --destroy` removes everything this project created. A failed
deployment does **not** delete resources automatically — you may want to inspect
them — so check `--status` and destroy explicitly if you are abandoning a run.

---

## Known limitations

* **Tailscale is the only tunnel provider.** The code is structured behind a
  small `tunnel_*` interface so another could be added, but nothing else is
  implemented, and nothing else is claimed to work.
* **The auth key passes through cloud-init user-data**, and Hetzner's metadata
  service keeps serving that user-data to the instance for its lifetime. This is
  why the key must be one-time and ephemeral. See SECURITY.md.
* **Losing tailnet access means using the Hetzner web console.** There is no
  emergency public SSH. That is the design, not an oversight.
* **A domain is mandatory.** Ghost's canonical URL and Let's Encrypt both need
  one; there is no IP-only mode.
* **Local backups are not disaster recovery.** Same disk, same failure domain.
* **Outbound traffic is unrestricted.** An untested egress allow-list that
  breaks certificate renewal weeks later is worse than none.
* **The owner account is not automated.** Creating it through direct database
  manipulation is unsupported by Ghost and would break on the next release.
* **One deployment per checkout.** State lives in `.ghost-hetzner/`; for a second
  blog, use a second clone.
* **x86 by default.** ARM (`cax*`) types exist and are cheaper, but the version
  matrix was verified on x86.

---

## Documentation

* [SECURITY.md](SECURITY.md) — threat model, credential handling, verification
* [docs/architecture.md](docs/architecture.md) — the two-stage design and a sequence diagram
* [docs/security-model.md](docs/security-model.md) — why each decision was made
* [docs/version-matrix.md](docs/version-matrix.md) — pinned versions and their sources
* [docs/troubleshooting.md](docs/troubleshooting.md) — what to do when a stage fails

---

## Public SSH

**Public SSH is never required and never permitted by this project.** There is no
flag, no environment variable, no prompt and no recovery path that opens TCP 22
on a public address. If a check ever finds it open, the deployment treats it as a
security incident: it powers the server off, reapplies the restrictive firewall,
and refuses to continue.

---

## Licence

MIT — see [LICENSE](LICENSE).
