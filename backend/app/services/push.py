"""Push über Apple Push Notification service (E52): HTTP/2 an api(.sandbox).push.apple.com, Token-Auth (JWT ES256).
Doku: developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns"""
import logging
import time
from datetime import datetime
from functools import cache
from pathlib import Path

import httpx
import jwt
from sqlalchemy.orm import object_session

from app.core.config import settings
from app.models import Member

log = logging.getLogger(__name__)
HOSTS = {"development": "https://api.sandbox.push.apple.com", "production": "https://api.push.apple.com"}
TOKEN_TTL = 50 * 60  # Apple: Token höchstens alle 20 min erneuern, spätestens nach 60 min
BACKEND = Path(__file__).resolve().parents[2]
_jwt: tuple[str, float] | None = None


def configured() -> bool:
    return bool(settings.apns_key_path and settings.apns_key_id and settings.apns_team_id)


def auth_token(now: float | None = None) -> str:
    """Provider-Token (JWT ES256, kid = Key-ID, iss = Team-ID), 50 min wiederverwendet."""
    global _jwt
    now = time.time() if now is None else now
    if _jwt is None or now - _jwt[1] >= TOKEN_TTL:
        path = Path(settings.apns_key_path)
        key = (path if path.is_absolute() else BACKEND / path).read_text()
        _jwt = (jwt.encode({"iss": settings.apns_team_id, "iat": int(now)}, key, algorithm="ES256",
                           headers={"kid": settings.apns_key_id}), now)
    return _jwt[0]


@cache
def client() -> httpx.Client:
    return httpx.Client(http2=True, timeout=10)


def payload(title: str, message: str, url: str | None, thread_id: str, category: str | None) -> dict:
    aps = {"alert": {"title": title, "body": message}, "sound": "default", "thread-id": thread_id}
    if category:
        aps["category"] = category  # Aktionen registriert die App (UNNotificationCategory)
    return {"aps": aps} | ({"url": url} if url else {})


def send(member: Member, title: str, message: str, click_url: str | None = None, thread_id: str = "essenapp",
         category: str | None = None) -> bool:
    """Sendet an alle Geräte des Mitglieds; True, wenn mindestens eins angenommen hat. Ungültige Geräte (410,
    BadDeviceToken) werden gelöscht. Fehler werden geloggt, nie geworfen: ein Push darf nichts abbrechen."""
    if not configured():
        log.warning("APNs nicht konfiguriert (APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID)")
        return False
    body, ok = payload(title, message, click_url, thread_id, category), False
    for device in list(member.devices):
        try:
            r = client().post(f"{HOSTS[device.environment]}/3/device/{device.token}", json=body, headers={
                "authorization": f"bearer {auth_token()}", "apns-topic": settings.apns_topic,
                "apns-push-type": "alert", "apns-priority": "10"})
            reason = r.json().get("reason", "") if r.content else ""
            if r.status_code == 200:
                device.last_ok, ok = datetime.now(), True
            elif r.status_code == 410 or reason == "BadDeviceToken":
                log.info("APNs: Gerät %s… von Mitglied %s ungültig (%s), gelöscht", device.token[:8], member.id,
                         reason or r.status_code)
                object_session(device).delete(device)
            else:
                log.warning("APNs-Push an Mitglied %s fehlgeschlagen: %s %s", member.id, r.status_code, reason)
        except Exception as e:
            log.warning("APNs-Push an Mitglied %s fehlgeschlagen: %s", member.id, e)
    if session := object_session(member):
        session.commit()  # last_ok / gelöschte Geräte
    return ok
