# Backend-Image (Spezifikation 72): api und scheduler. Build-Kontext = backend/ (siehe docker-compose.yml).
FROM python:3.12-slim

# tzdata: Jobs rechnen in Europe/Berlin, naive Zeitstempel wie lokal (TZ in docker-compose.yml)
RUN apt-get update && apt-get install -y --no-install-recommends tzdata && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:0.13.6 /uv /bin/uv

ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PROJECT_ENVIRONMENT=/venv PATH=/venv/bin:$PATH PYTHONUNBUFFERED=1
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

# Nicht-root; UID = Benutzer auf dem VPS (APP_UID), damit er backend/secrets lesen und /media sichern kann
ARG UID=10001
RUN useradd --uid "$UID" --no-create-home --home-dir /app app && mkdir -p /app/media /app/secrets \
    && chown app:app /app /app/media
COPY --chown=app:app . .
USER app

EXPOSE 8000
# Migrationen vor dem Start; Proxy-Header von Caddy übernehmen (Client-IP für /pair-Sperre, https)
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2 --proxy-headers --forwarded-allow-ips '*'"]
