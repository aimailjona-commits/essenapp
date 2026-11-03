from datetime import date

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./essenapp.db"  # VPS (72): postgresql+psycopg://…
    # Basis für Einladungs-/Listen-/Rezept-Links, z.B. https://essenapp.example.de; leer = Adresse der Anfrage (lokal)
    public_base_url: str = ""
    anthropic_api_key: str = ""
    # Nutzerentscheidung: Haiku 5.5 wegen der Kosten. Andere Modelle (claude-sonnet-5-5, claude-opus-5-5) per .env.
    model_planner: str = "claude-haiku-5-5"
    model_fast: str = "claude-haiku-5-5"  # Zuordnungen (Zutat → Nährwert-Eintrag), Haiku laut E38/E39
    planner_effort: str = "low"  # low | medium | high | xhigh | max
    fal_key: str = ""  # optional: KI-Rezeptfotos über fal.ai, wenn kein freies Foto gefunden wird
    # Apple Push (E52): Auth-Key (.p8) aus dem Developer-Account, Pfad absolut oder relativ zu backend/
    apns_key_path: str = ""  # z.B. secrets/AuthKey_XXXXXXXXXX.p8
    apns_key_id: str = ""
    apns_team_id: str = ""
    apns_topic: str = "de.jsenf.essenapp"  # Bundle-ID der App
    # Scheduler (E47) läuft bis zum VPS als Thread im lokalen API-Prozess.
    scheduler: bool = False  # SCHEDULER=1 startet die Job-Schleife beim App-Start (dev.sh serve)
    reinstall_base: date | None = None  # letzte Installation der iOS-App (7-Tage-Signatur), z.B. 2026-11-02
    job_schedules: dict[str, str] = {}  # Zeitpläne überschreiben, z.B. {"import_offers": "Sa 22:00, Mo 06:00"}


settings = Settings()
