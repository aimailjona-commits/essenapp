import csv
import io
import zipfile
from types import SimpleNamespace

from sqlalchemy import select

from app.models import Food, IngredientMap, MealPlanEntry
from app.services import food_map, nutrition
from app.tools import import_usda
from tests.test_profiles_pantry import join
from tests.test_sharing import add_plan, ing

FOOD = dict(description="x", data_type="sr_legacy", sugar=0, salt=0)


def food(i, kcal, protein, carbs, fat, fiber=0):
    return SimpleNamespace(id=i, kcal=kcal, protein=protein, carbs=carbs, fat=fat, fiber=fiber)


def mapping(food_obj, gpp=None):
    return (SimpleNamespace(grams_per_piece=gpp), food_obj)


MAPS = {"reis": mapping(food(1, 360, 7, 80, 1)), "ei": mapping(food(2, 140, 12, 2, 10), gpp=55),
        "öl": mapping(food(3, 880, 0, 0, 100)), "wasser": mapping(None)}


def test_dish_per_portion_pieces_spoons_and_composition():
    ings = [{"name": "Reis", "amount": 200, "unit": "g"}, {"name": "Ei", "amount": 2, "unit": "stk"},
            {"name": "Öl", "amount": 1, "unit": "el"}, {"name": "Wasser", "amount": 400, "unit": "ml"}]
    nut, comp = nutrition.dish(ings, MAPS, portions=2)
    # Reis 720 kcal + 110 g Ei 154 kcal + 15 g Öl 132 kcal = 1006 kcal, / 2 Portionen
    assert nut == {"kcal": 503.0, "protein": 13.6, "carbs": 81.1, "fat": 14.0, "fiber": 0.0}
    assert [c["name"] for c in comp] == ["Wasser", "Reis", "Ei", "Öl"] and comp[1]["grams"] == 100
    assert abs(sum(c["share"] for c in comp) - 1) < 1e-9
    assert nutrition.dish(ings, MAPS, portions=4, scale=2)[0] == nut  # scale × doppelte Portionen
    assert nutrition.dish(ings + [{"name": "Safran", "amount": 1, "unit": "g"}], MAPS, 2) == (None, None)  # läuft noch
    assert nutrition.dish([{"name": "Zwiebel", "amount": 1, "unit": "stk"}],
                          {"zwiebel": mapping(food(4, 40, 1, 9, 0))}, 1)[0]["kcal"] == 40  # Stückgewicht fehlt: 100 g


def fdc_zip(path):
    files = {
        "food.csv": [["fdc_id", "data_type", "description", "food_category_id", "publication_date"],
                     ["1", "sr_legacy_food", "Rice, white, long-grain, raw", "20", "2019-04-01"],
                     ["2", "foundation_food", "Chicken, breast, boneless, skinless, raw", "5", "2026-04-30"],
                     ["3", "sub_sample_food", "Chicken sample 3", "5", "2026-04-30"],
                     ["4", "sr_legacy_food", "Spices, saffron", "2", "2019-04-01"]],
        "food_nutrient.csv": [["id", "fdc_id", "nutrient_id", "amount"],
                              ["1", "1", "1008", "365"], ["2", "1", "1003", "7.1"], ["3", "1", "1005", "80"],
                              ["4", "1", "1004", "0.7"], ["5", "1", "1093", "4"], ["6", "2", "2048", "120"],
                              ["7", "2", "2047", "118"], ["8", "2", "1003", "22.5"], ["9", "2", "1085", "1.9"],
                              ["10", "2", "1050", "0"], ["11", "3", "1003", "20"], ["12", "1", "1079", "1.3"],
                              ["13", "4", "1093", "148"]],
    }
    with zipfile.ZipFile(path, "w") as zf:
        for name, rows in files.items():
            buf = io.StringIO()
            csv.writer(buf).writerows(rows)
            zf.writestr(f"FoodData_Central_test/{name}", buf.getvalue())
    return path


def test_usda_parser_and_store(db, tmp_path):
    path = fdc_zip(tmp_path / "fdc.zip")
    assert import_usda.complete(path)
    foods = {f["id"]: f for f in import_usda.parse(path)}
    assert set(foods) == {1, 2}  # Teilproben und Einträge ohne kcal/Protein nicht
    assert foods[1] | {} == {"id": 1, "description": "Rice, white, long-grain, raw", "data_type": "sr_legacy",
                             "kcal": 365, "protein": 7.1, "fat": 0.7, "carbs": 80, "fiber": 1.3, "sugar": None,
                             "salt": 0.01}
    assert (foods[2]["kcal"], foods[2]["fat"], foods[2]["carbs"]) == (120, 1.9, 0)  # Ersatz-IDs (Foundation)
    assert import_usda.store(db, list(foods.values())) == 2
    assert [f.id for f in food_map.search(db, "chicken breast raw")] == [2, 1]  # alle Wörter zuerst, dann aufgefüllt
    assert [f.id for f in food_map.search(db, "rice cooked")] == [1]  # kein Treffer mit allen Wörtern → irgendeins


def test_mapping_cache_with_mocked_ai(db, tmp_path):
    assert food_map.map_missing(db, ["Reis"], ask=lambda p, s: 1 / 0) == 0  # leere food-Tabelle: nichts tun
    import_usda.store(db, import_usda.parse(fdc_zip(tmp_path / "fdc.zip")))
    calls = []

    def ask(prompt, schema):
        calls.append((schema.__name__, prompt))
        if schema is food_map.Translations:
            return schema(items=[{"name": "Basmati Reis", "query": "rice raw", "grams_per_piece": None},
                                 {"name": "Hähnchenbrust", "query": "chicken breast raw", "grams_per_piece": 150},
                                 {"name": "Zwiebeln", "query": "onion", "grams_per_piece": 90}]), {}
        return schema(items=[{"name": "Basmati Reis", "food_id": 1, "confidence": "hoch"},
                             {"name": "Hähnchenbrust", "food_id": 999, "confidence": "mittel"}]), {}  # 999 erfunden

    assert food_map.map_missing(db, ["Basmati  Reis", "Hähnchenbrust", "Zwiebeln"], ask=ask) == 3
    rows = {m.ingredient_key: m for m in db.scalars(select(IngredientMap))}
    assert (rows["basmati reis"].food_id, rows["basmati reis"].confidence) == (1, "hoch")
    assert rows["hähnchenbrust"].food_id is None  # nicht unter den Kandidaten → verworfen
    assert rows["zwiebeln"].food_id is None and rows["zwiebeln"].grams_per_piece == 100  # Tabelle vor KI
    assert rows["hähnchenbrust"].grams_per_piece == 150  # KI-Vorschlag
    assert "1|Rice, white, long-grain, raw" in calls[1][1] and "Zutat: Zwiebeln" not in calls[1][1]
    assert food_map.map_missing(db, ["basmati reis", "Zwiebeln"], ask=ask) == 0 and len(calls) == 2  # Cache


def test_plan_nutrition_per_member_with_factors(client, auth, db):
    oma = join(client, auth)
    client.patch("/me/profile", headers=auth, json={"kcal": 3000, "protein_g": 150})  # Faktor 1,5
    client.patch("/me/profile", headers=oma, json={"kcal": 2000})  # Faktor 1
    db.add_all([Food(id=1, kcal=360, protein=7, carbs=80, fat=1, fiber=0, **FOOD),
                IngredientMap(ingredient_key="reis", food_id=1, confidence="hoch")])
    add_plan(db, 1, [[ing("Reis", 500)], [ing("Reis", 250), ing("Curry", 10)]])
    e0, e1 = db.get(MealPlanEntry, 1), db.get(MealPlanEntry, 2)
    e0.portions, e0.portions_total = [{"member_id": 1, "factor": 1.5}, {"member_id": 2, "factor": 1}], 2.5
    e1.portions, e1.portions_total = [{"member_id": 1, "factor": 1.5}], 1.5
    db.commit()

    plan = client.get("/plans/current", headers=auth).json()
    assert plan["entries"][0]["recipe"]["nutrition"] == {"kcal": 720.0, "protein": 14.0, "carbs": 160.0, "fat": 2.0,
                                                         "fiber": 0.0}  # 1800 kcal / 2,5 Portionen
    assert plan["entries"][0]["recipe"]["composition"] == [{"name": "Reis", "grams": 200.0, "share": 1.0}]
    assert plan["entries"][1]["recipe"]["nutrition"] is None  # Curry noch ohne Zuordnung

    n = client.get("/plans/current/nutrition", headers=auth).json()
    day0 = {m["member_id"]: m for m in n["days"][0]["members"]}
    assert day0[1]["kcal"] == 1080 and day0[2]["kcal"] == 720 and day0[1]["complete"]
    assert not n["days"][1]["members"][0]["complete"] and n["days"][1]["members"][1]["complete"]
    assert n["members"][0] | {} == {"member_id": 1, "name": "J", "emoji": "🙂", "kcal_goal": 3000,
                                    "protein_goal": 150, "avg_kcal": 540.0, "avg_protein": 10.5}

    db.add(IngredientMap(ingredient_key="curry", food_id=None, confidence="niedrig"))  # kein Eintrag → zählt 0
    db.commit()
    n = client.get("/plans/current/nutrition", headers=auth).json()
    assert n["days"][1]["members"][0] == {"member_id": 1, "kcal": 900.0, "protein": 17.5, "carbs": 200.0,
                                          "fat": 2.5, "fiber": 0.0, "complete": True}
