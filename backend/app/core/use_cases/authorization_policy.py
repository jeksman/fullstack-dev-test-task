"""The one place that answers "may this user do this?"."""

import logging

from app.core.domain.exceptions import AccessDenied
from app.core.domain.rbac import ROLE_PERMISSIONS, Permission, Role
from app.core.domain.user import User

logger = logging.getLogger(__name__)


class AuthorizationPolicy:
    """A pure function of (Role, Permission), plus an audit trail for denials."""

    def grants(self, role: Role, permission: Permission) -> bool:
        return permission in ROLE_PERMISSIONS[role]

    def require(
        self, user: User, permission: Permission, *, resource: str | None = None
    ) -> None:
        """Raise AccessDenied unless the user's role grants the permission.

        Called before any side effect and before reading sensitive data, so a
        denial never leaks the existence or contents of the target resource.
        """
        if self.grants(user.role, permission):
            return
        logger.warning(
            "access denied: user=%s role=%s permission=%s resource=%s",
            user.id,
            user.role,
            permission,
            resource or "-",
        )
        raise AccessDenied(f"Role '{user.role}' lacks permission '{permission}'")

    def permissions_of(self, role: Role) -> frozenset[Permission]:
        return ROLE_PERMISSIONS[role]
