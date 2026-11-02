#!/bin/bash
# In WSL ausführen: ./dev.sh test | ./dev.sh serve | ./dev.sh <beliebiger uv-run-Befehl>
# venv liegt im WSL-Dateisystem, weil Python-Importe von /mnt/c sehr langsam sind.
export PATH="$HOME/.local/bin:$PATH"
export UV_PROJECT_ENVIRONMENT="$HOME/.venvs/essenapp-backend"
cd "$(dirname "$0")"
case "$1" in
  test)  shift; uv run pytest -q "$@" ;;
  serve) SCHEDULER=1 uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload ;;
  *)     uv run "$@" ;;
esac
