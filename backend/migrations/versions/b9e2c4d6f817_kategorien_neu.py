"""angebote neu kategorisieren (Stichwort-Fallen wie „Schwein“ ≠ Wein)

Revision ID: b9e2c4d6f817
Revises: a7c3e9f1b204
Create Date: 2026-11-03 20:00:00.000000

"""
import json
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b9e2c4d6f817'
down_revision: Union[str, Sequence[str], None] = 'a7c3e9f1b204'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def offer_text(title: str, source_id: str, raw: dict) -> str:
    """Derselbe Text wie beim Import (kaufda.parse_pages/parse_search): Produktname + Beschreibung."""
    if "products" in raw:
        i = int(source_id.split("#")[1]) if "#" in source_id else 0
        p = raw["products"][i] if i < len(raw["products"]) else {}
        desc = " ".join(d.get("paragraph") or "" for d in p.get("description") or [])
        return f"{(p.get('name') or title).strip()} {desc}"
    return f"{title} {raw.get('description') or ''}"


def upgrade() -> None:
    from app.sources.kaufda import category_of
    conn = op.get_bind()
    for oid, chain, title, source_id, raw, old in conn.execute(sa.text(
            "SELECT id, chain, title, source_id, raw, category FROM offer")).all():
        data = json.loads(raw) if isinstance(raw, str) else (raw or {})
        if (new := category_of(chain, offer_text(title, source_id, data))) != old:
            conn.execute(sa.text("UPDATE offer SET category = :c WHERE id = :i"), {"c": new, "i": oid})


def downgrade() -> None:
    pass  # alte (falsche) Kategorien werden nicht wiederhergestellt
