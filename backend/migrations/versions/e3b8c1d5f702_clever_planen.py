"""clever planen: abwechslung, gäste, lunchbox-push, wochen-basics, vorrat-ort

Revision ID: e3b8c1d5f702
Revises: d2a7f4c9e815
Create Date: 2026-11-03 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'e3b8c1d5f702'
down_revision: Union[str, Sequence[str], None] = 'd2a7f4c9e815'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('weekly_basic',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('household_id', sa.Integer(), nullable=False),
    sa.Column('name', sa.String(length=100), nullable=False),
    sa.Column('amount', sa.Float(), nullable=True),
    sa.Column('unit', sa.String(length=10), nullable=False),
    sa.ForeignKeyConstraint(['household_id'], ['household.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_weekly_basic_household_id'), 'weekly_basic', ['household_id'], unique=False)
    op.add_column('household', sa.Column('variety', sa.JSON(), server_default='{}', nullable=False))
    op.add_column('member', sa.Column('lunchbox_push', sa.String(length=5), nullable=True))
    op.add_column('meal_plan_entry', sa.Column('guests', sa.Integer(), server_default='0', nullable=False))
    op.add_column('pantry_item', sa.Column('location', sa.String(length=15), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table('pantry_item') as batch:
        batch.drop_column('location')
    with op.batch_alter_table('meal_plan_entry') as batch:
        batch.drop_column('guests')
    with op.batch_alter_table('member') as batch:
        batch.drop_column('lunchbox_push')
    with op.batch_alter_table('household') as batch:
        batch.drop_column('variety')
    op.drop_index(op.f('ix_weekly_basic_household_id'), table_name='weekly_basic')
    op.drop_table('weekly_basic')
