"""woche per swipe (Phase 20): swipe_deck, swipe_card, swipe_vote

Revision ID: e1b5c7a9d240
Revises: d9a4f6b2c158
Create Date: 2026-11-05 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'e1b5c7a9d240'
down_revision: Union[str, Sequence[str], None] = 'd9a4f6b2c158'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'swipe_deck',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('household_id', sa.Integer(), nullable=False),
        sa.Column('member_id', sa.Integer(), nullable=True),
        sa.Column('week', sa.String(length=8), nullable=False),
        sa.Column('state', sa.String(length=10), nullable=False),
        sa.Column('need', sa.JSON(), nullable=False),
        sa.Column('slots', sa.JSON(), nullable=False),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
        sa.ForeignKeyConstraint(['household_id'], ['household.id']),
        sa.ForeignKeyConstraint(['member_id'], ['member.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_swipe_deck_household_id', 'swipe_deck', ['household_id'])
    op.create_table(
        'swipe_card',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('deck_id', sa.Integer(), nullable=False),
        sa.Column('meal_type', sa.String(length=20), nullable=False),
        sa.Column('position', sa.Integer(), nullable=False),
        sa.Column('source', sa.String(length=10), nullable=False),
        sa.Column('recipe_id', sa.Integer(), nullable=True),
        sa.Column('title', sa.String(length=200), nullable=False),
        sa.Column('description', sa.String(length=500), nullable=False),
        sa.Column('cuisine', sa.String(length=50), nullable=False),
        sa.Column('prep_minutes', sa.Integer(), nullable=False),
        sa.Column('side', sa.String(length=20), nullable=False),
        sa.Column('protein', sa.String(length=20), nullable=False),
        sa.Column('image_url', sa.String(length=500), nullable=False),
        sa.Column('cost_cents', sa.Integer(), nullable=False),
        sa.Column('deals', sa.Integer(), nullable=False),
        sa.Column('chain', sa.String(length=30), nullable=False),
        sa.Column('ingredients', sa.JSON(), nullable=False),
        sa.ForeignKeyConstraint(['deck_id'], ['swipe_deck.id']),
        sa.ForeignKeyConstraint(['recipe_id'], ['recipe.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_swipe_card_deck_id', 'swipe_card', ['deck_id'])
    op.create_table(
        'swipe_vote',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('card_id', sa.Integer(), nullable=False),
        sa.Column('member_id', sa.Integer(), nullable=False),
        sa.Column('vote', sa.String(length=10), nullable=False),
        sa.Column('days', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
        sa.ForeignKeyConstraint(['card_id'], ['swipe_card.id']),
        sa.ForeignKeyConstraint(['member_id'], ['member.id']),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('card_id', 'member_id'),
    )
    op.create_index('ix_swipe_vote_card_id', 'swipe_vote', ['card_id'])


def downgrade() -> None:
    op.drop_index('ix_swipe_vote_card_id', table_name='swipe_vote')
    op.drop_table('swipe_vote')
    op.drop_index('ix_swipe_card_deck_id', table_name='swipe_card')
    op.drop_table('swipe_card')
    op.drop_index('ix_swipe_deck_household_id', table_name='swipe_deck')
    op.drop_table('swipe_deck')
