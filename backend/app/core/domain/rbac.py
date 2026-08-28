"""The authorization model: roles, permissions, and the mapping between them.

This module is the single source of truth for "who may do what". Adding a role
means adding one entry to ROLE_PERMISSIONS and nothing else.
"""

from enum import StrEnum


class Role(StrEnum):
    ADMIN = "admin"
    MANAGER = "manager"
    MEMBER = "member"


class Permission(StrEnum):
    USER_LIST = "user:list"
    USER_CREATE = "user:create"
    USER_READ_ANY = "user:read_any"
    USER_UPDATE_ANY = "user:update_any"
    USER_DELETE_ANY = "user:delete_any"
    METRICS_VIEW = "metrics:view"
    SETTINGS_MANAGE = "settings:manage"
    ITEM_MANAGE_ANY = "item:manage_any"
    PROFILE_UPDATE_OWN = "profile:update_own"


# Every role can manage its own profile; the rest is granted explicitly.
ROLE_PERMISSIONS: dict[Role, frozenset[Permission]] = {
    Role.ADMIN: frozenset(Permission),
    Role.MANAGER: frozenset(
        {
            Permission.USER_LIST,
            Permission.USER_READ_ANY,
            Permission.METRICS_VIEW,
            Permission.PROFILE_UPDATE_OWN,
        }
    ),
    Role.MEMBER: frozenset({Permission.PROFILE_UPDATE_OWN}),
}
