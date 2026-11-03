"""Zutat → Angebote per Namensabgleich (Feature 1, auch Kostenanteil im Angebot, 3).
Normalisiert, einfache Plural-Endungen, Komposita über das Wortende („Gemüsezwiebeln“ ist eine Zwiebel,
„Butterkeks“ keine Butter), plus Synonyme für Fälle, in denen das Wortende nicht passt."""
import re

from app.models import Offer

FOOD = ("fleisch_fisch", "obst_gemuese", "kuehlung", "vorrat", "sonstiges")  # wie planner.FOOD_CATEGORIES
IGNORE = {"frisch", "frische", "frischer", "frisches", "bio", "tk", "gehackt", "gehackte", "getrocknet",
          "getrocknete", "klein", "kleine", "große", "groß"}
SYNONYMS = {  # Zutat → weitere Bezeichnungen im Prospekt
    "hähnchenbrust": ("hähnchenbrustfilet", "hähnchenfilet", "hühnerbrust", "hühnerbrustfilet"),
    "putenbrust": ("putenbrustfilet", "putenschnitzel"),
    "ei": ("eier",),
    "hackfleisch": ("hack", "gehacktes"),
    "möhre": ("karotte",),
    "karotte": ("möhre",),
    "lauchzwiebel": ("frühlingszwiebel",),
    "frühlingszwiebel": ("lauchzwiebel",),
    "kartoffel": ("speisekartoffel", "drillinge"),
    "nudeln": ("pasta", "spaghetti", "penne", "fusilli", "farfalle"),
    "paprika": ("paprikaschote",),
    "parmesan": ("grana padano", "hartkäse"),
}


def stem(word: str) -> str:
    for suffix in ("en", "n", "e", "s"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 4:
            return word[:-len(suffix)]
    return word


def words(text: str) -> list[str]:
    return [stem(w) for w in re.findall(r"\w+", (text or "").lower()) if w not in IGNORE]


SYN = {" ".join(words(k)): [words(v) for v in vs] for k, vs in SYNONYMS.items()}


class Matcher:
    """Index über Angebotstitel: Wortende (4 Zeichen) → Angebote, damit viele Zutaten schnell gesucht werden können."""

    def __init__(self, offers: list[Offer], food_only: bool = True):
        self.offers = [o for o in offers if o.category in FOOD or not food_only]
        # Titelwörter roh und gestemmt („Langkornreis“ verliert sonst sein s und passt nicht mehr zu „Reis“)
        self.titles = [set(words(o.title)) | set(re.findall(r"\w+", o.title.lower())) for o in self.offers]
        self.index: dict[str, set[int]] = {}
        for i, ws in enumerate(self.titles):
            for w in ws:
                self.index.setdefault(w[-4:], set()).add(i)

    def _hits(self, phrase: list[str]) -> set[int]:
        found = None
        for w in phrase:
            # kurze Wörter („ei“) nur exakt, sonst auch als Wortende (Kompositum)
            ids = {i for i in self.index.get(w[-4:], ()) if any(t == w or (len(w) >= 4 and t.endswith(w))
                                                                  for t in self.titles[i])}
            found = ids if found is None else found & ids
            if not found:
                return set()
        return found or set()

    def find(self, name: str) -> list[Offer]:
        """Passende Angebote, günstigster Grundpreis zuerst."""
        phrase = words(name)
        if not phrase:
            return []
        ids = self._hits(phrase)
        for alt in SYN.get(" ".join(phrase), ()):
            ids |= self._hits(alt)
        return sorted((self.offers[i] for i in ids),
                      key=lambda o: (o.base_price_cents is None, o.base_price_cents or 0, o.price_cents))
