# Security model — design notes

The normative document is [`../SECURITY.md`](../SECURITY.md). This file records
the reasoning behind the decisions, so that a future change does not quietly
undo one of them.

## Why no temporary public SSH rule

The obvious design is: open 22 to the operator's current IP, configure the
machine, close it. It is rejected here for four reasons.

1. **The rule outlives the intent.** Closing it is a separate step, and separate
   steps get skipped when a run fails half way. A window that only closes on the
   happy path is not a window, it is a door.
2. **"The operator's IP" is not a boundary.** It is a NAT pool, a coffee shop, a
   corporate egress range shared with thousands of machines.
3. **It is observable.** Scanners see the open port during the window and record
   the host as an SSH target regardless of what happens afterwards.
4. **It makes failure handling ambiguous.** If the run dies with the rule open,
   is the deployment "in progress" or "exposed"? With no rule ever, there is
   nothing to reason about.

The tunnel costs one extra dependency and removes the entire question.

## Why the firewall is created before the server

Hetzner applies a firewall to a server asynchronously if you attach it after
creation. `hcloud server create --firewall <id>` attaches it as part of the
create request, so the machine is filtered from its first packet. Creating the
firewall first is what makes that possible.

`hetzner_server_has_firewall` then asserts `status == "applied"`, not merely
that the firewall is listed.

## Why exit code zero is not evidence

`lib/verify.sh` requires each check to state its expected outcome. The most
important check in the project is an **expected failure**: connecting to public
TCP 22 must not succeed. A step runner that only knows "the command worked"
cannot express that, and would silently pass if `nc` were missing and the
fallback returned zero.

Every check therefore has: a name, an expected outcome, a timeout, a bounded
retry policy, a recorded status, and an entry in the report.

## Why Ghost does not run as a user named `ghost`

Ghost-CLI's default `linux-user` setup stage creates a system user called
`ghost` and runs the service as it. That is one more account to reason about,
and it separates "the user that owns the files" from "the user you log in as",
which makes every maintenance command a `sudo -u` dance.

`--no-setup-linux-user` makes the systemd unit run as the owner of the install
directory, which is `ghostops`. One account, unprivileged, owns the files and
runs the process. `verify-server.sh` asserts the unit's `User=` is not root and
that no `node` process runs as root.

## Why the database password is rotated after install

See SECURITY.md, "The one exception". `ghost install` takes `--dbpass` on the
command line and there is no supported alternative. Rather than accept a
credential that has been in the process table, the installer treats the install
password as throwaway and rotates to a second generated password through 0600
files. The cost is about fifteen lines; the benefit is that the leakage scanner
stays honest.

## Why TOFU host keys are acceptable here

Pinning a host key you have never seen is normally a real weakness. It is not
here, because the first connection is not made over the internet: it is made
over an established WireGuard session to a node that the Tailscale control plane
has already authenticated and admitted to your tailnet. An attacker who could
intercept that has already compromised the tunnel, at which point host key
verification is not what is protecting you.

`StrictHostKeyChecking=yes` stays on for every subsequent connection, against a
deployment-specific `known_hosts` file rather than your personal one.

## Why outbound is unrestricted

An egress allow-list has to cover: the Ubuntu archives and their mirrors,
NodeSource, the npm registry and its CDN, `pkgs.tailscale.com`, the Tailscale
coordination and DERP servers, Let's Encrypt's ACME endpoints and OCSP
responders, NTP, DNS, and the Hetzner metadata service. Each of those is a set of
addresses that changes without notice.

A policy that breaks certificate renewal at 03:00 six weeks after deployment is
worse than no policy. This project does not ship an egress policy it has not
tested. If you want one, add it after deployment and test renewal explicitly.

## Why three separate SSH-closed checks

* A live probe can be wrong: your network may drop outbound 22, making a
  genuinely open port look closed.
* A configuration read can be wrong: the rules may be correct while the firewall
  is detached from the server.
* A single check at one moment in time says nothing about the state after Ghost
  installs, or after a reboot.

So: probe **and** read the provider configuration **and** repeat both after
installation and after the reboot. Any of them failing is a containment event.

## What a "critical" failure means

Ordinary failures stop the stage, save state, print the failed check and the
redacted log path, and tell you to `--resume`. Billable resources are kept,
because deleting a server the operator may want to debug is not a recovery.

Critical failures — an open public 22, a missing or detached firewall, password
or root SSH enabled, a secret in a world-readable file — do not stop politely.
They power the machine off, reapply the restrictive policy, and refuse to
continue. There is no flag to override this and no code path that opens SSH as a
recovery shortcut.
