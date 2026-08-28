from app.core.domain.exceptions import EmailAlreadyTaken
from app.core.domain.rbac import Permission
from app.core.domain.user import ProfileUpdate, User
from app.core.ports.user_repository import AbstractUserRepository
from app.core.use_cases.authorization_policy import AuthorizationPolicy


class UpdateOwnProfileUseCase:
    def __init__(
        self, users: AbstractUserRepository, policy: AuthorizationPolicy
    ) -> None:
        self._users = users
        self._policy = policy

    def execute(self, *, actor: User, changes: ProfileUpdate) -> User:
        self._policy.require(
            actor, Permission.PROFILE_UPDATE_OWN, resource=f"users/{actor.id}"
        )
        # ProfileUpdate carries no `role` field, so this path cannot escalate
        # privileges regardless of what the client sends.
        if changes.email:
            owner = self._users.get_by_email(changes.email)
            if owner and owner.id != actor.id:
                raise EmailAlreadyTaken(changes.email)
        return self._users.update_profile(actor.id, changes)
