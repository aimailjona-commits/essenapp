from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./essenapp.db"
    anthropic_api_key: str = ""
    # Nutzerentscheidung: Haiku 5.5 wegen der Kosten. Andere Modelle (claude-sonnet-5-5, claude-opus-5-5) per .env.
    model_planner: str = "claude-haiku-5-5"
    model_fast: str = "claude-opus-5-5"
    planner_effort: str = "low"  # low | medium | high | xhigh | max


settings = Settings()
