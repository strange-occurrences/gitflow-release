"""add admin analytics tables

Revision ID: e8f9a0b1c2d3
Revises:
Create Date: 2026-06-18 01:00:00

Dummy migration #1 (numbered scheme: migration_1, migration_2, migration_3, ...
so experiments can grow by appending migration_N). Mirrors the real premapp
promotion revision (backend/aci/alembic/versions/2026_06_18_0100-e8f9a0b1c2d3_add_admin_analytics_tables.py).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "e8f9a0b1c2d3"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create the admin analytics tables (2 of the 7 "missing tables")."""
    op.create_table(
        "admin_analytics_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("event_type", sa.String(length=64), nullable=False),
        sa.Column("occurred_at", sa.DateTime(), nullable=False),
    )
    op.create_table(
        "admin_analytics_daily",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("metric", sa.String(length=64), nullable=False),
        sa.Column("value", sa.Integer(), nullable=False),
    )


def downgrade() -> None:
    """Drop the admin analytics tables."""
    op.drop_table("admin_analytics_daily")
    op.drop_table("admin_analytics_events")
