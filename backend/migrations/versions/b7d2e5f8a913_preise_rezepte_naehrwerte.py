"""preisdaten, meine rezepte, naehrwerte

Revision ID: b7d2e5f8a913
Revises: a4e7c2d91b10
Create Date: 2026-11-02 23:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b7d2e5f8a913'
down_revision: Union[str, Sequence[str], None] = 'a4e7c2d91b10'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('product',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('key', sa.String(length=320), nullable=False),
    sa.Column('title', sa.String(length=200), nullable=False),
    sa.Column('brand', sa.String(length=100), nullable=False),
    sa.Column('amount', sa.Double(), nullable=True),
    sa.Column('unit', sa.String(length=10), nullable=False),
    sa.Column('ean', sa.String(length=14), nullable=False),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('key')
    )
    op.create_index(op.f('ix_product_ean'), 'product', ['ean'], unique=False)
    op.create_table('price_point',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('product_id', sa.Integer(), nullable=False),
    sa.Column('chain', sa.String(length=30), nullable=False),
    sa.Column('store_ref', sa.String(length=50), nullable=False),
    sa.Column('week', sa.String(length=8), nullable=False),
    sa.Column('price_cents', sa.Integer(), nullable=False),
    sa.Column('regular_price_cents', sa.Integer(), nullable=True),
    sa.Column('base_price_cents', sa.Integer(), nullable=True),
    sa.Column('is_offer', sa.Boolean(), nullable=False),
    sa.Column('valid_from', sa.Date(), nullable=False),
    sa.Column('valid_to', sa.Date(), nullable=False),
    sa.ForeignKeyConstraint(['product_id'], ['product.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('product_id', 'chain', 'store_ref', 'week')
    )
    op.create_index(op.f('ix_price_point_product_id'), 'price_point', ['product_id'], unique=False)
    with op.batch_alter_table('offer') as batch:
        batch.add_column(sa.Column('product_id', sa.Integer(), nullable=True))
        batch.create_index(batch.f('ix_offer_product_id'), ['product_id'], unique=False)
        batch.create_foreign_key('fk_offer_product_id', 'product', ['product_id'], ['id'])

    op.add_column('recipe', sa.Column('source_url', sa.String(length=500), server_default='', nullable=False))
    op.add_column('recipe', sa.Column('source_author', sa.String(length=100), server_default='', nullable=False))
    op.add_column('recipe', sa.Column('tags', sa.JSON(), server_default='[]', nullable=False))
    op.add_column('meal_plan_entry', sa.Column('scale', sa.Double(), server_default='1', nullable=False))
    op.create_table('recipe_favorite',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('household_id', sa.Integer(), nullable=False),
    sa.Column('recipe_id', sa.Integer(), nullable=False),
    sa.Column('member_id', sa.Integer(), nullable=False),
    sa.Column('created_at', sa.DateTime(), server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
    sa.ForeignKeyConstraint(['household_id'], ['household.id'], ),
    sa.ForeignKeyConstraint(['member_id'], ['member.id'], ),
    sa.ForeignKeyConstraint(['recipe_id'], ['recipe.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('household_id', 'recipe_id')
    )
    op.create_index(op.f('ix_recipe_favorite_household_id'), 'recipe_favorite', ['household_id'], unique=False)
    op.create_index(op.f('ix_recipe_favorite_recipe_id'), 'recipe_favorite', ['recipe_id'], unique=False)
    op.create_table('rating',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('recipe_id', sa.Integer(), nullable=False),
    sa.Column('member_id', sa.Integer(), nullable=False),
    sa.Column('stars', sa.Integer(), nullable=False),
    sa.Column('again', sa.String(length=12), nullable=False),
    sa.Column('note', sa.String(length=500), nullable=False),
    sa.Column('cooked_at', sa.DateTime(), nullable=False),
    sa.ForeignKeyConstraint(['member_id'], ['member.id'], ),
    sa.ForeignKeyConstraint(['recipe_id'], ['recipe.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_rating_recipe_id'), 'rating', ['recipe_id'], unique=False)

    op.create_table('food',
    sa.Column('id', sa.Integer(), autoincrement=False, nullable=False),
    sa.Column('description', sa.String(length=300), nullable=False),
    sa.Column('data_type', sa.String(length=20), nullable=False),
    sa.Column('kcal', sa.Double(), nullable=True),
    sa.Column('protein', sa.Double(), nullable=True),
    sa.Column('fat', sa.Double(), nullable=True),
    sa.Column('carbs', sa.Double(), nullable=True),
    sa.Column('fiber', sa.Double(), nullable=True),
    sa.Column('sugar', sa.Double(), nullable=True),
    sa.Column('salt', sa.Double(), nullable=True),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_table('ingredient_map',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('ingredient_key', sa.String(length=100), nullable=False),
    sa.Column('food_id', sa.Integer(), nullable=True),
    sa.Column('grams_per_piece', sa.Double(), nullable=True),
    sa.Column('confidence', sa.String(length=10), nullable=False),
    sa.Column('created_at', sa.DateTime(), server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
    sa.ForeignKeyConstraint(['food_id'], ['food.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('ingredient_key')
    )
    # Rückfüllung der Preispunkte aus den gespeicherten Angeboten: Job `price_history` (Angebote ohne product_id)


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS food_fts")  # von tools.import_usda angelegt
    op.drop_table('ingredient_map')
    op.drop_table('food')
    op.drop_index(op.f('ix_rating_recipe_id'), table_name='rating')
    op.drop_table('rating')
    op.drop_index(op.f('ix_recipe_favorite_recipe_id'), table_name='recipe_favorite')
    op.drop_index(op.f('ix_recipe_favorite_household_id'), table_name='recipe_favorite')
    op.drop_table('recipe_favorite')
    op.drop_column('meal_plan_entry', 'scale')
    op.drop_column('recipe', 'tags')
    op.drop_column('recipe', 'source_author')
    op.drop_column('recipe', 'source_url')
    with op.batch_alter_table('offer') as batch:
        batch.drop_constraint('fk_offer_product_id', type_='foreignkey')
        batch.drop_index(batch.f('ix_offer_product_id'))
        batch.drop_column('product_id')
    op.drop_index(op.f('ix_price_point_product_id'), table_name='price_point')
    op.drop_table('price_point')
    op.drop_index(op.f('ix_product_ean'), table_name='product')
    op.drop_table('product')
