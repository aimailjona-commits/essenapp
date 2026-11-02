"""osm_id laenger

Revision ID: 811c113bd35d
Revises: c3ffcd1b7e76
Create Date: 2026-11-02 21:17:00.969812

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '811c113bd35d'
down_revision: Union[str, Sequence[str], None] = 'c3ffcd1b7e76'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    with op.batch_alter_table('household_store') as batch:  # SQLite kann ALTER COLUMN nur per Batch
        batch.alter_column('osm_id', existing_type=sa.VARCHAR(length=30), type_=sa.String(length=60),
                           existing_nullable=False, existing_server_default=sa.text("('')"))


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('household_store') as batch:
        batch.alter_column('osm_id', existing_type=sa.String(length=60), type_=sa.VARCHAR(length=30),
                           existing_nullable=False, existing_server_default=sa.text("('')"))
