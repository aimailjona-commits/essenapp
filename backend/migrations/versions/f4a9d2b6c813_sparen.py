"""sparen (phase 12): merkliste, preisalarme, open food facts, vorratsplatz, nächste-woche-gruppe

Revision ID: f4a9d2b6c813
Revises: e3b8c1d5f702
Create Date: 2026-11-03 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'f4a9d2b6c813'
down_revision: Union[str, Sequence[str], None] = 'e3b8c1d5f702'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('watch_item',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('household_id', sa.Integer(), nullable=False),
    sa.Column('kind', sa.String(length=10), nullable=False),
    sa.Column('label', sa.String(length=200), nullable=False),
    sa.Column('brand', sa.String(length=100), nullable=False),
    sa.Column('ean', sa.String(length=14), nullable=False),
    sa.Column('image_url', sa.String(length=500), nullable=False),
    sa.Column('category', sa.String(length=30), nullable=False),
    sa.Column('max_price_cents', sa.Integer(), nullable=True),
    sa.Column('max_base_price_cents', sa.Integer(), nullable=True),
    sa.Column('base_unit', sa.String(length=3), nullable=False),
    sa.Column('chains', sa.JSON(), nullable=False),
    sa.Column('lasts_weeks', sa.Float(), nullable=True),
    sa.Column('last_bought', sa.Date(), nullable=True),
    sa.Column('rhythm_push_at', sa.Date(), nullable=True),
    sa.Column('rhythm_listed_at', sa.Date(), nullable=True),
    sa.Column('created_by', sa.Integer(), nullable=True),
    sa.Column('created_at', sa.DateTime(), server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
    sa.ForeignKeyConstraint(['created_by'], ['member.id'], ),
    sa.ForeignKeyConstraint(['household_id'], ['household.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_watch_item_household_id'), 'watch_item', ['household_id'], unique=False)
    op.create_table('watch_hit',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('watch_item_id', sa.Integer(), nullable=False),
    sa.Column('offer_id', sa.Integer(), nullable=False),
    sa.Column('week', sa.String(length=8), nullable=False),
    sa.Column('notified_at', sa.DateTime(), nullable=True),
    sa.ForeignKeyConstraint(['watch_item_id'], ['watch_item.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('watch_item_id', 'offer_id')
    )
    op.create_index(op.f('ix_watch_hit_watch_item_id'), 'watch_hit', ['watch_item_id'], unique=False)
    op.add_column('household', sa.Column('storage_space', sa.String(length=10), server_default='mittel', nullable=False))
    op.add_column('shopping_item', sa.Column('defer_week', sa.String(length=8), nullable=True))
    op.add_column('product', sa.Column('nutri_score', sa.String(length=1), nullable=True))
    op.add_column('product', sa.Column('off_code', sa.String(length=20), server_default='', nullable=False))
    op.add_column('product', sa.Column('off_bio', sa.Boolean(), server_default='0', nullable=False))
    op.add_column('product', sa.Column('off_vegan', sa.Boolean(), server_default='0', nullable=False))
    op.add_column('product', sa.Column('off_vegetarian', sa.Boolean(), server_default='0', nullable=False))
    op.add_column('product', sa.Column('off_checked_at', sa.DateTime(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table('product') as batch:
        for col in ('off_checked_at', 'off_vegetarian', 'off_vegan', 'off_bio', 'off_code', 'nutri_score'):
            batch.drop_column(col)
    with op.batch_alter_table('shopping_item') as batch:
        batch.drop_column('defer_week')
    with op.batch_alter_table('household') as batch:
        batch.drop_column('storage_space')
    op.drop_index(op.f('ix_watch_hit_watch_item_id'), table_name='watch_hit')
    op.drop_table('watch_hit')
    op.drop_index(op.f('ix_watch_item_household_id'), table_name='watch_item')
    op.drop_table('watch_item')
