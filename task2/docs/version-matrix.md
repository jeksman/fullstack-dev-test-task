# Version matrix

**Verified against official documentation on 2026-08-28.**

Everything below is pinned in [`versions.env`](../versions.env). Nothing in this
project installs "latest" of a runtime without a compatibility statement here.

## What Ghost requires

| Component | Pinned value | Why | Source |
|---|---|---|---|
| Ubuntu | `ubuntu-24.04` | Ghost supports 22.04, 24.04 and 26.04. 24.04 LTS is the middle option: MySQL 8.0 is in `main`, and standard support runs to 2029. | Ghost, *Install Ghost on Ubuntu* |
| Node.js | `22` (Node v22 "Jod" LTS) | Ghost ≥ 6.0.0 requires `^22.13.1`. Node 20 and 24 are listed as **unsupported**, not merely untested. | Ghost, *Node.js version support* |
| MySQL | `mysql-server-8.0` | Ghost supports MySQL 8.0 or 8.4. Ubuntu 24.04 ships 8.0.x in `main`, so it gets distribution security updates. | Ghost, *Install Ghost on Ubuntu* |
| Nginx | distribution package | Ghost requires ≥ 1.9.5 for SSL. Ubuntu 24.04 ships 1.24. | Ghost, *Install Ghost on Ubuntu* |
| Ghost-CLI | `ghost-cli@^1.28.0` | 1.x is the current CLI generation. Pinned to a major range so a future 2.x cannot silently change the flags this installer depends on. | Ghost, *Ghost-CLI* |
| Ghost | 6.x | Installed by Ghost-CLI. | — |
| Process manager | systemd | Required by Ghost for production. | Ghost, *Install Ghost on Ubuntu* |
| Memory | ≥ 2 GB, default `cx23` (4 GB) | Ghost documents 1 GB as the minimum; MySQL 8 plus a Node build wants more. A swap file is created automatically below ~3.7 GB RAM. | Ghost, *Install Ghost on Ubuntu* |

## Local helper tooling

| Component | Pinned value | Notes |
|---|---|---|
| hcloud CLI | `1.67.0` | Downloaded into `.tools/bin` when absent. The publisher's `checksums.txt` is fetched and verified before the binary is made executable. |
| jq | `1.8.2` | Downloaded into `.tools/bin` when absent, verified against the release `sha256sum.txt`. |
| Tailscale | verified against `1.102.3` | Never downloaded by this project: the CLI talks to a local daemon and has to come from a real installation. `deploy.sh` finds an existing one, including the macOS app bundle path. |
| Bash | 3.2 or newer | `deploy.sh` is written to macOS's bash 3.2. No associative arrays, no `mapfile`, no `${var,,}`. |

## Deliberately not pinned

* **The Tailscale package on the server.** cloud-init installs current stable
  from `pkgs.tailscale.com`. Pinning it would mean shipping a client that ages
  out of the control plane's supported window.
* **Ubuntu security updates.** `unattended-upgrades` is enabled and restricted
  to the `-security` pockets.

## How to re-verify

```bash
# Ghost's supported Node versions
curl -s https://docs.ghost.org/faq/node-versions/ | grep -i 'node v'

# Current hcloud CLI release and checksums
curl -s https://api.github.com/repos/hetznercloud/cli/releases/latest | jq -r .tag_name

# Current jq release
curl -s https://api.github.com/repos/jqlang/jq/releases/latest | jq -r .tag_name
```

When any of these move, update `versions.env`, update the table above, change
the verification date, and run `bash tests/run.sh`.
