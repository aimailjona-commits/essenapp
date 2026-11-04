from datetime import date

from app.models import Offer
from app.services import planner
from app.services.matching import Matcher, fits
from app.sources.kaufda import classify
from tests.test_planner import ing, meal


def offer(i, title, chain="lidl"):
    cat, sub = classify(chain, title)
    return Offer(id=i, chain=chain, title=title, category=cat, subcategory=sub, price_cents=99, amount=500, unit="g",
                 source_id=str(i), valid_from=date.today(), valid_to=date.today())


def test_fits_rejects_wrong_product_kind():
    assert not fits("Joghurt", offer(1, "Cherrygold Käse"))
    assert not fits("Käse", offer(2, "Frischkäse Natur"))
    assert not fits("Milch", offer(3, "Kokosmilch"))
    assert fits("Joghurt", offer(4, "Naturjoghurt 3,8 %"))
    assert fits("Passierte Tomaten", offer(5, "Passata"))  # Dose statt frisch ist ok
    assert fits("Zwiebeln", offer(6, "Gemüsezwiebeln"))
    assert not fits("Kaffee", Offer(id=7, title="Kaffeemühle", category="nonfood", subcategory=""))


def test_matcher_skips_unfitting_offers():
    m = Matcher([offer(1, "Frischkäse Natur"), offer(2, "Gouda jung"), offer(3, "Sahnejoghurt")])
    assert [o.title for o in m.find("Käse")] == []  # Gouda heißt nicht „Käse“, Frischkäse ist keiner
    assert [o.title for o in m.find("Joghurt")] == ["Sahnejoghurt"]


def test_price_drops_offer_that_does_not_fit_the_ingredient():
    draft = planner.PlanDraft(meals=[meal(0, "Bowl", [ing("Joghurt", 500, offer_id=1, pack=500, price=129)])])
    p = planner.price(draft, {1: offer(1, "Cherrygold Käse")})
    assert draft.meals[0].ingredients[0].offer_id is None  # nicht mehr als Angebot verknüpft
    assert p.total_cents == 129  # Normalpreis-Schätzung der KI statt Käse-Angebot


def test_classify_unknown_asks_once_per_title_and_reuses_known(db):
    from datetime import timedelta
    from app.services.importer import Kind, Kinds, classify_unknown

    def row(i, title, cat="sonstiges", sub="", days=3):
        return Offer(chain="lidl", store_ref="", source_id=str(i), title=title, category=cat, subcategory=sub,
                     price_cents=99, valid_from=date.today() - timedelta(days=days), valid_to=date.today() + timedelta(days=days - 3))
    db.add_all([row(1, "Rama"), row(2, "Rama"), row(3, "Doppelzimmer"), row(4, "Yakult"),
                row(5, "Yakult", "kuehlung", "joghurt", days=10)])  # Yakult aus einer früheren Woche bekannt
    db.commit()
    asked = []

    def ask(prompt, schema, think=True):
        asked.append(prompt)
        lines = prompt.split("\n\n", 1)[1].splitlines()
        kinds = {"rama": "molkerei", "doppelzimmer": "nonfood"}
        return Kinds(items=[Kind(i=int(l.split("|")[0]), kind=kinds[l.split("|")[1]]) for l in lines]), {"cost_cents": 0.01}
    assert classify_unknown(db, ask) == 4
    assert len(asked) == 1 and "yakult" not in asked[0]
    got = {(o.title, o.category, o.subcategory) for o in db.query(Offer)}
    assert ("Rama", "kuehlung", "molkerei") in got and ("Doppelzimmer", "nonfood", "nonfood") in got
    assert ("Yakult", "kuehlung", "joghurt") in got
