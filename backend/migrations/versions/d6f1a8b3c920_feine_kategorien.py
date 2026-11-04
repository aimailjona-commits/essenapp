"""feine angebots-kategorien (19.1): subcategory, grobe kategorie neu aus dem prospekttext

Revision ID: d6f1a8b3c920
Revises: b9e2c4d6f817
Create Date: 2026-11-04 12:00:00.000000

"""
import json
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'd6f1a8b3c920'
down_revision: Union[str, Sequence[str], None] = 'b9e2c4d6f817'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table('offer') as batch:
        batch.add_column(sa.Column('subcategory', sa.String(length=30), nullable=False, server_default=''))
    from app.sources.kaufda import classify, top_path
    conn = op.get_bind()
    for oid, chain, title, source_id, raw, old in conn.execute(sa.text(
            "SELECT id, chain, title, source_id, raw, category FROM offer")).all():
        data = json.loads(raw) if isinstance(raw, str) else (raw or {})
        cat, sub = classify(chain, _offer_text(title, source_id, data), top_path(_product(source_id, data)), title)
        conn.execute(sa.text("UPDATE offer SET category = :c, subcategory = :s WHERE id = :i"),
                     {"c": cat, "s": sub, "i": oid})


def _product(source_id: str, raw: dict) -> dict:
    i = int(source_id.split("#")[1]) if "#" in source_id else 0
    return raw["products"][i] if i < len(raw.get("products") or []) else {}


def _offer_text(title: str, source_id: str, raw: dict) -> str:
    """Wie b9e2c4d6f817: derselbe Text wie beim Import (Produktname + Beschreibung)."""
    if "products" in raw:
        p = _product(source_id, raw)
        desc = " ".join(d.get("paragraph") or "" for d in p.get("description") or [])
        return f"{(p.get('name') or title).strip()} {desc}"
    return f"{title} {raw.get('description') or ''}"


def downgrade() -> None:
    with op.batch_alter_table('offer') as batch:
        batch.drop_column('subcategory')
