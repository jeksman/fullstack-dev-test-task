from app.core.domain.rbac import Permission
from app.core.domain.user import User
from app.core.ports.user_repository import AbstractUserRepository
from app.core.use_cases.authorization_policy import AuthorizationPolicy


class ListUsersUseCase:
    def __init__(
        self, users: AbstractUserRepository, policy: AuthorizationPolicy
    ) -> None:
        self._users = users
        self._policy = policy

    def execute(
        self, *, actor: User, skip: int, limit: int
    ) -> tuple[list[User], int]:
        self._policy.require(actor, Permission.USER_LIST, resource="users")
        return self._users.list(skip=skip, limit=limit)
