"""add user feature flags

Revision ID: b1c2d3e4f5a6
Revises: e8f9a0b1c2d3
Create Date: 2026-07-21 01:00:00

Dummy migration #2 (numbered scheme: migration_1, migration_2, migration_3, ...
so experiments can grow by appending migration_N). Mirrors the real production
promotion revision (backend/aci/alembic/versions/2026_07_21_0100-b1c2d3e4f5a6_add_user_feature_flags.py).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "b1c2d3e4f5a6"
down_revision: Union[str, None] = "e8f9a0b1c2d3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create the user feature flags table (3rd of the 7 "missing tables")."""
    op.create_table(
        "user_feature_flags",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("flag", sa.String(length=64), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("1")),
    )


def downgrade() -> None:
    """Drop the user feature flags table."""
    op.drop_table("user_feature_flags")
