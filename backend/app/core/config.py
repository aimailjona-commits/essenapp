from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./essenapp.db"
    anthropic_api_key: str = ""
    model_planner: str = "claude-sonnet-5-5"
    model_fast: str = "claude-haiku-5-5"


settings = Settings()
