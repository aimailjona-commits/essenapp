"""push und scheduler

Revision ID: a4e7c2d91b10
Revises: 62cd9b10caa5
Create Date: 2026-11-02 22:40:00.000000

"""
import secrets
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'a4e7c2d91b10'
down_revision: Union[str, Sequence[str], None] = '62cd9b10caa5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('job_run',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('name', sa.String(length=40), nullable=False),
    sa.Column('ran_at', sa.DateTime(), nullable=False),
    sa.Column('ok', sa.Boolean(), nullable=False),
    sa.Column('info', sa.String(length=500), nullable=False),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_job_run_name'), 'job_run', ['name'], unique=False)
    op.add_column('member', sa.Column('ntfy_topic', sa.String(length=32), nullable=True))
    op.add_column('member', sa.Column('push_enabled', sa.Boolean(), server_default=sa.true(), nullable=False))
    op.add_column('member', sa.Column('plan_prompt_enabled', sa.Boolean(), server_default=sa.true(), nullable=False))
    op.add_column('member', sa.Column('plan_prompt_weekday', sa.Integer(), server_default='6', nullable=False))
    op.add_column('member', sa.Column('plan_prompt_time', sa.String(length=5), server_default='18:00', nullable=False))
    op.add_column('member', sa.Column('quiet_hours', sa.JSON(), nullable=True))
    # bestehende Mitglieder: eigenes Topic + Standard-Ruhezeit
    bind = op.get_bind()
    for (member_id,) in bind.execute(sa.text("SELECT id FROM member")).all():
        bind.execute(sa.text("UPDATE member SET ntfy_topic = :t, quiet_hours = :q WHERE id = :i"),
                     {"t": secrets.token_urlsafe(24), "q": '{"start": "22:00", "end": "07:00"}', "i": member_id})
    with op.batch_alter_table('member') as batch:
        batch.alter_column('ntfy_topic', existing_type=sa.String(length=32), nullable=False)
        batch.create_index(batch.f('ix_member_ntfy_topic'), ['ntfy_topic'], unique=True)


def downgrade() -> None:
    with op.batch_alter_table('member') as batch:
        batch.drop_index(batch.f('ix_member_ntfy_topic'))
        for c in ('quiet_hours', 'plan_prompt_time', 'plan_prompt_weekday', 'plan_prompt_enabled', 'push_enabled',
                  'ntfy_topic'):
            batch.drop_column(c)
    op.drop_index(op.f('ix_job_run_name'), table_name='job_run')
    op.drop_table('job_run')
