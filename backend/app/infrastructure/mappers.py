"""Translation between the ORM/API edge and the domain. Lives in L3 because it
is the only thing allowed to know about both sides."""

from app.core.domain.rbac import Role
from app.core.domain.user import User as UserEntity
from app.models import User as UserModel
from app.models import UserPublic


def to_entity(db_user: UserModel) -> UserEntity:
    return UserEntity(
        id=db_user.id,
        email=db_user.email,
        role=Role(db_user.role),
        is_active=db_user.is_active,
        full_name=db_user.full_name,
        created_at=db_user.created_at,
    )


def to_public(user: UserEntity) -> UserPublic:
    return UserPublic(
        id=user.id,
        email=user.email,
        role=user.role,
        is_active=user.is_active,
        # Derived, never stored as an independent truth. See crud.sync_legacy_superuser_flag.
        is_superuser=user.role == Role.ADMIN,
        full_name=user.full_name,
        created_at=user.created_at,
    )
