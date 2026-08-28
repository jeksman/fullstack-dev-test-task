"""Seed one user per role so the permission matrix can be exercised by hand.

    uv run python -m app.seed_data

The admin comes from FIRST_SUPERUSER in .env; the other two are demo accounts
and are only ever created, never updated, so a changed password survives reruns.
"""

import logging

from sqlmodel import Session

from app import crud
from app.core.db import engine, init_db
from app.core.domain.rbac import Role
from app.models import UserCreate

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DEMO_USERS = [
    ("manager@example.com", Role.MANAGER, "Maria Manager"),
    ("member@example.com", Role.MEMBER, "Mike Member"),
]
DEMO_PASSWORD = "changethis"


def seed(session: Session) -> None:
    init_db(session)  # creates the admin from FIRST_SUPERUSER
    for email, role, full_name in DEMO_USERS:
        if crud.get_user_by_email(session=session, email=email):
            logger.info("%s already exists, skipping", email)
            continue
        crud.create_user(
            session=session,
            user_create=UserCreate(
                email=email,
                password=DEMO_PASSWORD,
                role=role,
                full_name=full_name,
            ),
        )
        logger.info("created %s with role %s", email, role)


def main() -> None:
    with Session(engine) as session:
        seed(session)


if __name__ == "__main__":
    main()
