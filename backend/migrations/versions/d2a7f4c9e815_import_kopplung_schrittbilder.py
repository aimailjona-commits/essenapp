"""import, kopplungscode, schritt-bilder, kostenprotokoll

Revision ID: d2a7f4c9e815
Revises: c5e8a1f2d304
Create Date: 2026-11-03 01:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'd2a7f4c9e815'
down_revision: Union[str, Sequence[str], None] = 'c5e8a1f2d304'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('member_token',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('member_id', sa.Integer(), nullable=False),
    sa.Column('token_hash', sa.String(length=64), nullable=False),
    sa.Column('label', sa.String(length=50), nullable=False),
    sa.Column('created_at', sa.DateTime(), server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
    sa.ForeignKeyConstraint(['member_id'], ['member.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('token_hash')
    )
    op.create_index(op.f('ix_member_token_member_id'), 'member_token', ['member_id'], unique=False)
    op.create_table('pairing_code',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('member_id', sa.Integer(), nullable=False),
    sa.Column('code', sa.String(length=6), nullable=False),
    sa.Column('expires_at', sa.DateTime(), nullable=False),
    sa.Column('used_at', sa.DateTime(), nullable=True),
    sa.ForeignKeyConstraint(['member_id'], ['member.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('code')
    )
    op.create_index(op.f('ix_pairing_code_member_id'), 'pairing_code', ['member_id'], unique=False)
    op.create_table('ai_cost',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('household_id', sa.Integer(), nullable=True),
    sa.Column('kind', sa.String(length=20), nullable=False),
    sa.Column('model', sa.String(length=60), nullable=False),
    sa.Column('cost_cents', sa.Float(), nullable=False),
    sa.Column('info', sa.String(length=200), nullable=False),
    sa.Column('created_at', sa.DateTime(), server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
    sa.ForeignKeyConstraint(['household_id'], ['household.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ai_cost_household_id'), 'ai_cost', ['household_id'], unique=False)
    op.add_column('recipe', sa.Column('step_images', sa.JSON(), server_default='[]', nullable=False))
    op.add_column('household', sa.Column('step_images', sa.Boolean(), server_default=sa.true(), nullable=False))


def downgrade() -> None:
    with op.batch_alter_table('household') as batch:
        batch.drop_column('step_images')
    with op.batch_alter_table('recipe') as batch:
        batch.drop_column('step_images')
    op.drop_index(op.f('ix_ai_cost_household_id'), table_name='ai_cost')
    op.drop_table('ai_cost')
    op.drop_index(op.f('ix_pairing_code_member_id'), table_name='pairing_code')
    op.drop_table('pairing_code')
    op.drop_index(op.f('ix_member_token_member_id'), table_name='member_token')
    op.drop_table('member_token')
