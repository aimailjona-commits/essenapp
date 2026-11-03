"""bonus, laden, ausgaben, motivation (phase 13/14): coupons, bonus-konten, käufe, erfolge, rückblicke,
rewe-bonus am angebot, rezept-link

Revision ID: a7c3e9f1b204
Revises: f4a9d2b6c813
Create Date: 2026-11-03 18:00:00.000000

"""
import json
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'a7c3e9f1b204'
down_revision: Union[str, Sequence[str], None] = 'f4a9d2b6c813'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('coupon',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('household_id', sa.Integer(), nullable=False),
    sa.Column('program', sa.String(length=12), nullable=False),
    sa.Column('partner', sa.String(length=50), nullable=False),
    sa.Column('chain', sa.String(length=30), nullable=False),
    sa.Column('product', sa.String(length=100), nullable=False),
    sa.Column('category', sa.String(length=30), nullable=False),
    sa.Column('benefit', sa.String(length=100), nullable=False),
    sa.Column('multiplier', sa.Integer(), nullable=True),
    sa.Column('bonus_cents', sa.Integer(), nullable=True),
    sa.Column('percent', sa.Integer(), nullable=True),
    sa.Column('min_spend_cents', sa.Integer(), nullable=True),
    sa.Column('valid_until', sa.Date(), nullable=True),
    sa.Column('code', sa.String(length=200), nullable=False),
    sa.Column('code_type', sa.String(length=10), nullable=False),
    sa.Column('source', sa.String(length=10), nullable=False),
    sa.Column('expiry_notified_at', sa.Date(), nullable=True),
    sa.Column('created_by', sa.Integer(), nullable=True),
    sa.Column('created_at', sa.DateTime(), server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
    sa.ForeignKeyConstraint(['created_by'], ['member.id'], ),
    sa.ForeignKeyConstraint(['household_id'], ['household.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_coupon_household_id'), 'coupon', ['household_id'], unique=False)
    op.create_table('bonus_entry',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('household_id', sa.Integer(), nullable=False),
    sa.Column('program', sa.String(length=12), nullable=False),
    sa.Column('kind', sa.String(length=5), nullable=False),
    sa.Column('delta', sa.Integer(), nullable=False),
    sa.Column('note', sa.String(length=100), nullable=False),
    sa.Column('member_id', sa.Integer(), nullable=True),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.ForeignKeyConstraint(['household_id'], ['household.id'], ),
    sa.ForeignKeyConstraint(['member_id'], ['member.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_bonus_entry_household_id'), 'bonus_entry', ['household_id'], unique=False)
    op.create_table('purchase',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('household_id', sa.Integer(), nullable=False),
    sa.Column('item_id', sa.Integer(), nullable=True),
    sa.Column('name', sa.String(length=100), nullable=False),
    sa.Column('amount', sa.Float(), nullable=True),
    sa.Column('unit', sa.String(length=10), nullable=False),
    sa.Column('chain', sa.String(length=30), nullable=False),
    sa.Column('category', sa.String(length=30), nullable=False),
    sa.Column('offer_id', sa.Integer(), nullable=True),
    sa.Column('price_cents', sa.Integer(), nullable=False),
    sa.Column('saved_cents', sa.Integer(), nullable=False),
    sa.Column('estimated', sa.Boolean(), nullable=False),
    sa.Column('verdict', sa.String(length=15), nullable=True),
    sa.Column('source', sa.String(length=10), nullable=False),
    sa.Column('bought_by', sa.String(length=50), nullable=False),
    sa.Column('bought_at', sa.DateTime(), nullable=False),
    sa.ForeignKeyConstraint(['household_id'], ['household.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_purchase_household_id'), 'purchase', ['household_id'], unique=False)
    op.create_index(op.f('ix_purchase_item_id'), 'purchase', ['item_id'], unique=False)
    op.create_index(op.f('ix_purchase_bought_at'), 'purchase', ['bought_at'], unique=False)
    op.create_table('achievement',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('household_id', sa.Integer(), nullable=False),
    sa.Column('member_id', sa.Integer(), nullable=False),
    sa.Column('key', sa.String(length=30), nullable=False),
    sa.Column('unlocked_at', sa.DateTime(), nullable=False),
    sa.Column('seen_at', sa.DateTime(), nullable=True),
    sa.ForeignKeyConstraint(['household_id'], ['household.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('household_id', 'member_id', 'key')
    )
    op.create_index(op.f('ix_achievement_household_id'), 'achievement', ['household_id'], unique=False)
    op.create_table('week_review',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('household_id', sa.Integer(), nullable=False),
    sa.Column('week', sa.String(length=8), nullable=False),
    sa.Column('data', sa.JSON(), nullable=False),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.ForeignKeyConstraint(['household_id'], ['household.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('household_id', 'week')
    )
    op.create_index(op.f('ix_week_review_household_id'), 'week_review', ['household_id'], unique=False)
    op.add_column('offer', sa.Column('bonus_cents', sa.Integer(), nullable=True))
    with op.batch_alter_table('recipe') as batch:
        batch.add_column(sa.Column('share_code', sa.String(length=16), nullable=True))
        batch.create_unique_constraint('uq_recipe_share_code', ['share_code'])

    # Rewe-Bonus (39) für schon importierte Angebote aus den gespeicherten Rohdaten nachtragen
    from app.sources.kaufda import bonus_cents
    conn = op.get_bind()
    rows = conn.execute(sa.text("SELECT id, title, source_id, raw FROM offer WHERE chain = 'rewe' "
                                "AND lower(raw) LIKE '%bonus%'")).all()
    for oid, title, source_id, raw in rows:
        data = json.loads(raw) if isinstance(raw, str) else raw
        names = [(p.get("name") or "").strip() for p in data.get("products") or []]
        if (bonus := bonus_cents(data.get("deals") or [], title.strip(), names)) is not None:
            conn.execute(sa.text("UPDATE offer SET bonus_cents = :b WHERE id = :i"), {"b": bonus, "i": oid})


def downgrade() -> None:
    with op.batch_alter_table('recipe') as batch:
        batch.drop_constraint('uq_recipe_share_code', type_='unique')
        batch.drop_column('share_code')
    with op.batch_alter_table('offer') as batch:
        batch.drop_column('bonus_cents')
    for table in ('week_review', 'achievement', 'purchase', 'bonus_entry', 'coupon'):
        for ix in {'purchase': ('household_id', 'item_id', 'bought_at')}.get(table, ('household_id',)):
            op.drop_index(op.f(f'ix_{table}_{ix}'), table_name=table)
        op.drop_table(table)
