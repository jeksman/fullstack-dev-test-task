"""Unit tests for the authorization model. No database, no HTTP, no Docker."""

import uuid
from unittest.mock import Mock

import pytest

from app.core.domain.exceptions import AccessDenied, EmailAlreadyTaken
from app.core.domain.rbac import ROLE_PERMISSIONS, Permission, Role
from app.core.domain.user import NewUser, ProfileUpdate, User
from app.core.ports.user_repository import AbstractUserRepository
from app.core.use_cases.authorization_policy import AuthorizationPolicy
from app.core.use_cases.create_user import CreateUserUseCase
from app.core.use_cases.list_users import ListUsersUseCase
from app.core.use_cases.update_own_profile import UpdateOwnProfileUseCase


def actor(role: Role) -> User:
    return User(
        id=uuid.uuid4(), email=f"{role}@example.com", role=role, is_active=True
    )


# The documented permission matrix, restated as a test so the README and the
# code cannot drift apart silently.
@pytest.mark.parametrize(
    ("role", "permission", "granted"),
    [
        (Role.ADMIN, Permission.USER_LIST, True),
        (Role.ADMIN, Permission.USER_CREATE, True),
        (Role.ADMIN, Permission.USER_UPDATE_ANY, True),
        (Role.ADMIN, Permission.SETTINGS_MANAGE, True),
        (Role.MANAGER, Permission.USER_LIST, True),
        (Role.MANAGER, Permission.METRICS_VIEW, True),
        (Role.MANAGER, Permission.USER_CREATE, False),
        (Role.MANAGER, Permission.USER_UPDATE_ANY, False),
        (Role.MANAGER, Permission.SETTINGS_MANAGE, False),
        (Role.MEMBER, Permission.PROFILE_UPDATE_OWN, True),
        (Role.MEMBER, Permission.USER_LIST, False),
        (Role.MEMBER, Permission.METRICS_VIEW, False),
    ],
)
def test_policy_matches_documented_matrix(
    role: Role, permission: Permission, granted: bool
) -> None:
    assert AuthorizationPolicy().grants(role, permission) is granted


def test_every_role_can_manage_its_own_profile() -> None:
    for role in Role:
        assert Permission.PROFILE_UPDATE_OWN in ROLE_PERMISSIONS[role]


def test_every_role_is_covered_by_the_matrix() -> None:
    assert set(ROLE_PERMISSIONS) == set(Role)


def test_list_users_denies_member_before_touching_the_repository() -> None:
    users = Mock(spec=AbstractUserRepository)
    use_case = ListUsersUseCase(users, AuthorizationPolicy())

    with pytest.raises(AccessDenied):
        use_case.execute(actor=actor(Role.MEMBER), skip=0, limit=100)

    users.list.assert_not_called()


def test_list_users_allows_manager() -> None:
    users = Mock(spec=AbstractUserRepository)
    users.list.return_value = ([], 0)

    result = ListUsersUseCase(users, AuthorizationPolicy()).execute(
        actor=actor(Role.MANAGER), skip=0, limit=100
    )

    assert result == ([], 0)
    users.list.assert_called_once_with(skip=0, limit=100)


def test_create_user_denies_manager_before_any_write() -> None:
    users = Mock(spec=AbstractUserRepository)
    use_case = CreateUserUseCase(users, AuthorizationPolicy())

    with pytest.raises(AccessDenied):
        use_case.execute(
            actor=actor(Role.MANAGER),
            new_user=NewUser(email="new@example.com", password="password123"),
        )

    users.create.assert_not_called()


def test_create_user_rejects_duplicate_email() -> None:
    users = Mock(spec=AbstractUserRepository)
    users.get_by_email.return_value = actor(Role.MEMBER)

    with pytest.raises(EmailAlreadyTaken):
        CreateUserUseCase(users, AuthorizationPolicy()).execute(
            actor=actor(Role.ADMIN),
            new_user=NewUser(email="taken@example.com", password="password123"),
        )

    users.create.assert_not_called()


def test_own_profile_update_cannot_carry_a_role() -> None:
    """Privilege escalation via self-update is closed by the type itself."""
    assert not hasattr(ProfileUpdate(), "role")

    users = Mock(spec=AbstractUserRepository)
    users.get_by_email.return_value = None
    member = actor(Role.MEMBER)

    UpdateOwnProfileUseCase(users, AuthorizationPolicy()).execute(
        actor=member, changes=ProfileUpdate(full_name="Renamed")
    )

    users.update_profile.assert_called_once_with(
        member.id, ProfileUpdate(full_name="Renamed")
    )


def test_denial_is_logged_with_who_what_and_which_resource(
    caplog: pytest.LogCaptureFixture,
) -> None:
    member = actor(Role.MEMBER)
    policy = AuthorizationPolicy()

    with caplog.at_level("WARNING"), pytest.raises(AccessDenied):
        policy.require(member, Permission.USER_LIST, resource="/users/")

    assert len(caplog.records) == 1
    logged = caplog.records[0].getMessage()
    assert str(member.id) in logged
    assert Permission.USER_LIST in logged
    assert "/users/" in logged


def test_allowed_request_is_not_logged(caplog: pytest.LogCaptureFixture) -> None:
    with caplog.at_level("WARNING"):
        AuthorizationPolicy().require(actor(Role.ADMIN), Permission.USER_LIST)

    assert caplog.records == []
