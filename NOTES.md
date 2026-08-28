# Notes

## What I cut, and why

- **Second ADR.** One decision actually had competing options worth writing up
  (permission layer vs. role checks vs. policy engine). The rest — the `role`
  column, the mapper on the L3 boundary — followed from the repository's
  existing architecture guidelines rather than from a choice I made.
- **Broad Playwright coverage.** `frontend/tests/rbac.spec.ts` covers the three
  role journeys that the README makes claims about (hidden nav, Access denied on
  a direct URL, no Add User for a manager) and nothing else. The rest of the UI
  is already covered by the template's own suite.
- **Renaming the `/admin` route** to something role-neutral like `/users`. It
  churns `routeTree.gen.ts` and every link for no functional gain.
- **Resource-scoped permissions** ("a manager may edit users on their own
  team"). Nothing in the brief needs them, and the policy signature would have
  to change to take a resource. Noted as the upgrade path in the ADR.

## Trade-offs worth flagging

- **`is_superuser` is now derived, not authoritative.** It stays in the schema
  because migrations and existing API clients reference it, and
  `crud.sync_legacy_superuser_flag` keeps it equal to `role == admin`. Nothing
  reads it to make a decision — `rg is_superuser backend/app` returns four hits:
  the column in `models.py`, the mirror in `crud.py`, and the derivation in
  `mappers.py` that fills the field on the public DTO. No branch anywhere reads
  it. Four upstream tests asserted the old source of
  truth (creating a user with `is_superuser=True` and expecting privileges);
  they now set `role=Role.ADMIN`. That is a deliberate behavioural change, not
  a test papering over a regression.
- **403 responses say "The user doesn't have enough privileges" and nothing
  more.** The specifics — user id, permission, resource — go to a warning-level
  audit log instead. Echoing the permission name back would tell an attacker
  the shape of the internal taxonomy for no user benefit; the UI shows a
  friendly Access denied page regardless.
- **The `role` column is `VARCHAR(20)`, not a Postgres `ENUM`.** A native enum
  would give database-level validation, but adding a role would then need a
  migration — which contradicts the "one line in `ROLE_PERMISSIONS`" goal.
  Validation happens at the API boundary via the `Role` enum.
- **Metrics are three `COUNT(*)` queries** computed in the route, with no
  repository port behind them. Inventing a port for a stub would be abstraction
  without a second implementation to justify it.
- **`GET /users/{id}` checks the permission inline** rather than through a
  `require(...)` dependency, because "self or `user:read_any`" is a two-branch
  rule that a single dependency cannot express. The check still runs before the
  database lookup, so a denied caller cannot probe which ids exist.

## With more time

- Drop `is_superuser` once no client depends on it, and delete the mirror.
- Move the remaining owner-scope checks in `items.py` behind the policy, so
  `AuthorizationPolicy` takes an optional resource and every access decision —
  not just the role-based ones — goes through one chokepoint.
- Structured (JSON) audit logs with a request id, so denials are queryable
  rather than greppable.

## Verification performed

- `uv run pytest` — 111 passed (109 template + new RBAC, architecture, and
  audit-log tests).
- `bun run lint` and `bun run --filter frontend build` — clean, including
  `tsc` typecheck.
- `alembic upgrade head` on an empty database, then `python -m app.seed_data`.
- `docker compose up -d --build` plus `python -m app.seed_data`, then live HTTP
  checks against the running stack as all three roles: the observed status
  matrix matches the documented one exactly, self-escalation via
  `PATCH /users/me` leaves the role unchanged, and each denial appears in the
  audit log.
- `bunx playwright test tests/rbac.spec.ts` — 3 passed against that stack.

One thing worth naming: my first pass at the Playwright test asserted only the
*absence* of the Add User button for a manager. It passed against a page that
had not rendered at all. Each role test now asserts something present before
asserting something absent.
