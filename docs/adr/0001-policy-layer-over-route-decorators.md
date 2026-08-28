# ADR 0001: A permission policy layer, not role checks on routes

**Status:** accepted · **Date:** 2026-08-28

## Problem

The template ships one authorization primitive: a boolean `is_superuser` flag
checked by the `get_current_active_superuser` dependency, plus ad-hoc
`if current_user.is_superuser` branches inside `items.py` and `users.py`. We
need three roles with different capabilities, enforced consistently, and the
brief asks that adding a role not require touching ten files.

## Options

**A. Role checks at the routes.** Replace `get_current_active_superuser` with
`require_role(Role.ADMIN, Role.MANAGER)`. Smallest diff. But the capability
model then lives scattered across route decorators: to answer "what can a
manager do?" you grep the whole API, and adding a role means revisiting every
decorator that should now include it. The frontend has no way to ask what it
may do, so it ends up with a duplicated role table in TypeScript that silently
drifts.

**B. A permission layer between roles and endpoints.** Endpoints require
*permissions*; a single `ROLE_PERMISSIONS` map assigns permissions to roles.
One more indirection, and a couple of extra names to learn.

**C. Full policy engine** (Casbin, OSO, row-level ABAC). Handles
resource-scoped and attribute-based rules we do not have. A dependency, a
policy DSL, and a second place for logic to hide, for a three-role problem.

## Decision

Option B. `ROLE_PERMISSIONS` in `core/domain/rbac.py` is the entire model and
fits on one screen; `AuthorizationPolicy.require()` is the only thing that
decides anything. Routes name the capability they need
(`require(Permission.USER_CREATE)`), never the roles that happen to have it, so
adding a role is one line in the map and changing who may create users is one
edit in one file.

The indirection pays for itself twice over. It makes `GET /users/me/permissions`
trivial — the frontend renders from the caller's actual permission list instead
of a hardcoded role table, which is what keeps the two sides from drifting. And
it gives denials one chokepoint to log from, satisfying the observability
requirement without an audit call at every call site.

## Trade-offs

- Two concepts (roles, permissions) where the brief only demanded one. Justified
  by the frontend contract; not justified for a system that will only ever have
  `admin`/`not admin`.
- `is_superuser` still exists, now derived from `role`. Carrying a mirror is a
  liability — the two could diverge if something writes the column directly.
  Mitigated by keeping the derivation in one function (`sync_legacy_superuser_flag`)
  and never reading the flag for a decision; the honest fix is dropping the
  column once no client reads it.
- Permissions are coarse and global. Anything resource-scoped ("managers may
  edit users in their own team") needs the policy to take the resource as an
  argument, which is a real change, not a config tweak. Option C becomes the
  right answer at that point.
