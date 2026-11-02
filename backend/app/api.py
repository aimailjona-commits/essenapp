from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.core.auth import current_member, new_token
from app.core.db import get_db
from app.models import Household, HouseholdStore, Member, Offer
from app.schemas import HouseholdCreate, HouseholdCreated, HouseholdOut, HouseholdSettings, OfferOut

router = APIRouter()


@router.post("/households", response_model=HouseholdCreated, status_code=201)
def create_household(body: HouseholdCreate, db: Session = Depends(get_db)):
    token, token_hash = new_token()
    household = Household(name=body.name)
    db.add_all([household, Member(household=household, name=body.member_name, token_hash=token_hash, role="owner")])
    db.commit()
    return {"token": token, "household": household}


@router.get("/household", response_model=HouseholdOut)
def get_household(member: Member = Depends(current_member)):
    return member.household


@router.patch("/household", response_model=HouseholdOut)
def update_household(body: HouseholdSettings, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    household = member.household
    changes = body.model_dump(exclude_unset=True)
    if (stores := changes.pop("stores", None)) is not None:
        household.stores = [HouseholdStore(**s) for s in stores]
    for key, value in changes.items():
        setattr(household, key, value)
    db.commit()
    return household


@router.get("/offers", response_model=list[OfferOut])
def list_offers(chain: str | None = None, category: str | None = None, q: str | None = None,
                member: Member = Depends(current_member), db: Session = Depends(get_db)):
    stores = [s for s in member.household.stores if s.enabled and (chain is None or s.chain == chain)]
    if not stores:
        return []
    today = date.today()
    query = select(Offer).where(
        or_(*[(Offer.chain == s.chain) & (Offer.store_ref == s.store_ref) for s in stores]),
        Offer.valid_from <= today, Offer.valid_to >= today,
    )
    if category:
        query = query.where(Offer.category == category)
    if q:
        query = query.where(Offer.title.ilike(f"%{q}%"))
    return db.scalars(query.order_by(Offer.category, Offer.title)).all()
