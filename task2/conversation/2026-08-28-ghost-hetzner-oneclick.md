# Conversation log — ghost-hetzner-oneclick

**Date:** 2026-08-28
**Working directory:** `Fullstack-Dev-Test-Task/task2`
**Participants:** the operator and Claude (Opus 5)
**Outcome:** the complete project was built, tested and left in a usable state.

---

## 1. The request

> You are a senior DevOps, SRE, Linux security, and automation engineer.
>
> Work directly in the current repository and build a complete, production-grade
> project named:
>
> **ghost-hetzner-oneclick**
>
> Do not only describe the solution. Do not return pseudocode. Do not stop after
> creating scaffolding. Create all required files, make the scripts executable,
> run the available tests, inspect the results, fix failures, and leave the
> repository in a usable state.
>
> The final deployment must be started by the user with exactly one command:
>
> ```
> bash ./deploy.sh
> ```
>
> The user must not need to edit configuration files, manually SSH into the
> server, copy commands from the documentation, or run a second deployment
> command. The default mode must be interactive and step-by-step.

The brief then specified, in full detail:

1. **Primary objective** — create a Hetzner VPS, create and attach a Cloud
   Firewall *before* the server is reachable, never expose SSH on the public
   IPv4 or IPv6, bootstrap private access via Tailscale in cloud-init, connect
   only over the Tailscale address, install production Ghost with MySQL, Nginx,
   HTTPS, systemd, firewall rules and hardening, test every important result,
   reboot at the end and verify recovery, and print a clear final report.
2. **Non-negotiable security invariants** — (A) public SSH must never be opened,
   with immediate containment if port 22 is ever reachable; (B) SSH only through
   Tailscale with a dedicated key, no passwords, no root; (C) strict secret
   handling — never print tokens, keys or passwords, hidden prompts, no `set -x`
   near secrets, 0600 temp files, a one-time Tailscale key passed through a file
   rather than a process argument, and key destruction afterwards;
   (D) Linux hardening — the `ghostops` user, sshd drop-in, UFW default-deny,
   automatic security updates, MySQL on loopback, Ghost never as root.
3. **Two-stage architecture** — a minimal cloud-init bootstrap, then provisioning
   through the tunnel. No provisioning command may use the public IP.
4. **Supported control machines** — macOS and common Linux, bash 3.2 compatible,
   correct architecture detection, in-run dependency installation with checksum
   verification, never "exit and run again".
5. **Interactive UX** — a twelve-step wizard with `PASS/FAIL/SKIP/WARNING`,
   thirteen enumerated questions, hidden secret input, immediate validation, and
   a summary plus one final confirmation before creating billable resources.
6. **Hetzner resource management** — prefer the official CLI, query locations,
   server types, images and pricing dynamically, label everything, create in a
   specified order, never touch resources from another deployment.
7. **Firewall configuration** — the exact inbound policy, unrestricted egress,
   and independent verification of both the provider and host firewalls.
8. **Tailscale requirements** — eleven enumerated behaviours, a provider
   interface for future providers, and a precise explanation (never a public-SSH
   fallback) when a tailnet ACL blocks the connection.
9. **DNS and domain flow** — manual mode with multi-resolver polling, and a
   Cloudflare API mode with explicit confirmation before overwriting.
10. **Ghost installation** — verify the current official requirements first,
    record a version matrix with a verification date, pin critical majors, run
    non-interactively, generate the MySQL password on the VPS, keep MySQL local,
    do not fake the owner account, and be idempotent.
11. **Optional backups** — Hetzner server backups and a tested local timer.
12. **State, resume and idempotency** — `.ghost-hetzner/` layout, atomic writes,
    a lock, and the seven `deploy.sh` invocation modes.
13. **Verification after every stage** — a reusable step runner and ten named
    test groups (A–J), including the reboot-persistence group.
14. **Failure handling** — fail-closed, ordinary vs critical, containment.
15. **Resource destruction** — eleven enumerated requirements.
16. **Required repository structure.**
17. **Code quality requirements** — what to use and what never to use.
18. **Automated tests** — sixteen listed behaviours, mocks for eight commands,
    security tests that fail on eight forbidden patterns, and an opt-in live test.
19. **Documentation** — README (twenty points), SECURITY.md (eleven points), and
    an architecture doc with a Mermaid sequence diagram naming twelve actors.
20. **Final user output** — the exact report fields.
21. **Execution process** — a twenty-step procedure ending with the exact command
    `bash ./deploy.sh`.

### Mid-task addition

> also in the folder create folder called conversation, and create there file
> with all our conversation history

(This file.)

### Standing project rules already in effect

* `CLAUDE.md` — every session appends an entry to `chat-history/ГГГГ-ММ-ДД.md`.
* Global rule — fetch current documentation rather than relying on training data.
* All communication in Russian; code and identifiers in English.

---

## 2. What was done, in order

### 2.1 Inspected the repository

`task2/` was empty. The parent repository is the Clean-Architecture RBAC task
with its own `CLAUDE.md`; nothing there was modified.

Local tooling audit: `curl`, `jq`, `ssh`, `scp`, `ssh-keygen`, `dig`, `openssl`,
`nc`, `shellcheck` present. **`hcloud` and `tailscale` missing** — which is
exactly the case `lib/tools.sh` has to handle. **Bash 3.2.57** — so bash 3.2
compatibility was a hard constraint, not a nicety.

### 2.2 Verified the version matrix against official documentation

| Question | Source consulted | Answer |
|---|---|---|
| Supported Ubuntu | `docs.ghost.org/install/ubuntu/` | 22.04, 24.04, 26.04 → chose **24.04 LTS** |
| Required Node | `docs.ghost.org/faq/node-versions/` | Ghost ≥ 6.0.0 requires `^22.13.1`; 20 and 24 unsupported |
| MySQL | `docs.ghost.org/install/ubuntu/` | 8.0 or 8.4 → **8.0** (in Ubuntu 24.04 `main`) |
| Nginx | same | ≥ 1.9.5 for SSL |
| `ghost install` flags | `docs.ghost.org/ghost-cli/` | `--db --dbhost --dbuser --dbpass --dbname --url --process --no-prompt --no-setup-* --sslemail --start --enable --dir` |
| hcloud CLI | GitHub releases API | v1.67.0, with `checksums.txt` |
| jq | GitHub releases API | 1.8.2, with `sha256sum.txt` |
| `--auth-key=file:` | `tailscale/tailscale` `cmd/tailscale/cli/up.go` | Confirmed in source: *"if it begins with `file:`, then it's a path to a file containing the authkey"* |
| Tailscale stable | `pkgs.tailscale.com/stable/?mode=json` | 1.102.3 |

Recorded in `docs/version-matrix.md` with the verification date.

### 2.3 Built the project

Written in dependency order: `redact` → `common` → `ui` → `state` → `tools` →
`hetzner` → `tailscale` → `dns` → `ssh` → `verify` → templates → remote scripts
→ `deploy.sh` → tests → docs.

---

## 3. Decisions worth recording

### Public SSH: no window at all

The firewall is created first and passed to `hcloud server create --firewall`,
so it is attached as part of the create request rather than asynchronously
afterwards. The machine has no unfiltered moment. Three independent enforcement
points: the renderer refuses to emit a policy containing inbound TCP 22 or an
open-ended TCP range; the rules are read back from Hetzner and compared to the
intended policy; a live probe of public 22 must fail — after creation, after
installation, and again after the reboot.

### The public-IP fallback is made structurally impossible

`rssh` and `rscp` call `ssh_assert_private_target` before doing anything. It
refuses an empty target, a hostname, an arbitrary public address, and explicitly
the server's own recorded public IPv4 and IPv6. Only `100.64.0.0/10` passes. A
test asserts that a public target produces **no ssh process at all**, not merely
a failed one.

### Secrets never become process arguments

* Tailscale: `tailscale up --auth-key="file:/run/gho-authkey"`.
* cloud-init rendering uses bash parameter substitution, so the key never
  reaches `sed`'s argv; the output file is created 0600.
* The redactor writes its `sed` program to a 0600 file instead of passing the
  secret on a command line.
* Cloudflare: `curl --config <0600 file>` carrying the `Authorization` header.
* MySQL: statements come from 0600 SQL files; `mysqldump` uses
  `--defaults-extra-file`.
* The bootstrap's cloud-init redaction uses a generated `sed` script file, not
  `python3 argv` (an earlier draft did the latter and was rewritten).

**The one unavoidable exception** is `ghost install --dbpass`, which Ghost-CLI
offers no alternative to. Resolved by installing with a throwaway generated
password and then rotating the account to a second generated password through a
0600 SQL file plus a `jq` patch of `config.production.json`. The credential Ghost
keeps on disk has never been in the process table.

### Ghost does not run as a user named `ghost`

`--no-setup-linux-user` makes the systemd unit run as the owner of the install
directory — `ghostops`. One unprivileged account owns the files and runs the
process. `verify-server.sh` asserts the unit's `User=` is not root and that no
`node` process runs as root.

### Stage 08 installs Ghost without TLS; stage 09 does DNS then HTTPS

Certificate issuance cannot happen before DNS points at the machine, so
`ghost install` runs with `--no-setup-nginx --no-setup-ssl`, and
`remote/configure-https.sh` runs `ghost setup nginx` then `ghost setup ssl` once
all three public resolvers agree. This is why there are five remote scripts
rather than the four the brief listed — the split is by responsibility and by
when the step can legally run.

### `preflight`, `credentials` and `settings` always re-run

They populate the session: tool paths, the API token, the resolved
configuration. Skipping them on `--resume` would leave later stages without
their inputs. They ask nothing new and do not re-ask for billing confirmation.
Only `firewall` through `report` are skippable.

### Egress is deliberately unrestricted

An allow-list would have to cover Ubuntu mirrors, NodeSource, npm and its CDN,
`pkgs.tailscale.com`, DERP relays, Let's Encrypt and OCSP, NTP, DNS and the
Hetzner metadata service. A policy that breaks certificate renewal six weeks
later is worse than none, and the brief said not to ship an untested one.

### cloud-init's irreducible limitation is documented, not hidden

The auth key must travel in user-data, and Hetzner's metadata service keeps
serving that user-data to the instance for its lifetime. The bootstrap shreds
every copy it can reach and redacts the on-disk cloud-init files, but it cannot
scrub the provider's metadata endpoint. This is precisely why the key must be
one-time, ephemeral and pre-approved — stated in SECURITY.md and warned about at
the credentials stage.

---

## 4. Bugs found by the tests, and fixed

These were real defects in code already written, caught by running the suite —
not hypotheticals.

1. **`\|` alternation in BSD sed** (`lib/redact.sh`). The environment-assignment
   redaction rule used a GNU extension. On macOS it silently matched nothing, so
   `HCLOUD_TOKEN=…` would have appeared unredacted in logs. Replaced with one
   rule per variable name.
2. **jq operator precedence in node discovery** (`lib/tailscale.sh`).
   `select(.HostName == $h or (.DNSName // "") | startswith(…))` parses as
   `select((… or …) | startswith(…))` and threw
   `startswith() requires string inputs`. Tailscale node discovery would have
   failed on every deployment. Fixed with explicit parentheses.
3. **`A && B` at statement level under `set -e`** (three sites in
   `remote/install-ghost.sh` and `remote/configure-security.sh`). The MySQL
   loopback check, the ufw SSH-rule check and the world-readable-config check
   each returned non-zero when they found nothing wrong, killing the script on
   success. Rewritten as explicit `if` blocks.
4. **The Hetzner token leaked into argv** (`deploy.sh`). A `wait_until … sh -c`
   helper interpolated `HCLOUD_TOKEN='…'` into a command string. Removed; the
   existing retrying `verify` covers the same wait.
5. **`stage_mark` before the state file existed.** `stage_preflight` marked
   itself done before `stage_settings` had created `state.json`; the first
   dry-run died on the first stage. Led to the "session-setup stages always run"
   design above, plus `state_exists` guards.
6. **`verify_warn` printed FAIL and WARNING for the same check.** Replaced the
   stderr-suppression hack with a `GHO_VERIFY_SOFT` flag inside `verify`.
7. **`rscp`'s `${!#}` last-argument indirection** was fragile; simplified to an
   explicit two-argument signature.
8. **Deployment names of two characters were rejected** while the test expected
   them to pass. The three-character minimum is correct; the test was corrected
   and an explicit "too short is rejected" case added.
9. **The TLS issuer check was too loose** — `E[0-9]` matched any CA whose CN
   happened to be `E5`. Narrowed to `Let's Encrypt|ISRG`, with the chain itself
   still validated by curl against the system trust store.
10. **The cloud-init header comment was itself being substituted**, so the
    rendered file's comment contained the real values. Reworded to prose.

Mock bugs found and fixed along the way: `nc` argument parsing consumed `-w N`
incorrectly; several test env vars were not exported to the mock subprocesses.

---

## 5. Tests actually executed

Everything below was run in this session on macOS with bash 3.2.57. No live
Hetzner credentials were available and no live deployment was authorised, so all
external commands are mocked. This is stated in the README and in the final
summary.

```
bash tests/run.sh
```

| File | Assertions |
|---|---|
| `tests/unit/01-validation.sh` | 61 |
| `tests/unit/02-redaction.sh` | 16 |
| `tests/unit/03-state.sh` | 25 |
| `tests/unit/04-firewall-render.sh` | 20 |
| `tests/unit/05-cloud-init-render.sh` | 33 |
| `tests/unit/06-tailscale-discovery.sh` | 23 |
| `tests/unit/07-hetzner-discovery.sh` | 25 |
| `tests/unit/08-dns.sh` | 15 |
| `tests/unit/09-port-and-https-checks.sh` | 24 |
| `tests/unit/10-destroy-safeguards.sh` | 16 |
| `tests/unit/11-containment.sh` | 16 |
| `tests/unit/12-report.sh` | 38 |
| `tests/unit/13-embedded-scripts.sh` | 17 |
| `tests/security/01-repo-invariants.sh` | 49 |
| **Total** | **378, 0 failed** |

Plus, in the same run:

* **ShellCheck** — clean. Production code checked strictly (`-e SC1091` only);
  test and mock code additionally excludes the cross-file-visibility noise
  (`SC2034`, `SC2016`, `SC2012`), which is documented in `tests/run.sh`.
* **shfmt** — `shfmt -d -ln bash -i 0` reports no differences. `shfmt` was
  downloaded into `.tools/bin` so that this check could genuinely run rather
  than be reported as skipped.

Additional end-to-end exercises against the mocks:

* `bash ./deploy.sh --dry-run --non-interactive` — all twelve stages executed,
  firewall policy rendered and asserted SSH-free, cloud-init rendered with every
  placeholder substituted at mode 0600. The redacted dry-run preview was
  inspected: **zero occurrences of the auth key**, `__TS_AUTHKEY_REDACTED__`
  present. `state.json` inspected: **zero credential material**.
* `bash ./deploy.sh --status` — full stage and resource listing.
* `bash ./deploy.sh --resume` with earlier stages marked done — skipped them
  correctly and produced the complete final report, including the private SSH
  command built from the tailnet name.
* `bash ./deploy.sh --destroy` — correctly **refused** to delete resources whose
  `deployment-id` label did not match the running deployment, proving the
  safeguard in the real flow rather than only in a unit test.

**Not tested:** a live Hetzner deployment. No credentials were provided and no
live run was authorised. `tests/live/01-live-deploy.sh` exists, is double-gated
behind `RUN_LIVE_TESTS=1` and
`LIVE_TEST_CONFIRM=I-ACCEPT-HETZNER-CHARGES`, and was **not** executed.

---

## 6. Final state

```
task2/
├── deploy.sh                 1400+ lines, twelve stages, seven modes
├── versions.env              the pinned matrix
├── README.md  SECURITY.md  CHANGELOG.md  LICENSE  .gitignore
├── lib/        redact ui common state tools hetzner tailscale dns ssh verify
├── templates/  cloud-init.yaml  hetzner-firewall.json
├── remote/     install-ghost  configure-security  configure-https
│               configure-backups  verify-server
├── tests/      run.sh lib.sh unit/(13) security/(1) live/(1) mocks/(8 + fixtures)
├── docs/       architecture  security-model  version-matrix  troubleshooting
└── conversation/  this file
```

All scripts executable, all syntactically valid, ShellCheck and shfmt clean, the
full non-live suite green.

The deployment is started with exactly one command:

```
bash ./deploy.sh
```
