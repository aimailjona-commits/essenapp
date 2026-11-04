"""packungsgröße je listeneintrag (19.5): „1 × 1,1 kg, 900 g gebraucht“

Revision ID: b3e7c1d9f420
Revises: a8d3f5b7c294
Create Date: 2026-11-04 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b3e7c1d9f420'
down_revision: Union[str, Sequence[str], None] = 'a8d3f5b7c294'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table('shopping_item') as batch:
        batch.add_column(sa.Column('pack_amount', sa.Float(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table('shopping_item') as batch:
        batch.drop_column('pack_amount')
