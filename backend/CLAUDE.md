# Backend – Regeln

PonyTail `full` gilt (siehe Root-`CLAUDE.md`).

## Umgebung

- Läuft **in WSL (Ubuntu-24.04)**, Python 3.12, Paketverwaltung mit `uv`.
- Immer über `./dev.sh` (venv im WSL-Dateisystem, E27): `./dev.sh test`, `./dev.sh serve`, `./dev.sh alembic upgrade head`.
- Secrets nur in `backend/.env` (nicht ins Git). `.env.example` immer aktuell halten.

## Struktur (aus dem Playbook)

```
app/api/        FastAPI-Router
app/core/       Config, Auth, DB-Session
app/models/     SQLAlchemy-Modelle
app/schemas/    Pydantic-Schemas = API-Vertrag (iOS-Modelle richten sich danach)
app/sources/    ein Adapter pro Händler (OfferSource)
app/services/   Planner, Pricing, Nutrition, Matching, Notifications
app/jobs/       geplante Jobs
app/web/        Web-PWA für Familie (Jinja + HTMX), gleiches Design-System wie iOS
migrations/     Alembic
tests/
```

Ordner erst anlegen, wenn eine Aufgabe sie braucht.

## Regeln

- Händler-Adapter: Endpunkte recherchieren, nie erfinden. Im Playbook (Abschnitt 5) dokumentieren. Schonend abrufen, Rohdaten speichern, Test mit gespeicherter Fixture.
- Geld: Beträge als `Decimal` bzw. Cent-Integer, nie `float`.
- Nährwerte und Kosten rechnet der Code, nicht die KI.
- KI-Aufrufe: Modell per ENV, strukturierte Ausgabe (Tool-Schema), Ergebnisse cachen.
- Web-PWA: CSS-Variablen mit denselben Werten wie `docs/ui/design-system.md`.
