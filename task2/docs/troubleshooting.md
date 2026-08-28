# Troubleshooting

Start with:

```bash
bash ./deploy.sh --status
ls -t .ghost-hetzner/logs/ | head -3
```

Logs are redacted, mode 0600. Everything below assumes public SSH stays closed —
opening it is never the fix.

---

## The node never appears on the tailnet

```
FAIL  the node never appeared on the tailnet
```

Stage 6 waited ten minutes and `tailscale status --json` never listed
`gho-<name>`. Almost always the auth key.

| Cause | Check | Fix |
|---|---|---|
| Key already used | Tailscale admin → Keys. A one-time key is spent after one node. | Create a fresh one-time key, `bash ./deploy.sh --resume`. |
| Key not pre-approved | Tailnet has device approval on, and the node is sitting in "Awaiting approval". | Approve it, or reissue the key as pre-approved. |
| Key expired | Keys have an expiry; a slow first boot can outlast a very short one. | Reissue with an hour's expiry. |
| cloud-init still running | The server may still be installing packages. | Wait, then `--resume`. Hetzner console → the server's console shows cloud-init output. |
| Egress blocked | Rare on Hetzner; only if you added an outbound firewall policy. | Remove it. |

You have no SSH yet at this point. The Hetzner web console (VNC) is the only way
in, and that is by design.

---

## The node is on the tailnet but SSH is refused

```
FAIL  ssh-host-key-pinned   /   FAIL  private-ssh-login
      The node is on the tailnet but TCP 22 is not reachable from this machine.
```

This is a tailnet **access policy** problem, not a server problem. Your default
ACL does not let your user reach port 22 on the new node.

In the Tailscale admin console, add something like:

```json
{"action": "accept", "src": ["autogroup:member"], "dst": ["gho-ghost-blog:22"]}
```

Then `bash ./deploy.sh --resume`.

Verify the path independently:

```bash
tailscale ping gho-ghost-blog
tailscale status | grep gho-
```

---

## `this machine is not connected to a tailnet`

```bash
tailscale up          # Linux
open -a Tailscale     # macOS, then sign in
tailscale status
```

The control machine must be on the same tailnet as the server. There is no
other route in.

---

## Tailscale CLI not found

macOS: install the app from <https://tailscale.com/download/mac>. The CLI lives
at `/Applications/Tailscale.app/Contents/MacOS/Tailscale`, which `deploy.sh`
already looks for. If yours is elsewhere:

```bash
TAILSCALE_CLI=/path/to/tailscale bash ./deploy.sh
```

Linux: `curl -fsSL https://tailscale.com/install.sh | sh`

---

## DNS never resolves

```
WARNING  DNS did not resolve within 15 minutes
```

`deploy.sh` polls 1.1.1.1, 8.8.8.8 and 9.9.9.9 and requires **all three** to
return the new address. Partial propagation would make Let's Encrypt fail, so
it is not accepted.

```bash
dig +short A blog.example.com @1.1.1.1
dig +short A blog.example.com @8.8.8.8
dig +short A blog.example.com @9.9.9.9
```

* Records on the wrong name — `blog` vs `blog.example.com` in your provider's UI.
* An old high-TTL record still cached. Wait it out; lower the TTL for next time.
* Cloudflare proxying already on. Turn the orange cloud **off** until the
  certificate is issued; `http-01` validation must reach your origin.

The prompt keeps offering to wait. You do not need to restart the deployment.

---

## Certificate issuance fails

```
FAIL  nginx or certificate configuration failed
```

```bash
ssh ghostops@<tailnet-name> 'sudo journalctl -u nginx -n 50 --no-pager'
ssh ghostops@<tailnet-name> 'ls -la /var/www/ghost/system/nginx-root/.well-known/acme-challenge/ 2>/dev/null'
curl -I http://blog.example.com/.well-known/acme-challenge/test
```

* Port 80 must be reachable from the internet. `nc -vz <public-ip> 80`.
* DNS must already point here — the deployment enforces this, but a record
  changed mid-run will break it.
* Let's Encrypt rate limits: 5 duplicate certificates per week. If you have been
  iterating, wait or use a different subdomain.

---

## Ghost will not start

```bash
ssh ghostops@<tailnet-name>
cd /var/www/ghost
ghost status
ghost log --error
ghost doctor
sudo systemctl status 'ghost_*'
```

Most common causes:

* **Out of memory during install.** `free -h`. The installer creates a 2 GB swap
  file below ~3.7 GB RAM; if you picked a 2 GB server and disabled swap, Node's
  install can be OOM-killed. Use a 4 GB type.
* **Database connection refused.** `sudo systemctl status mysql`, then
  `sudo mysql -e "SELECT 1"`.
* **Wrong Node version.** `node -v` must be `v22.x`. Ghost 6 refuses anything else.

---

## `ghost install` fails with "directory is not empty"

An earlier run died between creating `/var/www/ghost` and writing
`config.production.json`. The installer clears the directory automatically, but
only when it can prove there is nothing to lose (no Ghost tables in the database
and no `content/images`). Otherwise it stops and says so — deliberately, because
the alternative is deleting someone's posts.

Inspect it, take a backup, then remove the directory contents yourself and
`--resume`.

---

## The deployment stopped with a critical security failure

```
FAIL  CRITICAL SECURITY FAILURE: ...
```

The server has been powered off and the restrictive firewall policy reapplied.
Do not restart it and do not resume until you understand why.

```bash
hcloud firewall describe gho-<name>-fw -o json | jq '.rules'
hcloud server describe gho-<name> -o json | jq '.public_net.firewalls'
```

Then read `.ghost-hetzner/reports/final-report.json` for the failing check.

---

## Another deployment holds the lock

```
another deployment holds the lock
```

A previous run was killed. If no `deploy.sh` is running:

```bash
cat .ghost-hetzner/lock/pid
ps -p "$(cat .ghost-hetzner/lock/pid)"    # no output means it is gone
rm -rf .ghost-hetzner/lock
```

A lock whose owner is gone is reclaimed automatically on the next run.

---

## Resuming after any failure

```bash
bash ./deploy.sh --resume
```

Completed stages are skipped. `preflight`, `credentials` and `settings` always
re-run — they populate the session and ask nothing new. You will be asked for
the Hetzner token and Tailscale key again unless they are in the environment;
nothing stores them.

If the Tailscale key was spent by the failed attempt, create a new one first.

---

## Removing everything

```bash
bash ./deploy.sh --destroy
```

Lists exactly what will be deleted, refuses anything not carrying this
deployment's id, and requires you to type the deployment name. Logs and reports
are kept unless you ask for them to go too.

The DNS records and the Tailscale node entry are yours to remove.
