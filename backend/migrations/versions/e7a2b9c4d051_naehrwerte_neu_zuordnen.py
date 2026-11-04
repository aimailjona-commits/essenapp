"""unsichere naehrwert-zuordnungen neu (19.2): niedrig, bohnen/kichererbsen/tortillas/wraps

Revision ID: e7a2b9c4d051
Revises: d6f1a8b3c920
Create Date: 2026-11-04 14:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'e7a2b9c4d051'
down_revision: Union[str, Sequence[str], None] = 'd6f1a8b3c920'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Gelöschte Zuordnungen legt food_map.map_later beim nächsten Abruf der Nährwerte mit den neuen Regeln wieder an
    op.execute(sa.text(
        "DELETE FROM ingredient_map WHERE confidence = 'niedrig' OR ingredient_key LIKE '%bohne%'"
        " OR ingredient_key LIKE '%kichererbse%' OR ingredient_key LIKE '%tortilla%' OR ingredient_key LIKE '%wrap%'"))


def downgrade() -> None:
    pass  # alte Zuordnungen werden nicht wiederhergestellt
