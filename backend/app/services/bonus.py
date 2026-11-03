"""Payback & Rewe Bonus (38), Rewe-Bonus-Aktionen (39), Drogerie-Coupons (59): Coupon-Foto lesen (Haiku), Coupons
den Angeboten/Artikeln zuordnen, Effektivpreise für Planner/Pricing. Keine Logins bei Payback/Rewe (A7)."""
import base64
import re
from collections.abc import Callable
from datetime import date

from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import BonusEntry, Coupon, Offer
from app.services import food_map
from app.services.matching import words
from app.services.normalize import cents

PROGRAMS = {"payback": "Payback", "rewe_bonus": "Rewe Bonus"}  # Konten (38b): Payback in °P, Rewe Bonus in Cent
POINT_CENTS = 1  # 1 °P ≈ 1 Cent
POINT_RATE = 0.005  # Grundpunkte: 1 °P je 2 € Umsatz → 10fach = 10 × 0,5 % (Spezifikation 38c)
PARTNERS = {"rewe": "rewe", "edeka": "edeka", "marktkauf": "edeka", "penny": "penny", "lidl": "lidl",
            "kaufland": "kaufland", "netto": "netto_md", "dm": "dm", "rossmann": "rossmann", "aldi süd": "aldi_sued",
            "aldi nord": "aldi_nord"}


def chain_of(partner: str) -> str:
    """„dm-drogerie markt“ → dm, „REWE“ → rewe; unbekannte Partner (z.B. Aral) → ""."""
    text = " ".join(re.findall(r"\w+", partner.lower()))
    return next((c for k, c in PARTNERS.items() if re.search(rf"\b{k}\b", text)), "")


# --- Coupon-Foto (38a) ---

class CouponRead(BaseModel):
    partner: str
    program: str  # payback | rewe_bonus | dm | rossmann | sonstige
    product: str
    category: str
    benefit: str
    multiplier: int | None
    bonus_cents: int | None
    percent: int | None
    min_spend_cents: int | None
    valid_until: str | None  # YYYY-MM-DD


SCAN = """Das Foto zeigt einen Coupon (Payback, REWE Bonus, dm, Rossmann o.ä.) aus Deutschland. Lies ab:
- partner: Händler, bei dem der Coupon gilt (z.B. „dm“, „REWE“, „Edeka“, „Aral“).
- program: payback (Payback-Coupon), rewe_bonus (REWE Bonus), dm, rossmann (App-Coupons dieser Händler) oder sonstige.
- product: Produkt oder Marke, für das der Coupon gilt (z.B. „Kaffee“, „Balea Shampoo“); "" = ganzer Einkauf.
- category: eine von fleisch_fisch, obst_gemuese, kuehlung, vorrat, getraenke, drogerie, haushalt, sonstiges, wenn der
  Coupon für eine ganze Warengruppe gilt (z.B. „auf Obst & Gemüse“ → obst_gemuese), sonst "".
- benefit: Vorteil kurz wie aufgedruckt, z.B. „10fach Punkte“, „0,50 € Bonus“, „20 % Rabatt“.
- multiplier: bei „Xfach Punkte“ die Zahl X, sonst null. bonus_cents: fester Betrag in Cent (Bonus/Rabatt), sonst null.
  percent: Prozent-Rabatt, sonst null. min_spend_cents: Mindestumsatz in Cent, sonst null.
- valid_until: letzter Gültigkeitstag als YYYY-MM-DD (Jahr {year}, wenn keins dasteht), sonst null.
Nichts erfinden: Unleserliches leer bzw. null lassen."""
CATEGORIES = {"fleisch_fisch", "obst_gemuese", "kuehlung", "vorrat", "getraenke", "drogerie", "haushalt", "sonstiges"}


def scan(image: bytes, ask: Callable | None = None, today: date | None = None) -> tuple[dict, dict]:
    """JPEG → Coupon-Felder (nicht gespeichert; die App zeigt sie zum Prüfen, dann POST /coupons)."""
    ask = ask or food_map.ask_claude
    today = today or date.today()
    read, usage = ask([{"type": "image", "source": {"type": "base64", "media_type": "image/jpeg",
                                                    "data": base64.b64encode(image).decode()}},
                       {"type": "text", "text": SCAN.format(year=today.year)}], CouponRead)
    try:
        until = date.fromisoformat(read.valid_until) if read.valid_until else None
    except ValueError:
        until = None

    def amount(v, hi):
        return v if v is not None and 0 < v <= hi else None
    program = read.program if read.program in (*PROGRAMS, "dm", "rossmann") else "sonstige"
    return {"partner": read.partner.strip()[:50], "program": program, "chain": chain_of(read.partner),
            "product": read.product.strip()[:100], "category": read.category if read.category in CATEGORIES else "",
            "benefit": read.benefit.strip()[:100], "multiplier": amount(read.multiplier, 100),
            "bonus_cents": amount(read.bonus_cents, 100000), "percent": amount(read.percent, 100),
            "min_spend_cents": amount(read.min_spend_cents, 1000000), "valid_until": until}, usage


# --- Zuordnung + Effektivpreis (38c, 39, 59) ---

def active(db: Session, household_id: int, today: date | None = None) -> list[Coupon]:
    today = today or date.today()
    return list(db.scalars(select(Coupon).where(Coupon.household_id == household_id).where(
        (Coupon.valid_until.is_(None)) | (Coupon.valid_until >= today)).order_by(Coupon.valid_until, Coupon.id)))


def badge(c: Coupon) -> str:
    """Badge am Artikel: „🎟 10fach“, „🎟 0,50 €“, „🎟 −20 %“."""
    if c.multiplier:
        return f"🎟 {c.multiplier}fach"
    if c.bonus_cents:
        return f"🎟 {c.bonus_cents / 100:.2f} €".replace(".", ",")
    if c.percent:
        return f"🎟 −{c.percent} %"
    return "🎟 Coupon"


def _has(title_words: set[str], w: str) -> bool:
    return any(t == w or (len(w) >= 4 and t.endswith(w)) for t in title_words)


def name_fits(c: Coupon, name: str, category: str = "") -> bool:
    """Produkt-Coupon: alle Wörter des Produkts im Namen (Komposita über das Wortende, „Kaffee“ ~ „Röstkaffee“);
    Kategorie-Coupon: gleiche Kategorie; ohne beides gilt er für den ganzen Einkauf."""
    if c.product:
        want = words(c.product)
        have = set(words(name)) | set(re.findall(r"\w+", name.lower()))
        return bool(want) and all(_has(have, w) for w in want)
    if c.category:
        return c.category == category
    return True


def fits_offer(c: Coupon, o: Offer) -> bool:
    return (not c.chain or c.chain == o.chain) and name_fits(c, f"{o.title} {o.brand}", o.category)


def discount(c: Coupon, price_cents: int) -> int:
    """Vorteil in Cent für eine Packung: Xfach Punkte = X × 0,5 % (1 °P ≈ 1 ct je 2 €), fester Betrag, Prozent.
    shortcut: Mindestumsatz wird nur angezeigt, nicht geprüft (Wocheneinkauf liegt meist darüber)."""
    if c.multiplier:
        return cents(price_cents * c.multiplier * POINT_RATE)
    if c.bonus_cents:
        return min(c.bonus_cents, price_cents)
    if c.percent:
        return cents(price_cents * c.percent / 100)
    return 0


def apply(offers: list[Offer], coupons: list[Coupon]) -> list[Offer]:
    """Angebote mit Effektivpreis für Planner/Pricing: Rewe-Bonus (39) und passende Coupons wirken wie Rabatt.
    Geänderte Angebote werden als nicht gespeicherte Kopie geliefert (price_cents = Effektivpreis, Streichpreis =
    bisheriger Preis, falls keiner da war → zählt als Ersparnis; badge = Text fürs Prompt)."""
    out = []
    for o in offers:
        off, tags = o.bonus_cents or 0, [f"🎁 {o.bonus_cents / 100:.2f} € Bonus".replace(".", ",")] if o.bonus_cents else []
        for c in coupons:
            if fits_offer(c, o) and (d := discount(c, o.price_cents)):
                off += d
                tags.append(badge(c))
        if not off:
            out.append(o)
            continue
        copy = Offer(**{col.key: getattr(o, col.key) for col in Offer.__table__.columns})
        copy.price_cents = max(o.price_cents - off, 0)
        copy.regular_price_cents = o.regular_price_cents or o.price_cents
        if o.base_price_cents:
            copy.base_price_cents = cents(o.base_price_cents * copy.price_cents / o.price_cents) if o.price_cents else 0
        copy.badge = " ".join(tags)
        out.append(copy)
    return out


def item_coupon(coupons: list[Coupon], name: str, chain: str, offer: Offer | None) -> Coupon | None:
    """Coupon für einen Listenartikel bzw. Merklisten-Eintrag (59): über das Angebot, sonst über den Namen; Artikel
    ohne Laden bekommen den Coupon jedes Ladens."""
    for c in coupons:
        if offer is not None and fits_offer(c, offer):
            return c
        if (c.product or c.category) and (not chain or not c.chain or c.chain == chain) and name_fits(c, name):
            return c
    return None


# --- Konten (38b) ---

def value_cents(program: str, amount: int) -> int:
    return amount * POINT_CENTS if program == "payback" else amount


def accounts(db: Session, household_id: int, since: date | None = None) -> list[dict]:
    """Kontostand je Programm + „Heute bekommen“-Summe (Ersparnis „Bonus“) seit since (Standard: Monatsanfang)."""
    since = since or date.today().replace(day=1)
    rows = list(db.scalars(select(BonusEntry).where(BonusEntry.household_id == household_id)))
    out = []
    for program, name in PROGRAMS.items():
        mine = [r for r in rows if r.program == program]
        balance = sum(r.delta for r in mine)
        earned = sum(r.delta for r in mine if r.kind == "plus" and r.created_at.date() >= since)
        out.append({"program": program, "name": name, "unit": "punkte" if program == "payback" else "cent",
                    "balance": balance, "value_cents": value_cents(program, balance),
                    "earned_month_cents": value_cents(program, earned)})
    return out


def earned_cents(db: Session, household_id: int, start: date, end: date) -> int:
    """Gutgeschriebener Bonus (kind plus) in [start, end) als Cent – Spalte „Bonus“ in Dashboard/Erfolgen."""
    rows = db.scalars(select(BonusEntry).where(BonusEntry.household_id == household_id, BonusEntry.kind == "plus"))
    return sum(value_cents(r.program, r.delta) for r in rows if start <= r.created_at.date() < end)


def days_left(c: Coupon, today: date | None = None) -> int | None:
    return (c.valid_until - (today or date.today())).days if c.valid_until else None


def expiry_text(c: Coupon, today: date | None = None) -> str:
    """„Dein Payback-Coupon für Kaffee läuft übermorgen ab“."""
    left = days_left(c, today)
    when = {0: "heute", 1: "morgen", 2: "übermorgen"}.get(left, f"in {left} Tagen") if left is not None else "bald"
    kind = {"payback": "Payback-", "rewe_bonus": "Rewe-Bonus-"}.get(c.program, f"{c.partner}-" if c.partner else "")
    return f"🎟 Dein {kind}Coupon für {c.product or c.benefit or 'deinen Einkauf'} läuft {when} ab"
