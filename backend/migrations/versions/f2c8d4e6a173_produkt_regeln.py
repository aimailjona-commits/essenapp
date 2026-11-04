"""produkt-regeln je haushalt (19.2): „hafermilch statt milch“

Revision ID: f2c8d4e6a173
Revises: e7a2b9c4d051
Create Date: 2026-11-04 15:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'f2c8d4e6a173'
down_revision: Union[str, Sequence[str], None] = 'e7a2b9c4d051'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table('household') as batch:
        batch.add_column(sa.Column('product_rules', sa.JSON(), nullable=False, server_default='[]'))


def downgrade() -> None:
    with op.batch_alter_table('household') as batch:
        batch.drop_column('product_rules')
