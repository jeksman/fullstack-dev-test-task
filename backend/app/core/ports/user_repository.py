"""The contract the use cases need from storage. Implemented in L3."""

import uuid
from abc import ABC, abstractmethod

from app.core.domain.user import NewUser, ProfileUpdate, User


class AbstractUserRepository(ABC):
    @abstractmethod
    def list(self, *, skip: int, limit: int) -> tuple[list[User], int]:
        """Return a page of users and the total count."""

    @abstractmethod
    def get_by_email(self, email: str) -> User | None: ...

    @abstractmethod
    def create(self, new_user: NewUser) -> User: ...

    @abstractmethod
    def update_profile(self, user_id: uuid.UUID, changes: ProfileUpdate) -> User: ...
