import uuid
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import col, delete, func, select

from app import crud
from app.api.deps import (
    CreateUserDep,
    CurrentActor,
    CurrentUser,
    ListUsersDep,
    SessionDep,
    UpdateOwnProfileDep,
    require,
)
from app.core.config import settings
from app.core.domain.exceptions import AccessDenied, EmailAlreadyTaken
from app.core.domain.rbac import ROLE_PERMISSIONS, Permission, Role
from app.core.domain.user import NewUser, ProfileUpdate
from app.infrastructure.mappers import to_public
from app.core.security import get_password_hash, verify_password
from app.models import (
    Item,
    Message,
    UpdatePassword,
    User,
    UserCreate,
    UserPublic,
    UserRegister,
    UsersPublic,
    UserUpdate,
    UserUpdateMe,
)
from app.utils import generate_new_account_email, send_email

router = APIRouter(prefix="/users", tags=["users"])


def _deny(_: AccessDenied) -> HTTPException:
    """AuthorizationPolicy already logged the reason; the client gets a plain
    refusal so the permission taxonomy is not echoed back."""
    return HTTPException(
        status_code=403, detail="The user doesn't have enough privileges"
    )


@router.get("/", response_model=UsersPublic)
def read_users(
    actor: CurrentActor,
    list_users: ListUsersDep,
    skip: int = 0,
    limit: int = 100,
) -> Any:
    """
    Retrieve users. Requires `user:list` (admin, manager).
    """
    try:
        users, count = list_users.execute(actor=actor, skip=skip, limit=limit)
    except AccessDenied as exc:
        raise _deny(exc)
    return UsersPublic(data=[to_public(user) for user in users], count=count)


@router.post("/", response_model=UserPublic)
def create_user(
    *, actor: CurrentActor, create: CreateUserDep, user_in: UserCreate
) -> Any:
    """
    Create new user. Requires `user:create` (admin).
    """
    try:
        user = create.execute(
            actor=actor,
            new_user=NewUser(
                email=user_in.email,
                password=user_in.password,
                role=user_in.role,
                is_active=user_in.is_active,
                full_name=user_in.full_name,
            ),
        )
    except AccessDenied as exc:
        raise _deny(exc)
    except EmailAlreadyTaken:
        raise HTTPException(
            status_code=400,
            detail="The user with this email already exists in the system.",
        )

    if settings.emails_enabled and user_in.email:
        email_data = generate_new_account_email(
            email_to=user_in.email, username=user_in.email, password=user_in.password
        )
        send_email(
            email_to=user_in.email,
            subject=email_data.subject,
            html_content=email_data.html_content,
        )
    return to_public(user)


@router.patch("/me", response_model=UserPublic)
def update_user_me(
    *, actor: CurrentActor, update_profile: UpdateOwnProfileDep, user_in: UserUpdateMe
) -> Any:
    """
    Update own user. `UserUpdateMe` has no role field, so this endpoint cannot
    be used to escalate privileges.
    """
    try:
        user = update_profile.execute(
            actor=actor,
            changes=ProfileUpdate(email=user_in.email, full_name=user_in.full_name),
        )
    except AccessDenied as exc:
        raise _deny(exc)
    except EmailAlreadyTaken:
        raise HTTPException(
            status_code=409, detail="User with this email already exists"
        )
    return to_public(user)


@router.patch("/me/password", response_model=Message)
def update_password_me(
    *, session: SessionDep, body: UpdatePassword, current_user: CurrentUser
) -> Any:
    """
    Update own password.
    """
    verified, _ = verify_password(body.current_password, current_user.hashed_password)
    if not verified:
        raise HTTPException(status_code=400, detail="Incorrect password")
    if body.current_password == body.new_password:
        raise HTTPException(
            status_code=400, detail="New password cannot be the same as the current one"
        )
    hashed_password = get_password_hash(body.new_password)
    current_user.hashed_password = hashed_password
    session.add(current_user)
    session.commit()
    return Message(message="Password updated successfully")


@router.get("/me", response_model=UserPublic)
def read_user_me(current_user: CurrentUser) -> Any:
    """
    Get current user.
    """
    return current_user


@router.delete("/me", response_model=Message)
def delete_user_me(session: SessionDep, current_user: CurrentUser) -> Any:
    """
    Delete own user.
    """
    if current_user.role == Role.ADMIN:
        raise HTTPException(
            status_code=403, detail="Admins are not allowed to delete themselves"
        )
    session.delete(current_user)
    session.commit()
    return Message(message="User deleted successfully")


@router.post("/signup", response_model=UserPublic)
def register_user(session: SessionDep, user_in: UserRegister) -> Any:
    """
    Create new user without the need to be logged in.
    """
    user = crud.get_user_by_email(session=session, email=user_in.email)
    if user:
        raise HTTPException(
            status_code=400,
            detail="The user with this email already exists in the system",
        )
    user_create = UserCreate.model_validate(user_in)
    user = crud.create_user(session=session, user_create=user_create)
    return user


@router.get("/me/permissions", response_model=list[Permission])
def read_own_permissions(actor: CurrentActor) -> Any:
    """
    The capabilities of the current user. The frontend renders from this list
    instead of hardcoding role names.
    """
    return sorted(ROLE_PERMISSIONS[actor.role])


@router.get("/{user_id}", response_model=UserPublic)
def read_user_by_id(
    user_id: uuid.UUID, session: SessionDep, current_user: CurrentUser, actor: CurrentActor
) -> Any:
    """
    Get a specific user by id. Anyone may read themselves; reading someone else
    requires `user:read_any` (admin, manager).
    """
    if user_id == current_user.id:
        return current_user
    # Authorized before the lookup, so a denied caller cannot probe which ids exist.
    if Permission.USER_READ_ANY not in ROLE_PERMISSIONS[actor.role]:
        raise HTTPException(
            status_code=403,
            detail="The user doesn't have enough privileges",
        )
    user = session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.patch(
    "/{user_id}",
    dependencies=[Depends(require(Permission.USER_UPDATE_ANY))],
    response_model=UserPublic,
)
def update_user(
    *,
    session: SessionDep,
    user_id: uuid.UUID,
    user_in: UserUpdate,
) -> Any:
    """
    Update a user.
    """

    db_user = session.get(User, user_id)
    if not db_user:
        raise HTTPException(
            status_code=404,
            detail="The user with this id does not exist in the system",
        )
    if user_in.email:
        existing_user = crud.get_user_by_email(session=session, email=user_in.email)
        if existing_user and existing_user.id != user_id:
            raise HTTPException(
                status_code=409, detail="User with this email already exists"
            )

    db_user = crud.update_user(session=session, db_user=db_user, user_in=user_in)
    return db_user


@router.delete("/{user_id}", dependencies=[Depends(require(Permission.USER_DELETE_ANY))])
def delete_user(
    session: SessionDep, current_user: CurrentUser, user_id: uuid.UUID
) -> Message:
    """
    Delete a user.
    """
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if user == current_user:
        raise HTTPException(
            status_code=403, detail="Admins are not allowed to delete themselves"
        )
    statement = delete(Item).where(col(Item.owner_id) == user_id)
    session.exec(statement)
    session.delete(user)
    session.commit()
    return Message(message="User deleted successfully")
