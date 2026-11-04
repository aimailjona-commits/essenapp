"""Pro (19.8, E95): Abo je Haushalt über die App Store Server API, Werbe-Gutschriften über AdMob-Server-Prüfung,
Gratis-Grenzen. Mit PAYWALL aus ist alles frei (Familie/privat)."""
import base64
import logging
import time
from datetime import UTC, date, datetime, timedelta
from functools import cache
from pathlib import Path
from urllib.parse import parse_qsl

import httpx
import jwt
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import Household, MealPlan

log = logging.getLogger(__name__)
BACKEND = Path(__file__).resolve().parents[2]

FREE_PLANS_PER_WEEK = 1
PRICE = "3 € im Monat"
# Pro-Funktionen (Vorschlag C in Phase 19, Abschnitt 0); Schlüssel = was der Client in der Paywall zeigt
FEATURES = {
    "plan": "Mehr als ein KI-Plan pro Woche",
    "reroll_direction": "Neu würfeln mit Richtung oder Wunsch",
    "scan": "Kühlschrank-Foto",
    "import": "Rezepte aus Instagram und Webseiten",
    "step_images": "Bilder zu jedem Kochschritt",
    "no_mood": "„Keine Lust“-Vorschläge",
    "substitutes": "Ersatzzutaten",
    "price_alert": "Preisalarme",
}


def now_utc() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


def is_pro(h: Household) -> bool:
    return h.pro_until is not None and h.pro_until > now_utc()


def plans_this_week(db: Session, h: Household) -> int:
    monday = date.today() - timedelta(days=date.today().weekday())
    return db.scalar(select(func.count()).select_from(MealPlan).where(
        MealPlan.household_id == h.id, MealPlan.created_at >= datetime.combine(monday, datetime.min.time()))) or 0


def free_plans_left(db: Session, h: Household) -> int:
    return max(FREE_PLANS_PER_WEEK - plans_this_week(db, h), 0)


def require(db: Session, h: Household, feature: str, spend: bool = True) -> None:
    """Pro-Funktion freigeben oder 402. Ohne Abo verbraucht sie eine Werbe-Gutschrift; die Abbuchung wird mit der
    Antwort committet, ein Fehler davor bucht also nichts ab. spend=False: nur prüfen (Plan-Job bucht im Lauf)."""
    if not settings.paywall or is_pro(h):
        return
    if feature == "plan" and free_plans_left(db, h):
        return
    if h.ad_credits > 0:
        h.ad_credits -= spend
        return
    raise HTTPException(402, f"Pro: {FEATURES[feature]}")


def allowed(h: Household) -> bool:
    """Ohne Abbuchung: läuft eine Pro-Funktion im Hintergrund mit (Schritt-Bilder beim Öffnen)?"""
    return not settings.paywall or is_pro(h)


# --- App Store Server API (developer.apple.com/documentation/appstoreserverapi) ---

APPLE_HOSTS = ("https://api.storekit.itunes.apple.com", "https://api.storekit-sandbox.itunes.apple.com")


def apple_configured() -> bool:
    return bool(settings.appstore_key_path and settings.appstore_key_id and settings.appstore_issuer_id)


def apple_token() -> str:
    path = Path(settings.appstore_key_path)
    key = (path if path.is_absolute() else BACKEND / path).read_text()
    now = int(time.time())
    return jwt.encode({"iss": settings.appstore_issuer_id, "iat": now, "exp": now + 1800, "aud": "appstoreconnect-v1",
                       "bid": settings.appstore_bundle_id}, key, algorithm="ES256",
                      headers={"kid": settings.appstore_key_id, "typ": "JWT"})


def payload(jws: str) -> dict:
    # Signatur nicht geprüft: die Antwort kommt per TLS direkt von Apple auf unsere authentifizierte Anfrage
    return jwt.decode(jws, options={"verify_signature": False})


def subscription(body: dict) -> dict | None:
    """Antwort von GET /inApps/v1/subscriptions/{id} → {"until", "trial_until"} des spätesten Abos dieser App."""
    best = None
    for group in body.get("data", []):
        for last in group.get("lastTransactions", []):
            t = payload(last["signedTransactionInfo"])
            if t.get("bundleId") != settings.appstore_bundle_id or not t.get("expiresDate"):
                continue
            until = datetime.fromtimestamp(t["expiresDate"] / 1000, UTC).replace(tzinfo=None)
            if t.get("revocationDate"):  # erstattet: kein Pro
                continue
            if best is None or until > best["until"]:
                best = {"until": until, "trial_until": until if t.get("offerType") == 1 else None}
    return best


def apple_status(transaction_id: str, get=None) -> dict | None:
    """Abo-Stand bei Apple; erst Produktion, dann Sandbox (TestFlight/Entwicklung). None = unbekannt."""
    get = get or httpx.get
    headers = {"Authorization": f"Bearer {apple_token()}"}
    for host in APPLE_HOSTS:
        r = get(f"{host}/inApps/v1/subscriptions/{transaction_id}", headers=headers, timeout=10)
        if r.status_code == 404:
            continue
        r.raise_for_status()
        return subscription(r.json())
    return None


def apply(h: Household, status: dict | None) -> None:
    h.pro_until = status["until"] if status else None
    if status and status["trial_until"] != h.pro_trial_until:
        h.pro_trial_until, h.pro_trial_reminded = status["trial_until"], False
    h.pro_checked_at = now_utc()


def refresh(h: Household, get=None) -> None:
    """Abo abgelaufen und letzte Abfrage > 6 h her → bei Apple nachsehen (Verlängerung kommt so ohne Server-
    Benachrichtigungen an). Fehler nur geloggt."""
    if not (h.apple_transaction_id and apple_configured()) or is_pro(h):
        return
    if h.pro_checked_at and now_utc() - h.pro_checked_at < timedelta(hours=6):
        return
    try:
        apply(h, apple_status(h.apple_transaction_id, get))
    except httpx.HTTPError as e:
        log.warning("App Store Server API: %s", e)


# --- AdMob: Prüfung der Prämien-Rückmeldung (developers.google.com/admob/android/ssv) ---

ADMOB_KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json"


@cache
def admob_keys() -> dict[str, str]:
    # shortcut: Schlüssel bis zum Neustart gecacht; Google tauscht sie selten, sonst Cache mit Ablaufzeit
    return {str(k["keyId"]): k["pem"] for k in httpx.get(ADMOB_KEYS_URL, timeout=10).json()["keys"]}


def admob_verified(query: str, keys: dict[str, str] | None = None) -> dict[str, str] | None:
    """Rohe Query der AdMob-Rückmeldung → Parameter, wenn die Signatur stimmt. Signiert ist alles vor „&signature=“."""
    if "&signature=" not in query:
        return None
    content = query.split("&signature=", 1)[0]
    params = dict(parse_qsl(query))
    pem = (keys if keys is not None else admob_keys()).get(params.get("key_id", ""))
    if not pem:
        return None
    sig = base64.urlsafe_b64decode(params["signature"] + "==")
    key = serialization.load_pem_public_key(pem.encode())
    try:
        key.verify(sig, content.encode(), ec.ECDSA(hashes.SHA256()))
    except InvalidSignature:
        return None
    return params
