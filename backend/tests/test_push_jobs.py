"""Apple Push (E52) + lokaler Scheduler (E47)."""
import secrets
from datetime import date, datetime

from types import SimpleNamespace

import httpx
import jwt
import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import jobs
from app.core.config import settings
from app.jobs import BERLIN
from app.models import Household, JobRun, MealPlan, Member, PushDevice, PushOutbox
from app.services import push

PROMPT = "🍽️ Neue Woche – sollen wir deinen Plan für KW 46 erstellen?"


def at(day: int, hhmm: str) -> datetime:
    """November 2026: 4/11/18 = Mi, 7 = Sa, 8 = So, 9 = Mo."""
    h, m = map(int, hhmm.split(":"))
    return datetime(2026, 11, day, h, m, tzinfo=BERLIN)


def member(db, role="owner", household=None, **kw) -> Member:
    m = Member(household=household or Household(name="T", plz="50667"), name="J", token_hash=secrets.token_hex(32),
               role=role, **kw)
    db.add(m)
    db.commit()
    return m


def runs(db, name=None) -> list[JobRun]:
    q = select(JobRun).order_by(JobRun.id)
    return list(db.scalars(q.where(JobRun.name == name) if name else q))


@pytest.fixture
def sent(monkeypatch):
    calls = []
    monkeypatch.setattr(push, "send", lambda m, title, message, **kw: calls.append((m.id, message, kw)) or True)
    return calls


@pytest.fixture
def imports(monkeypatch):
    calls = []
    monkeypatch.setattr(jobs, "refresh_household", lambda db, h: calls.append(h.id) or 42)
    return calls


# --- Fälligkeit ---

def test_last_slot():
    spec = "Sa 22:00, Mo 06:00, Mi 06:00"
    assert jobs.last_slot(spec, at(7, "22:00")) == at(7, "22:00")
    assert jobs.last_slot(spec, at(7, "21:59")) == at(4, "06:00")
    assert jobs.last_slot(spec, at(9, "05:59")) == at(7, "22:00")
    assert jobs.last_slot("täglich 09:00", at(9, "08:00")) == at(8, "09:00")
    assert jobs.last_slot("So 18:00", at(8, "18:30")) == at(8, "18:00")
    with pytest.raises(ValueError):
        jobs.last_slot("Xy 09:00", at(8, "10:00"))


def test_import_runs_once_per_slot_also_after_restart(db, imports, sent):
    h = member(db).household
    jobs.tick(db, at(7, "21:59"))
    assert runs(db) == [] and imports == []
    jobs.tick(db, at(7, "22:00"))
    assert [r.name for r in runs(db)] == ["import_offers", "price_history", "watch_alarms", "product_facts"]
    assert imports == [h.id] and runs(db)[0].ok and runs(db)[0].info == f"{h.id}: 42"
    assert runs(db, "price_history")[0].info == "0 Preispunkte aus 0 Angeboten"
    jobs.tick(db, at(7, "22:01"))
    with Session(db.get_bind()) as fresh:  # Neustart: neue Sitzung, job_run bleibt
        jobs.tick(fresh, at(7, "23:00"))
    assert imports == [h.id]
    jobs.tick(db, at(9, "06:00"))
    assert imports == [h.id, h.id] and len(runs(db, "import_offers")) == 2
    assert [r.name for r in runs(db, "achievements")] == ["achievements"]  # täglich 03:00, nachgeholt


def test_catch_up_window_and_failures_are_not_retried(db, sent, monkeypatch):
    member(db)
    assert jobs.due(db, "import_offers", at(7, "22:00"), at(8, "09:59"))
    assert not jobs.due(db, "import_offers", at(7, "22:00"), at(8, "10:01"))  # > 12 h: nicht mehr nachholen
    assert not jobs.due(db, "reinstall_reminder", None, at(8, "10:00"))

    def blocked(db, h):
        raise RuntimeError("kaufDA blockt (403)")
    monkeypatch.setattr(jobs, "refresh_household", blocked)
    jobs.tick(db, at(7, "22:00"))
    jobs.tick(db, at(7, "22:01"))
    (run,) = runs(db, "import_offers")
    assert not run.ok and "kaufDA blockt" in run.info


def test_schedule_override_and_manual_run(db, imports, sent, monkeypatch):
    member(db)
    monkeypatch.setattr(settings, "job_schedules", {"import_offers": "Di 10:00"})
    jobs.tick(db, at(7, "22:00"))
    assert imports == []
    jobs.tick(db, datetime(2026, 11, 10, 10, 0, tzinfo=BERLIN))
    assert len(imports) == 1
    r = jobs.run(db, "coupon_expiry", at(8, "12:00"))
    assert r.ok and r.info == "Platzhalter, wartet auf Phase 13 (38 Payback & Rewe Bonus)"


# --- Ruhezeiten ---

def test_quiet_hours():
    q = {"start": "22:00", "end": "07:00"}
    assert jobs.quiet_end(q, at(8, "21:59")) is None
    assert jobs.quiet_end(q, at(8, "23:30")) == at(9, "07:00")
    assert jobs.quiet_end(q, at(9, "06:59")) == at(9, "07:00")
    assert jobs.quiet_end(q, at(9, "07:00")) is None
    assert jobs.quiet_end({"start": "13:00", "end": "15:00"}, at(9, "14:00")) == at(9, "15:00")
    assert jobs.quiet_end(None, at(9, "03:00")) is None


def test_notify_defers_quiet_hours_to_outbox_and_respects_push_enabled(db, sent):
    m = member(db)
    assert jobs.notify(m, at(8, "12:00"), "T", "a") and len(sent) == 1
    assert jobs.notify(m, at(8, "23:00"), "T", "b", click_url="essenapp://start", thread_id="x")
    assert len(sent) == 1  # Ruhezeit: wartet bis 07:00
    (row,) = db.scalars(select(PushOutbox)).all()
    assert (row.message, row.send_at, row.thread_id) == ("b", jobs.utc(at(9, "07:00")), "x")
    jobs.tick(db, at(9, "06:59"))
    assert len(sent) == 1
    jobs.tick(db, at(9, "07:00"))
    assert sent[-1] == (m.id, "b", {"click_url": "essenapp://start", "thread_id": "x", "category": None})
    assert db.scalars(select(PushOutbox)).all() == []
    m.push_enabled = False
    assert not jobs.notify(m, at(8, "12:00"), "T", "c") and len(sent) == 2


# --- Plan-Erinnerung (17) ---

def test_plan_prompt_with_reminders(db, sent):
    m = member(db)
    jobs.tick(db, at(8, "17:59"))
    assert sent == []
    jobs.tick(db, at(8, "18:00"))
    (member_id, message, kw), = sent
    assert (member_id, message, kw) == (m.id, PROMPT, {"click_url": "essenapp://generator", "thread_id": "plan",
                                                       "category": "PLAN_PROMPT"})
    jobs.tick(db, at(8, "19:59"))
    assert len(sent) == 1
    jobs.tick(db, at(8, "20:00"))  # 1. Erinnerung
    jobs.tick(db, at(8, "22:00"))  # 2. Erinnerung, in der Ruhezeit → wird um 07:00 gesendet
    assert len(sent) == 2
    jobs.tick(db, at(9, "00:00"))
    jobs.tick(db, at(9, "07:00"))
    assert len(sent) == 3 and sent[-1][1] == PROMPT  # max. 2×
    assert [r.info for r in runs(db, f"plan_prompt:{m.id}")] == ["KW 46"] * 3


def test_plan_prompt_stops_when_plan_created_and_follows_settings(db, sent, imports):
    m = member(db)
    jobs.tick(db, at(8, "18:00"))
    db.add(MealPlan(household_id=m.household_id, week="2026-W46", created_at=jobs.utc(at(8, "18:30"))))
    db.commit()
    jobs.tick(db, at(8, "20:00"))
    assert len(sent) == 1

    m.plan_prompt_weekday, m.plan_prompt_time = 2, "07:30"
    db.commit()
    jobs.tick(db, at(11, "07:29"))
    jobs.tick(db, at(11, "07:30"))  # Mittwoch → laufende KW
    assert len(sent) == 2 and sent[-1][1] == PROMPT
    m.plan_prompt_enabled = False
    db.commit()
    jobs.tick(db, at(18, "07:30"))
    assert len(sent) == 2


# --- Neu-Installations-Erinnerung (E2) ---

def test_reinstall_reminder(db, sent, monkeypatch):
    owner = member(db, plan_prompt_enabled=False)
    member(db, role="member", household=owner.household, plan_prompt_enabled=False)
    jobs.tick(db, at(8, "18:00"))
    assert sent == []  # ohne REINSTALL_BASE
    monkeypatch.setattr(settings, "reinstall_base", date(2026, 11, 2))
    assert jobs.reinstall_slot(at(8, "17:59")) is None
    assert jobs.reinstall_slot(at(8, "18:00")) == at(8, "18:00")
    assert jobs.reinstall_slot(at(14, "17:59")) == at(8, "18:00")
    assert jobs.reinstall_slot(at(14, "18:00")) == at(14, "18:00")
    jobs.tick(db, at(8, "18:00"))
    jobs.tick(db, at(8, "18:05"))
    assert [(i, msg) for i, msg, _ in sent] == [(owner.id, "App neu installieren (7-Tage-Signatur)")]
    assert runs(db, "reinstall_reminder")[0].info == "1/1 gesendet"


# --- push.send (APNs) ---

@pytest.fixture
def apns(monkeypatch, tmp_path):
    """Echter ES256-Schlüssel in tmp, gemockter HTTP/2-Client; antwortet mit replies (Status, reason)."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    key = ec.generate_private_key(ec.SECP256R1())
    (tmp_path / "AuthKey.p8").write_bytes(key.private_bytes(serialization.Encoding.PEM,
                                                            serialization.PrivateFormat.PKCS8,
                                                            serialization.NoEncryption()))
    monkeypatch.setattr(settings, "apns_key_path", str(tmp_path / "AuthKey.p8"))
    monkeypatch.setattr(settings, "apns_key_id", "KEY123")
    monkeypatch.setattr(settings, "apns_team_id", "TEAM456")
    monkeypatch.setattr(push, "_jwt", None)
    calls, replies = [], []

    class Client:
        def post(self, url, json, headers):
            calls.append((url, json, headers))
            status, reason = replies.pop(0) if replies else (200, "")
            if status == 0:
                raise httpx.ConnectError("offline")
            return httpx.Response(status, json={"reason": reason} if reason else None,
                                  request=httpx.Request("POST", url))
    monkeypatch.setattr(push, "client", lambda: Client())
    return SimpleNamespace(key=key, calls=calls, replies=replies)


def device_member(db, *tokens):
    m = member(db)
    m.devices = [PushDevice(token=t, environment=env) for t, env in tokens]
    db.commit()
    return m


def test_jwt_es256_cached_50_minutes(apns):
    token = push.auth_token(now=1_000_000)
    claims = jwt.decode(token, apns.key.public_key(), algorithms=["ES256"])
    assert claims == {"iss": "TEAM456", "iat": 1_000_000}
    assert jwt.get_unverified_header(token) == {"alg": "ES256", "kid": "KEY123", "typ": "JWT"}
    assert push.auth_token(now=1_000_000 + 49 * 60) == token
    assert push.auth_token(now=1_000_000 + 50 * 60) != token


def test_send_payload_headers_and_environments(db, apns):
    m = device_member(db, ("a" * 64, "development"), ("b" * 64, "production"))
    assert push.send(m, "Titel", "Text", click_url="essenapp://start", thread_id="plan", category="PLAN_PROMPT")
    (url1, body, headers), (url2, _, _) = apns.calls
    assert url1 == "https://api.sandbox.push.apple.com/3/device/" + "a" * 64
    assert url2 == "https://api.push.apple.com/3/device/" + "b" * 64
    assert body == {"aps": {"alert": {"title": "Titel", "body": "Text"}, "sound": "default", "thread-id": "plan",
                            "category": "PLAN_PROMPT"}, "url": "essenapp://start"}
    assert headers == {"authorization": f"bearer {push.auth_token()}", "apns-topic": "de.jsenf.essenapp",
                       "apns-push-type": "alert", "apns-priority": "10"}
    assert all(d.last_ok for d in m.devices)
    assert push.send(m, "T", "M") and apns.calls[-1][1] == {"aps": {"alert": {"title": "T", "body": "M"},
                                                                    "sound": "default", "thread-id": "essenapp"}}


def test_send_removes_invalid_devices_and_never_raises(db, apns, caplog):
    m = device_member(db, ("a" * 64, "production"), ("b" * 64, "production"), ("c" * 64, "production"))
    apns.replies.extend([(410, "Unregistered"), (400, "BadDeviceToken"), (500, "InternalServerError")])
    assert push.send(m, "T", "M") is False
    assert [d.token for d in db.scalars(select(PushDevice))] == ["c" * 64]
    apns.replies.append((0, ""))  # Netzwerkfehler
    assert push.send(m, "T", "M") is False
    assert "InternalServerError" in caplog.text and "offline" in caplog.text


def test_send_without_config(db, monkeypatch, caplog):
    monkeypatch.setattr(settings, "apns_key_path", "")
    m = device_member(db, ("a" * 64, "production"))
    assert push.send(m, "T", "M") is False and "APNs nicht konfiguriert" in caplog.text


# --- Endpunkte ---

def test_device_endpoints_and_test_push(client, auth, db, monkeypatch):
    token_b = client.post("/households", json={"name": "B", "member_name": "B"}).json()["token"]
    other = {"Authorization": f"Bearer {token_b}"}
    tok = "AB" * 32
    assert client.post("/me/push/test", headers=auth).status_code == 422  # kein Gerät
    body = {"token": tok, "environment": "development"}
    assert client.post("/me/push/device", headers=auth, json=body).status_code == 204
    assert client.post("/me/push/device", headers=other, json=body | {"environment": "production"}).status_code == 204
    (d,) = db.scalars(select(PushDevice)).all()
    assert (d.token, d.member_id, d.environment) == (tok.lower(), 2, "production")  # Gerät wechselt das Mitglied
    for bad in ({"token": "xyz", "environment": "production"}, {"token": tok, "environment": "prod"}):
        assert client.post("/me/push/device", headers=auth, json=bad).status_code == 422
    assert client.delete(f"/me/push/device/{tok}", headers=auth).status_code == 404  # gehört B
    client.post("/me/push/device", headers=auth, json=body)

    calls = []
    monkeypatch.setattr(push, "send", lambda m, title, message, **kw: calls.append((m.id, kw)) or True)
    assert client.post("/me/push/test", headers=auth).status_code == 204
    assert calls == [(1, {"click_url": "essenapp://start", "thread_id": "test"})]
    monkeypatch.setattr(push, "send", lambda *a, **kw: False)
    assert client.post("/me/push/test", headers=auth).status_code == 502
    assert client.delete(f"/me/push/device/{tok}", headers=auth).status_code == 204
    assert client.get("/me/push", headers=auth).status_code == 404  # ntfy-Endpunkt entfernt


def test_push_settings(client, auth):
    assert client.get("/me/push/settings", headers=auth).json() == {
        "push_enabled": True, "plan_prompt_enabled": True, "plan_prompt_weekday": 6, "plan_prompt_time": "18:00",
        "quiet_hours": {"start": "22:00", "end": "07:00"}, "lunchbox_push": None}
    r = client.patch("/me/push/settings", headers=auth, json={
        "plan_prompt_weekday": 0, "plan_prompt_time": "07:30", "push_enabled": False, "plan_prompt_enabled": None})
    assert r.status_code == 200, r.text
    assert r.json() == {"push_enabled": False, "plan_prompt_enabled": True, "plan_prompt_weekday": 0,
                        "plan_prompt_time": "07:30", "quiet_hours": {"start": "22:00", "end": "07:00"},
                        "lunchbox_push": None}
    assert client.patch("/me/push/settings", headers=auth, json={"lunchbox_push": "20:00"}).json()["lunchbox_push"] == "20:00"
    assert client.patch("/me/push/settings", headers=auth, json={"lunchbox_push": None}).json()["lunchbox_push"] is None
    r = client.patch("/me/push/settings", headers=auth, json={"quiet_hours": None})
    assert r.json()["quiet_hours"] is None and r.json()["plan_prompt_time"] == "07:30"
    client.patch("/me/push/settings", headers=auth, json={"quiet_hours": {"start": "23:00", "end": "06:30"}})
    assert client.get("/me/push/settings", headers=auth).json()["quiet_hours"] == {"start": "23:00", "end": "06:30"}
    for bad in ({"plan_prompt_weekday": 7}, {"plan_prompt_time": "24:00"}, {"plan_prompt_time": "7:30"},
                {"quiet_hours": {"start": "22:00"}}, {"quiet_hours": {"start": "22:00", "end": "7"}}):
        assert client.patch("/me/push/settings", headers=auth, json=bad).status_code == 422, bad
