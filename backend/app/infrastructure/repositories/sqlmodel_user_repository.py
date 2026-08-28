import uuid

from sqlmodel import Session, col, func, select

from app import crud
from app.core.domain.exceptions import UserNotFound
from app.core.domain.user import NewUser, ProfileUpdate
from app.core.domain.user import User as UserEntity
from app.core.ports.user_repository import AbstractUserRepository
from app.infrastructure.mappers import to_entity
from app.models import User as UserModel
from app.models import UserCreate


class SQLModelUserRepository(AbstractUserRepository):
    def __init__(self, session: Session) -> None:
        self._session = session

    def list(self, *, skip: int, limit: int) -> tuple[list[UserEntity], int]:
        count = self._session.exec(select(func.count()).select_from(UserModel)).one()
        statement = (
            select(UserModel)
            .order_by(col(UserModel.created_at).desc())
            .offset(skip)
            .limit(limit)
        )
        users = self._session.exec(statement).all()
        return [to_entity(user) for user in users], count

    def get_by_email(self, email: str) -> UserEntity | None:
        db_user = crud.get_user_by_email(session=self._session, email=email)
        return to_entity(db_user) if db_user else None

    def create(self, new_user: NewUser) -> UserEntity:
        user_create = UserCreate(
            email=new_user.email,
            password=new_user.password,
            role=new_user.role,
            is_active=new_user.is_active,
            full_name=new_user.full_name,
        )
        return to_entity(
            crud.create_user(session=self._session, user_create=user_create)
        )

    def update_profile(self, user_id: uuid.UUID, changes: ProfileUpdate) -> UserEntity:
        db_user = self._session.get(UserModel, user_id)
        if not db_user:
            raise UserNotFound(str(user_id))
        for field, value in vars(changes).items():
            if value is not None:
                setattr(db_user, field, value)
        self._session.add(db_user)
        self._session.commit()
        self._session.refresh(db_user)
        return to_entity(db_user)
