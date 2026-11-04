"""plan und gericht rueckgaengig (19.3): meal_plan.active_at, meal_plan_entry.prev_recipe_id

Revision ID: a8d3f5b7c294
Revises: f2c8d4e6a173
Create Date: 2026-11-04 16:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'a8d3f5b7c294'
down_revision: Union[str, Sequence[str], None] = 'f2c8d4e6a173'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table('meal_plan') as batch:
        batch.add_column(sa.Column('active_at', sa.DateTime(), nullable=False, server_default=sa.func.now()))
    op.execute(sa.text("UPDATE meal_plan SET active_at = created_at"))
    with op.batch_alter_table('meal_plan_entry') as batch:
        batch.add_column(sa.Column('prev_recipe_id', sa.Integer(), nullable=True))
        batch.create_foreign_key('fk_meal_plan_entry_prev_recipe', 'recipe', ['prev_recipe_id'], ['id'])


def downgrade() -> None:
    with op.batch_alter_table('meal_plan_entry') as batch:
        batch.drop_constraint('fk_meal_plan_entry_prev_recipe', type_='foreignkey')
        batch.drop_column('prev_recipe_id')
    with op.batch_alter_table('meal_plan') as batch:
        batch.drop_column('active_at')
