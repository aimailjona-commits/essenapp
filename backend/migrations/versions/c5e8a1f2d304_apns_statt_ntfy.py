"""apns statt ntfy

Revision ID: c5e8a1f2d304
Revises: b7d2e5f8a913
Create Date: 2026-11-03 00:30:00.000000

"""
import secrets
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'c5e8a1f2d304'
down_revision: Union[str, Sequence[str], None] = 'b7d2e5f8a913'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('push_device',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('member_id', sa.Integer(), nullable=False),
    sa.Column('token', sa.String(length=200), nullable=False),
    sa.Column('environment', sa.String(length=12), nullable=False),
    sa.Column('created_at', sa.DateTime(), server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=False),
    sa.Column('last_ok', sa.DateTime(), nullable=True),
    sa.ForeignKeyConstraint(['member_id'], ['member.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('token')
    )
    op.create_index(op.f('ix_push_device_member_id'), 'push_device', ['member_id'], unique=False)
    op.create_table('push_outbox',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('member_id', sa.Integer(), nullable=False),
    sa.Column('title', sa.String(length=200), nullable=False),
    sa.Column('message', sa.String(length=1000), nullable=False),
    sa.Column('click_url', sa.String(length=200), nullable=True),
    sa.Column('thread_id', sa.String(length=40), nullable=False),
    sa.Column('category', sa.String(length=40), nullable=True),
    sa.Column('send_at', sa.DateTime(), nullable=False),
    sa.ForeignKeyConstraint(['member_id'], ['member.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_push_outbox_member_id'), 'push_outbox', ['member_id'], unique=False)
    with op.batch_alter_table('member') as batch:  # ntfy-Topics werden nicht mehr gebraucht
        batch.drop_index(batch.f('ix_member_ntfy_topic'))
        batch.drop_column('ntfy_topic')


def downgrade() -> None:
    op.add_column('member', sa.Column('ntfy_topic', sa.String(length=32), nullable=True))
    bind = op.get_bind()
    for (member_id,) in bind.execute(sa.text("SELECT id FROM member")).all():
        bind.execute(sa.text("UPDATE member SET ntfy_topic = :t WHERE id = :i"),
                     {"t": secrets.token_urlsafe(24), "i": member_id})
    with op.batch_alter_table('member') as batch:
        batch.alter_column('ntfy_topic', existing_type=sa.String(length=32), nullable=False)
        batch.create_index(batch.f('ix_member_ntfy_topic'), ['ntfy_topic'], unique=True)
    op.drop_index(op.f('ix_push_outbox_member_id'), table_name='push_outbox')
    op.drop_table('push_outbox')
    op.drop_index(op.f('ix_push_device_member_id'), table_name='push_device')
    op.drop_table('push_device')
