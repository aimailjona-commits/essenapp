import hashlib
import secrets

from fastapi import Depends, Header, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.db import get_db
from app.models import Member


def new_token() -> tuple[str, str]:
    """(Klartext-Token für den Client, Hash für die DB)"""
    token = secrets.token_urlsafe(32)
    return token, hash_token(token)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def current_member(authorization: str = Header(""), db: Session = Depends(get_db)) -> Member:
    token = authorization.removeprefix("Bearer ").strip()
    member = token and db.scalar(select(Member).where(Member.token_hash == hash_token(token)))
    if not member:
        raise HTTPException(401, "Ungültiges Token")
    return member
