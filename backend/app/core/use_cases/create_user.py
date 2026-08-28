from app.core.domain.exceptions import EmailAlreadyTaken
from app.core.domain.rbac import Permission
from app.core.domain.user import NewUser, User
from app.core.ports.user_repository import AbstractUserRepository
from app.core.use_cases.authorization_policy import AuthorizationPolicy


class CreateUserUseCase:
    def __init__(
        self, users: AbstractUserRepository, policy: AuthorizationPolicy
    ) -> None:
        self._users = users
        self._policy = policy

    def execute(self, *, actor: User, new_user: NewUser) -> User:
        self._policy.require(actor, Permission.USER_CREATE, resource="users")
        if self._users.get_by_email(new_user.email):
            raise EmailAlreadyTaken(new_user.email)
        return self._users.create(new_user)
