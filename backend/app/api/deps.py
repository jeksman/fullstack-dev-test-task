from collections.abc import Callable, Generator
from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from jwt.exceptions import InvalidTokenError
from pydantic import ValidationError
from sqlmodel import Session

from app.core import security
from app.core.config import settings
from app.core.db import engine
from app.core.domain.exceptions import AccessDenied
from app.core.domain.rbac import Permission
from app.core.domain.user import User as UserEntity
from app.core.ports.user_repository import AbstractUserRepository
from app.core.use_cases.authorization_policy import AuthorizationPolicy
from app.core.use_cases.create_user import CreateUserUseCase
from app.core.use_cases.list_users import ListUsersUseCase
from app.core.use_cases.update_own_profile import UpdateOwnProfileUseCase
from app.infrastructure.mappers import to_entity
from app.infrastructure.repositories.sqlmodel_user_repository import (
    SQLModelUserRepository,
)
from app.models import TokenPayload, User

reusable_oauth2 = OAuth2PasswordBearer(
    tokenUrl=f"{settings.API_V1_STR}/login/access-token"
)


def get_db() -> Generator[Session]:
    with Session(engine) as session:
        yield session


SessionDep = Annotated[Session, Depends(get_db)]
TokenDep = Annotated[str, Depends(reusable_oauth2)]


def get_current_user(session: SessionDep, token: TokenDep) -> User:
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[security.ALGORITHM]
        )
        token_data = TokenPayload(**payload)
    except InvalidTokenError, ValidationError:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Could not validate credentials",
        )
    user = session.get(User, token_data.sub)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if not user.is_active:
        raise HTTPException(status_code=400, detail="Inactive user")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def get_current_actor(current_user: CurrentUser) -> UserEntity:
    """The authenticated user as the core sees them — a role, not an ORM row."""
    return to_entity(current_user)


CurrentActor = Annotated[UserEntity, Depends(get_current_actor)]


def get_policy() -> AuthorizationPolicy:
    return AuthorizationPolicy()


PolicyDep = Annotated[AuthorizationPolicy, Depends(get_policy)]


def get_user_repository(session: SessionDep) -> AbstractUserRepository:
    return SQLModelUserRepository(session)


UserRepositoryDep = Annotated[AbstractUserRepository, Depends(get_user_repository)]


def require(permission: Permission) -> Callable[..., UserEntity]:
    """Build a route dependency that admits only roles holding `permission`.

    This is the only gate used across the API, so every protected endpoint reads
    the same way and a new role never requires touching a route.
    """

    def dependency(
        request: Request, actor: CurrentActor, policy: PolicyDep
    ) -> UserEntity:
        try:
            policy.require(actor, permission, resource=request.url.path)
        except AccessDenied:
            raise HTTPException(
                status_code=403, detail="The user doesn't have enough privileges"
            )
        return actor

    return dependency


def get_list_users_use_case(
    users: UserRepositoryDep, policy: PolicyDep
) -> ListUsersUseCase:
    return ListUsersUseCase(users, policy)


def get_create_user_use_case(
    users: UserRepositoryDep, policy: PolicyDep
) -> CreateUserUseCase:
    return CreateUserUseCase(users, policy)


def get_update_own_profile_use_case(
    users: UserRepositoryDep, policy: PolicyDep
) -> UpdateOwnProfileUseCase:
    return UpdateOwnProfileUseCase(users, policy)


ListUsersDep = Annotated[ListUsersUseCase, Depends(get_list_users_use_case)]
CreateUserDep = Annotated[CreateUserUseCase, Depends(get_create_user_use_case)]
UpdateOwnProfileDep = Annotated[
    UpdateOwnProfileUseCase, Depends(get_update_own_profile_use_case)
]
