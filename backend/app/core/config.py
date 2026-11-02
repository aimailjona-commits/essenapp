from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./essenapp.db"
    anthropic_api_key: str = ""
    # Günstigere Modelle (z.B. claude-sonnet-5-5, claude-haiku-5-5) per .env möglich – Entscheidung des Nutzers.
    model_planner: str = "claude-opus-5-5"
    model_fast: str = "claude-opus-5-5"
    planner_effort: str = "medium"  # low | medium | high | xhigh | max


settings = Settings()
