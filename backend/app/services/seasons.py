"""Feiertags- & Saison-Specials (25): deutsche Feiertage (bundesweit + Bundesland aus der PLZ), Anlässe, Saisons,
Saisonkalender Obst/Gemüse. Alles im Code, keine KI."""
from dataclasses import dataclass
from datetime import date, timedelta

BANNER_DAYS = 14

# Bundesland aus dem PLZ-Leitbereich (2 Ziffern), Ausnahmen über 3 Ziffern.
# shortcut: PLZ-Bereiche folgen nicht exakt den Landesgrenzen, an Grenzen evtl. falsch; bei Bedarf amtliche Tabelle
PLZ2 = {
    **dict.fromkeys(["01", "02", "04", "08", "09"], "SN"), "03": "BB", "06": "ST", "07": "TH",
    **dict.fromkeys(["10", "11", "12", "13"], "BE"), **dict.fromkeys(["14", "15", "16"], "BB"),
    **dict.fromkeys(["17", "18", "19"], "MV"), "20": "HH", "21": "NI", "22": "HH",
    **dict.fromkeys(["23", "24", "25"], "SH"), **dict.fromkeys(["26", "27", "29", "30", "31", "37", "38", "49"], "NI"),
    "28": "HB", **dict.fromkeys(["32", "33", "40", "41", "42", "44", "45", "46", "47", "48", "50", "51", "52", "53",
                                 "57", "58", "59"], "NW"),
    **dict.fromkeys(["34", "35", "36", "60", "61", "63", "64", "65"], "HE"), "39": "ST",
    **dict.fromkeys(["54", "55", "56", "67"], "RP"), "66": "SL",
    **dict.fromkeys(["68", "69", "70", "71", "72", "73", "74", "75", "76", "77", "78", "79", "88", "89"], "BW"),
    **dict.fromkeys(["80", "81", "82", "83", "84", "85", "86", "87", "90", "91", "92", "93", "94", "95", "96", "97"],
                    "BY"),
    **dict.fromkeys(["98", "99"], "TH"),
}
PLZ3 = {"046": "TH", "049": "BB", "172": "BB", "173": "BB", "193": "BB", "210": "HH", "211": "HH", "215": "SH",
        "228": "SH", "229": "SH", "239": "MV", "275": "HB", "276": "HB", "287": "NI", "288": "NI",
        **dict.fromkeys(["364", "365", "366", "367", "368", "369"], "TH"), "372": "HE", "373": "TH",
        "388": "ST", "389": "ST", "575": "RP", "576": "RP", "637": "BY", "638": "BY", "639": "BY",
        "668": "RP", "669": "RP", "685": "HE", "686": "HE", "881": "BY", "892": "BY", "893": "BY", "894": "BY"}
STATES = {"BW": "Baden-Württemberg", "BY": "Bayern", "BE": "Berlin", "BB": "Brandenburg", "HB": "Bremen",
          "HH": "Hamburg", "HE": "Hessen", "MV": "Mecklenburg-Vorpommern", "NI": "Niedersachsen",
          "NW": "Nordrhein-Westfalen", "RP": "Rheinland-Pfalz", "SL": "Saarland", "SN": "Sachsen",
          "ST": "Sachsen-Anhalt", "SH": "Schleswig-Holstein", "TH": "Thüringen"}


def state(plz: str) -> str | None:
    """Kürzel des Bundeslands (z.B. "NW") oder None ohne gültige PLZ."""
    if len(plz or "") != 5 or not plz.isdigit():
        return None
    return PLZ3.get(plz[:3]) or PLZ2.get(plz[:2])


def easter(year: int) -> date:
    """Ostersonntag (gregorianisch, anonymer Algorithmus nach Meeus/Jones/Butcher)."""
    a, b, c = year % 19, year // 100, year % 100
    d, e = b // 4, b % 4
    g = (8 * b + 13) // 25
    h = (19 * a + b - d - g + 15) % 30
    i, k = c // 4, c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month, day = divmod(h + l - 7 * m + 114, 31)
    return date(year, month, day + 1)


def holidays(year: int, st: str | None = None) -> dict[date, str]:
    """Gesetzliche Feiertage: bundesweit + die des Bundeslands (nur landesweite, nicht einzelne Gemeinden)."""
    e = easter(year)
    days = {date(year, 1, 1): "Neujahr", e - timedelta(2): "Karfreitag", e + timedelta(1): "Ostermontag",
            date(year, 5, 1): "Tag der Arbeit", e + timedelta(39): "Christi Himmelfahrt",
            e + timedelta(50): "Pfingstmontag", date(year, 10, 3): "Tag der Deutschen Einheit",
            date(year, 12, 25): "1. Weihnachtstag", date(year, 12, 26): "2. Weihnachtstag"}
    regional = [
        (("BW", "BY", "ST"), date(year, 1, 6), "Heilige Drei Könige"),
        (("BE", "MV"), date(year, 3, 8), "Frauentag"),
        (("BB",), e, "Ostersonntag"), (("BB",), e + timedelta(49), "Pfingstsonntag"),
        (("BW", "BY", "HE", "NW", "RP", "SL"), e + timedelta(60), "Fronleichnam"),
        (("SL",), date(year, 8, 15), "Mariä Himmelfahrt"),
        (("TH",), date(year, 9, 20), "Weltkindertag"),
        (("BB", "HB", "HH", "MV", "NI", "SN", "ST", "SH", "TH"), date(year, 10, 31), "Reformationstag"),
        (("BW", "BY", "NW", "RP", "SL"), date(year, 11, 1), "Allerheiligen"),
        (("SN",), date(year, 11, 22) - timedelta((date(year, 11, 22).weekday() - 2) % 7), "Buß- und Bettag"),
    ]
    days |= {d: name for states, d, name in regional if st in states}
    return dict(sorted(days.items()))


def mothers_day(year: int) -> date:
    may1 = date(year, 5, 1)
    return may1 + timedelta((6 - may1.weekday()) % 7 + 7)  # 2. Sonntag im Mai


@dataclass(frozen=True)
class Event:
    key: str
    name: str
    emoji: str
    template: str  # festtagsmenue | plaetzchen | grillparty
    meal: str  # Hauptmahlzeit des Specials
    season: bool = False  # True = Saisonbeginn (Datum = Start), sonst Anlass an einem Tag


EVENTS = {e.key: e for e in (
    Event("weihnachten", "Weihnachten", "🎄", "festtagsmenue", "abend"),
    Event("silvester", "Silvester", "🎆", "festtagsmenue", "abend"),
    Event("ostern", "Ostern", "🐣", "festtagsmenue", "mittag"),
    Event("muttertag", "Muttertag", "💐", "festtagsmenue", "mittag"),
    Event("halloween", "Halloween", "🎃", "festtagsmenue", "abend"),
    Event("grillsaison", "Grillsaison", "🔥", "grillparty", "abend", season=True),
    Event("plaetzchen", "Plätzchenzeit", "🍪", "plaetzchen", "dessert", season=True),
)}
TEMPLATES = {"festtagsmenue": "Festtagsmenü", "plaetzchen": "Plätzchen-Back-Plan", "grillparty": "Grillparty"}
# Saisons (Monat von, bis); grill/plaetzchen haben ein Special, Spargel/Kürbis wirken nur im Planer-Prompt
SEASONS = {"spargel": ("Spargelzeit", 4, 6), "grillsaison": ("Grillsaison", 5, 8), "kuerbis": ("Kürbiszeit", 9, 11),
           "plaetzchen": ("Glühwein & Plätzchen", 12, 12)}
SEASON_HINTS = {"spargel": "Spargelzeit: 1–2 Gerichte mit Spargel einplanen",
                "grillsaison": "Grillsaison: gern ein Grillgericht", "kuerbis": "Kürbiszeit: gern ein Gericht mit Kürbis"}
# Saisonkalender Deutschland (Freiland/Lager), je Monat die typischen Sorten
PRODUCE = {
    1: "Grünkohl, Rosenkohl, Wirsing, Rotkohl, Feldsalat, Lauch, Pastinaken, Schwarzwurzeln, Rote Bete, Äpfel",
    2: "Grünkohl, Rosenkohl, Wirsing, Rotkohl, Feldsalat, Lauch, Pastinaken, Topinambur, Rote Bete, Äpfel",
    3: "Bärlauch, Feldsalat, Lauch, Chicorée, Pastinaken, Rote Bete, Spinat, Äpfel",
    4: "Spargel, Bärlauch, Rhabarber, Spinat, Radieschen, Rucola, Frühlingszwiebeln, Kopfsalat",
    5: "Spargel, Rhabarber, Erdbeeren, Radieschen, Kohlrabi, Spinat, Mangold, Frühlingszwiebeln",
    6: "Spargel, Erdbeeren, Kirschen, Erbsen, Kohlrabi, Zucchini, Brokkoli, Blumenkohl, Johannisbeeren",
    7: "Tomaten, Zucchini, Gurken, grüne Bohnen, Paprika, Himbeeren, Heidelbeeren, Kirschen, Brokkoli",
    8: "Tomaten, Paprika, Zucchini, Auberginen, Mais, grüne Bohnen, Pflaumen, Brombeeren, Birnen",
    9: "Kürbis, Zwetschgen, Äpfel, Birnen, Trauben, Tomaten, Paprika, Pfifferlinge, Rote Bete",
    10: "Kürbis, Äpfel, Birnen, Quitten, Rote Bete, Lauch, Wirsing, Rotkohl, Feldsalat, Maronen",
    11: "Kürbis, Grünkohl, Rosenkohl, Rotkohl, Wirsing, Feldsalat, Pastinaken, Steckrüben, Äpfel, Birnen",
    12: "Grünkohl, Rosenkohl, Rotkohl, Wirsing, Feldsalat, Pastinaken, Schwarzwurzeln, Äpfel, Maronen",
}


def event_date(key: str, today: date) -> date:
    """Nächstes Datum ≥ heute (Anlass bzw. Saisonbeginn; läuft die Saison schon, ist es heute)."""
    e = EVENTS[key]
    if e.season:
        name, start, end = SEASONS[key]
        if start <= today.month <= end:
            return today
        first = date(today.year, start, 1)
        return first if first >= today else date(today.year + 1, start, 1)
    for year in (today.year, today.year + 1):
        d = {"weihnachten": date(year, 12, 24), "silvester": date(year, 12, 31), "ostern": easter(year),
             "muttertag": mothers_day(year), "halloween": date(year, 10, 31)}[key]
        if d >= today:
            return d
    raise AssertionError("unreachable")


def active_seasons(today: date) -> list[str]:
    return [k for k, (_, start, end) in SEASONS.items() if start <= today.month <= end]


def specials(today: date, plz: str = "") -> dict:
    """Start-Banner (nächster Anlass/Saisonbeginn in ≤ 14 Tagen; Anlässe vor Saisons), alle jetzt passenden
    Special-Vorlagen, Feiertage der nächsten 14 Tage, Saisons und Saisongemüse."""
    st = state(plz)
    out = []
    for key, e in EVENTS.items():
        d = event_date(key, today)
        days = (d - today).days
        if e.season and d == today:
            out.append({"key": key, "name": e.name, "emoji": e.emoji, "date": d, "days_until": 0,
                        "template": e.template, "template_name": TEMPLATES[e.template], "running": True})
        elif days <= BANNER_DAYS:
            out.append({"key": key, "name": e.name, "emoji": e.emoji, "date": d, "days_until": days,
                        "template": e.template, "template_name": TEMPLATES[e.template], "running": False})
    upcoming = sorted((s for s in out if not s["running"]), key=lambda s: (EVENTS[s["key"]].season, s["days_until"]))
    banner = None
    if upcoming:
        s = upcoming[0]
        when = "heute" if s["days_until"] == 0 else "morgen" if s["days_until"] == 1 else f"in {s['days_until']} Tagen"
        action = {"festtagsmenue": "Menü planen?", "plaetzchen": "Back-Plan erstellen?",
                  "grillparty": "Grillparty planen?"}[s["template"]]
        banner = s | {"text": f"{s['emoji']} {s['name']} {when} – {action}"}
    hol = {d: n for y in (today.year, today.year + 1) for d, n in holidays(y, st).items()
           if 0 <= (d - today).days <= BANNER_DAYS}
    return {"state": st, "banner": banner, "specials": out,
            "holidays": [{"date": d, "name": n} for d, n in sorted(hol.items())],
            "seasons": [SEASONS[k][0] for k in active_seasons(today)], "produce": PRODUCE[today.month].split(", ")}


def plan_monday(today: date) -> date:
    """Montag der Woche, für die geplant wird: ab Freitag die nächste (wie jobs.plan_week)."""
    return today - timedelta(today.weekday()) + timedelta(7 if today.weekday() >= 4 else 0)


DAY_SHORT = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]


def prompt_lines(today: date, plz: str = "") -> list[str]:
    """Kompakte Zeilen für den variablen Prompt-Teil: Saisongemüse (leicht bevorzugen), Saison-Hinweise,
    Feiertage der Planwoche."""
    lines = [f"Saison (leicht bevorzugen): {PRODUCE[today.month]}"]
    lines += [SEASON_HINTS[k] for k in active_seasons(today) if k in SEASON_HINTS]
    monday = plan_monday(today)
    hol = {d: n for y in {monday.year, (monday + timedelta(6)).year} for d, n in holidays(y, state(plz)).items()
           if 0 <= (d - monday).days <= 6}
    if hol:
        lines.append("Feiertag (mehr Zeit zum Kochen): " + ", ".join(f"{DAY_SHORT[d.weekday()]} {n}"
                                                                        for d, n in sorted(hol.items())))
    return lines


def special_plan(key: str, today: date, plan_days: list[int]) -> tuple[list[tuple[int, str]], str]:
    """Zusatz-Slots und Prompt-Hinweis für eine Special-Vorlage (Generator mit Special). Festtagsmenü am Wochentag
    des Anlasses (Vorspeise/Haupt/Dessert), Grillparty am Samstag, Plätzchen Sa+So als Dessert."""
    e = EVENTS[key]
    if e.template == "festtagsmenue":
        d = event_date(key, today).weekday()
        slots = [(d, "vorspeise"), (d, e.meal), (d, "dessert")]
        return slots, (f"Festtagsmenü {e.name} am {DAY_SHORT[d]}: Vorspeise, Hauptgang ({e.meal}) und Dessert als "
                       "zusammenpassendes, festliches Menü; bis 120 min Kochzeit erlaubt.")
    if e.template == "grillparty":
        d = 5 if 5 in plan_days or not plan_days else max(plan_days)
        return [(d, "abend")], (f"Grillparty am {DAY_SHORT[d]} (abend): Grillgut plus 2–3 Beilagen (Salate, Dips, "
                                "Brot) als EIN Gericht mit allen Zutaten, gästetauglich.")
    return [(5, "dessert"), (6, "dessert")], ("Plätzchen-Back-Plan: Sa und So je eine andere Plätzchensorte "
                                              "(dessert), je ein Blech mit ca. 30 Stück, erster Schritt „Am Vortag: "
                                              "Teig vorbereiten …“, wenn der Teig ruhen muss.")
