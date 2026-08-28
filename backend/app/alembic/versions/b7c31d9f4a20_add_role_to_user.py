"""Add role column to user

Revision ID: b7c31d9f4a20
Revises: fe56fa70289e
Create Date: 2026-08-28

"""

import sqlalchemy as sa
import sqlmodel.sql.sqltypes
from alembic import op

revision = "b7c31d9f4a20"
down_revision = "fe56fa70289e"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "user",
        sa.Column(
            "role",
            sqlmodel.sql.sqltypes.AutoString(length=20),
            nullable=False,
            server_default="member",
        ),
    )
    # Existing superusers keep their access under the new source of truth.
    op.execute("UPDATE \"user\" SET role = 'admin' WHERE is_superuser IS TRUE")


def downgrade():
    op.drop_column("user", "role")
