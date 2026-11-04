"""fehler melden + wieder vorschlagen (19.9): report, recipe.unhidden

Revision ID: d9a4f6b2c158
Revises: c5d2e8f1a937
Create Date: 2026-11-04 21:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'd9a4f6b2c158'
down_revision: Union[str, Sequence[str], None] = 'c5d2e8f1a937'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table('recipe') as batch:
        batch.add_column(sa.Column('unhidden', sa.Boolean(), nullable=False, server_default=sa.false()))
    op.create_table(
        'report',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('household_id', sa.Integer(), nullable=False),
        sa.Column('member_id', sa.Integer(), nullable=True),
        sa.Column('recipe_id', sa.Integer(), nullable=True),
        sa.Column('kind', sa.String(length=20), nullable=False),
        sa.Column('ingredient', sa.String(length=100), nullable=False),
        sa.Column('offer_title', sa.String(length=200), nullable=False),
        sa.Column('note', sa.String(length=500), nullable=False),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
        sa.ForeignKeyConstraint(['household_id'], ['household.id']),
        sa.ForeignKeyConstraint(['member_id'], ['member.id']),
        sa.ForeignKeyConstraint(['recipe_id'], ['recipe.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_report_household_id', 'report', ['household_id'])


def downgrade() -> None:
    op.drop_index('ix_report_household_id', table_name='report')
    op.drop_table('report')
    with op.batch_alter_table('recipe') as batch:
        batch.drop_column('unhidden')
