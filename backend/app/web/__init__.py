"""Web-Version für Familie und Gäste (E4, E40): Jinja + HTMX, Auth über HttpOnly-Cookie mit dem Mitglied-Token."""
from itertools import groupby
from pathlib import Path

from fastapi import APIRouter, Depends, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api import (add_item, household_list, join_household, list_item, member_item, shared_list, update_item,
                     valid_invite)
from app.core.auth import hash_token
from app.core.db import get_db
from app.models import Household, MealPlan, Member, ShoppingList
from app.schemas import ItemCreate, ItemUpdate

COOKIE = "essen_token"
DIR = Path(__file__).parent
templates = Jinja2Templates(DIR / "templates")
router = APIRouter(include_in_schema=False)

CHAINS = {"rewe": "Rewe", "aldi_sued": "Aldi Süd", "aldi_nord": "Aldi Nord", "lidl": "Lidl", "edeka": "Edeka",
          "kaufland": "Kaufland", "penny": "Penny", "netto_md": "Netto", "dm": "dm", "rossmann": "Rossmann"}
DAYS = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
MEALS = {"fruehstueck": "Frühstück", "mittag": "Mittag", "abend": "Abend"}

templates.env.filters["euro"] = lambda cents: f"{(cents or 0) / 100:.2f} €".replace(".", ",")
templates.env.filters["qty"] = lambda i: (f"{i.amount:g} {'Stk' if i.unit == 'stk' else i.unit}".strip()
                                          if i.amount else "")


def cookie_member(request: Request, db: Session = Depends(get_db)) -> Member | None:
    token = request.cookies.get(COOKIE, "")
    return token and db.scalar(select(Member).where(Member.token_hash == hash_token(token))) or None


def require_member(member: Member | None = Depends(cookie_member)) -> Member:
    if not member:
        raise HTTPException(401, "Nicht angemeldet")
    return member


def current_plan(db: Session, household_id: int) -> MealPlan | None:
    return db.scalar(select(MealPlan).where(MealPlan.household_id == household_id)
                     .order_by(MealPlan.id.desc()).limit(1))


def plan_days(plan: MealPlan | None) -> list[tuple[str, list]]:
    entries = plan.entries if plan else []
    return [(DAYS[day], list(es)) for day, es in groupby(entries, key=lambda e: e.day)]


def page(request: Request, name: str, status: int = 200, **ctx) -> HTMLResponse:
    return templates.TemplateResponse(request, name, {"chains": CHAINS, "meals": MEALS, **ctx}, status_code=status)


def list_partial(request: Request, lst: ShoppingList, base: str) -> HTMLResponse:
    items = sorted(lst.items, key=lambda i: (not i.chain, i.chain, i.checked, i.name.lower()))
    groups = [(CHAINS.get(c, c) or "Sonstiges", list(its)) for c, its in groupby(items, key=lambda i: i.chain)]
    return page(request, "_list.html", lst=lst, groups=groups, base=base,
                open_count=sum(not i.checked for i in lst.items))


def not_found(request: Request, text: str) -> HTMLResponse:
    return page(request, "message.html", 404, title="Link ungültig", text=text)


# --- Beitritt ---

@router.get("/join/{code}", response_class=HTMLResponse)
@router.get("/h/{code}", response_class=HTMLResponse)
def join_page(code: str, request: Request, member: Member | None = Depends(cookie_member),
              db: Session = Depends(get_db)):
    try:
        invite = valid_invite(db, code)
    except HTTPException:
        return not_found(request, "Die Einladung ist abgelaufen. Bitte frag nach einem neuen Link.")
    if member and member.household_id == invite.household_id:
        return RedirectResponse("/app", 303)
    household = db.get(Household, invite.household_id)
    return page(request, "join.html", code=code, household=household,
                days=plan_days(current_plan(db, household.id)) if request.url.path.startswith("/h/") else [])


@router.post("/app/join/{code}")
def join_submit(code: str, request: Request, member_name: str = Form(..., min_length=1, max_length=50),
                db: Session = Depends(get_db)):
    try:
        token, _ = join_household(db, code, member_name.strip() or "Gast")
    except HTTPException:
        return not_found(request, "Die Einladung ist abgelaufen. Bitte frag nach einem neuen Link.")
    response = RedirectResponse("/app", 303)
    response.set_cookie(COOKIE, token, max_age=365 * 86400, httponly=True, samesite="lax",
                        secure=request.url.scheme == "https")
    return response


# --- Haushalt: Wochenplan + Einkaufsliste ---

@router.get("/app", response_class=HTMLResponse)
def app_page(request: Request, tab: str = "plan", member: Member | None = Depends(cookie_member),
             db: Session = Depends(get_db)):
    if not member:
        return page(request, "message.html", 401, title="Nicht angemeldet",
                    text="Öffne den Einladungslink, den du bekommen hast.")
    plan = current_plan(db, member.household_id)
    lst = household_list(db, member.household_id)
    db.commit()
    return page(request, "app.html", member=member, tab="liste" if tab == "liste" else "plan", plan=plan,
                days=plan_days(plan), lst=lst)


@router.get("/app/list", response_class=HTMLResponse)
def app_list(request: Request, member: Member = Depends(require_member), db: Session = Depends(get_db)):
    lst = household_list(db, member.household_id)
    db.commit()
    return list_partial(request, lst, "/app")


@router.post("/app/items", response_class=HTMLResponse)
def app_add(request: Request, name: str = Form(..., min_length=1, max_length=100),
            member: Member = Depends(require_member), db: Session = Depends(get_db)):
    lst = household_list(db, member.household_id)
    add_item(db, lst, ItemCreate(name=name.strip() or name), member.name)
    return list_partial(request, lst, "/app")


@router.post("/app/items/{item_id}/toggle", response_class=HTMLResponse)
def app_toggle(item_id: int, request: Request, member: Member = Depends(require_member),
               db: Session = Depends(get_db)):
    item = member_item(db, member, item_id)
    update_item(db, item, ItemUpdate(checked=not item.checked), member.name)
    return list_partial(request, db.get(ShoppingList, item.list_id), "/app")


# --- Gäste: einmalige Liste ---

def guest_name(guest: str) -> str:
    return guest.strip()[:50] or "Gast"


@router.get("/l/{share_code}", response_class=HTMLResponse)
def guest_page(share_code: str, request: Request, db: Session = Depends(get_db)):
    try:
        lst = shared_list(db, share_code)
    except HTTPException:
        return not_found(request, "Diese Liste gibt es nicht mehr.")
    return page(request, "guest.html", lst=lst, base=f"/l/{lst.share_code}")


@router.get("/l/{share_code}/list", response_class=HTMLResponse)
def guest_list(share_code: str, request: Request, db: Session = Depends(get_db)):
    lst = shared_list(db, share_code)
    return list_partial(request, lst, f"/l/{lst.share_code}")


@router.post("/l/{share_code}/items", response_class=HTMLResponse)
def guest_add(share_code: str, request: Request, name: str = Form(..., min_length=1, max_length=100),
              guest: str = Form(""), db: Session = Depends(get_db)):
    lst = shared_list(db, share_code)
    add_item(db, lst, ItemCreate(name=name.strip() or name), guest_name(guest))
    return list_partial(request, lst, f"/l/{lst.share_code}")


@router.post("/l/{share_code}/items/{item_id}/toggle", response_class=HTMLResponse)
def guest_toggle(share_code: str, item_id: int, request: Request, guest: str = Form(""),
                 db: Session = Depends(get_db)):
    lst = shared_list(db, share_code)
    item = list_item(lst, item_id)
    update_item(db, item, ItemUpdate(checked=not item.checked), guest_name(guest))
    return list_partial(request, lst, f"/l/{lst.share_code}")
