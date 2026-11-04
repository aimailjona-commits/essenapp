import base64
from datetime import UTC, datetime, timedelta

import jwt
import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

from app import jobs
from app.core.config import settings
from app.models import Household, Member
from app.services import planner, pro
from tests.test_planner import ing, meal, test_plan_endpoint


@pytest.fixture
def paywall(monkeypatch):
    monkeypatch.setattr(settings, "paywall", True)


def household(db) -> Household:
    return db.query(Household).one()


def test_without_paywall_everything_is_free(client, auth, db, monkeypatch):
    test_plan_endpoint(client, auth, db, monkeypatch)
    assert client.post("/plans", headers=auth).status_code == 201
    assert client.get("/pro", headers=auth).json()["paywall"] is False


def test_free_plan_per_week_then_ad_credit_then_pro(client, auth, db, monkeypatch, paywall):
    test_plan_endpoint(client, auth, db, monkeypatch)  # der Gratis-Plan der Woche
    r = client.post("/plans", headers=auth)
    assert r.status_code == 402 and r.json()["detail"] == "Pro: Mehr als ein KI-Plan pro Woche"
    assert client.post("/plans/job", headers=auth).status_code == 402
    h = household(db)
    h.ad_credits = 1
    db.commit()
    assert client.post("/plans", headers=auth).status_code == 201  # Werbe-Gutschrift verbraucht
    assert client.get("/pro", headers=auth).json()["ad_credits"] == 0
    h.pro_until = pro.now_utc() + timedelta(days=3)
    db.commit()
    assert client.post("/plans", headers=auth).status_code == 201
    assert client.get("/pro", headers=auth).json()["pro"] is True


def test_reroll_with_direction_is_pro_plain_reroll_free(client, auth, db, monkeypatch, paywall):
    test_plan_endpoint(client, auth, db, monkeypatch)
    entry = client.get("/plans/current", headers=auth).json()["entries"][0]["id"]
    monkeypatch.setattr(planner, "ask_claude", lambda p: (planner.PlanDraft(meals=[meal(0, "Suppe", [ing("Kartoffeln", 400)])]), {}))
    assert client.post(f"/plans/current/entries/{entry}/reroll", headers=auth, json={"direction": "schneller"}).status_code == 402
    assert client.post(f"/plans/current/entries/{entry}/reroll", headers=auth).status_code == 200


def signed(payload: dict) -> str:
    return jwt.encode(payload, "x" * 32, algorithm="HS256")  # Signatur prüfen wir nicht (TLS zu Apple)


class Resp:
    def __init__(self, status, body=None):
        self.status_code, self.body = status, body

    def json(self):
        return self.body

    def raise_for_status(self):
        pass


def test_apple_status_picks_latest_and_marks_trial(monkeypatch):
    monkeypatch.setattr(pro, "apple_token", lambda: "t")
    end = datetime(2026, 12, 1, 12, tzinfo=UTC)
    body = {"data": [{"lastTransactions": [
        {"signedTransactionInfo": signed({"bundleId": "de.jsenf.essenapp", "expiresDate": int(end.timestamp() * 1000),
                                          "offerType": 1})},
        {"signedTransactionInfo": signed({"bundleId": "fremde.app", "expiresDate": int(end.timestamp() * 2000)})}]}]}
    calls = []

    def get(url, **kw):
        calls.append(url)
        return Resp(404) if "sandbox" not in url else Resp(200, body)  # nur in der Sandbox bekannt (TestFlight)
    status = pro.apple_status("123", get)
    assert status == {"until": datetime(2026, 12, 1, 12), "trial_until": datetime(2026, 12, 1, 12)}
    assert len(calls) == 2


def test_pro_apple_binds_subscription_to_one_household(client, auth, db, monkeypatch):
    monkeypatch.setattr(pro, "apple_configured", lambda: True)
    until = pro.now_utc() + timedelta(days=30)
    monkeypatch.setattr(pro, "apple_status", lambda tid, get=None: {"until": until, "trial_until": None})
    r = client.post("/pro/apple", headers=auth, json={"original_transaction_id": "2000000123"})
    assert r.status_code == 200 and r.json()["pro"] is True
    other = client.post("/households", json={"name": "B", "member_name": "X"}).json()["token"]
    r = client.post("/pro/apple", headers={"Authorization": f"Bearer {other}"},
                    json={"original_transaction_id": "2000000123"})
    assert r.status_code == 409


def admob_query(key, params: dict) -> str:
    content = "&".join(f"{k}={v}" for k, v in params.items())
    sig = key.sign(content.encode(), ec.ECDSA(hashes.SHA256()))
    return f"{content}&signature={base64.urlsafe_b64encode(sig).decode().rstrip('=')}&key_id=7"


def test_admob_reward_credits_once_with_valid_signature(client, auth, db, monkeypatch):
    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    monkeypatch.setattr(pro, "admob_keys", lambda: {"7": pem.decode()})
    hid = household(db).id
    q = admob_query(key, {"ad_network": "5450213213286189855", "transaction_id": "abc", "user_id": hid})
    assert client.get(f"/pro/admob?{q}").status_code == 200
    assert client.get(f"/pro/admob?{q}").status_code == 200  # Google wiederholt: nur einmal gutschreiben
    assert client.get("/pro", headers=auth).json()["ad_credits"] == 1
    assert client.get(f"/pro/admob?{q.replace('abc', 'abd')}").status_code == 403  # verändert → Signatur falsch


def test_trial_reminder_once_two_days_before_end(client, auth, db, monkeypatch):
    calls = []
    monkeypatch.setattr(jobs.push, "send", lambda m, title, message, **kw: calls.append(message) or True)
    h = household(db)
    for m in db.query(Member):
        m.push_enabled = True
    now = datetime(2026, 11, 4, 10, tzinfo=jobs.BERLIN)
    h.pro_trial_until = jobs.utc(now + timedelta(days=1, hours=20))
    db.commit()
    assert jobs.run(db, "trial_reminder", now).info == "1 Haushalte, 1 Pushes"
    assert "endet am 06.11. um 06:00 Uhr" in calls[0] and "3 € im Monat" in calls[0]
    assert jobs.run(db, "trial_reminder", now).info == "0 Haushalte, 0 Pushes"
