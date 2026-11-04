"""pro je haushalt (19.8): abo-ablauf, testphase, apple-transaktion, werbe-gutschriften

Revision ID: c5d2e8f1a937
Revises: b3e7c1d9f420
Create Date: 2026-11-04 20:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'c5d2e8f1a937'
down_revision: Union[str, Sequence[str], None] = 'b3e7c1d9f420'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table('household') as batch:
        batch.add_column(sa.Column('pro_until', sa.DateTime(), nullable=True))
        batch.add_column(sa.Column('pro_trial_until', sa.DateTime(), nullable=True))
        batch.add_column(sa.Column('pro_trial_reminded', sa.Boolean(), nullable=False, server_default=sa.false()))
        batch.add_column(sa.Column('pro_checked_at', sa.DateTime(), nullable=True))
        batch.add_column(sa.Column('apple_transaction_id', sa.String(length=40), nullable=True))
        batch.add_column(sa.Column('ad_credits', sa.Integer(), nullable=False, server_default='0'))
        batch.create_unique_constraint('uq_household_apple_transaction_id', ['apple_transaction_id'])
    op.create_table(
        'ad_reward',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('household_id', sa.Integer(), nullable=False),
        sa.Column('transaction_id', sa.String(length=100), nullable=False),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
        sa.ForeignKeyConstraint(['household_id'], ['household.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('transaction_id'),
    )
    op.create_index('ix_ad_reward_household_id', 'ad_reward', ['household_id'])


def downgrade() -> None:
    op.drop_index('ix_ad_reward_household_id', table_name='ad_reward')
    op.drop_table('ad_reward')
    with op.batch_alter_table('household') as batch:
        batch.drop_constraint('uq_household_apple_transaction_id', type_='unique')
        for c in ('ad_credits', 'apple_transaction_id', 'pro_checked_at', 'pro_trial_reminded', 'pro_trial_until',
                  'pro_until'):
            batch.drop_column(c)
