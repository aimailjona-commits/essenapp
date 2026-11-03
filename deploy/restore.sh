#!/usr/bin/env bash
# Wiederherstellung aus einem Archiv von backup.sh.
#   ./restore.sh --test <archiv>   Probe (ändert nichts Live): Datenbank in essenapp_restore_test, Zählvergleich mit
#                                   der Live-Datenbank und den /media-Dateien, danach wird die Probe-Datenbank gelöscht
#   ./restore.sh <archiv>          Ernstfall: ersetzt Datenbank und /media (api + scheduler werden dafür gestoppt)
set -euo pipefail
cd "$(dirname "$0")"
ENV_FILE=${ENV_FILE:-./.env}
set -a; . "$ENV_FILE"; set +a
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE fehlt in $ENV_FILE}"
compose() { docker compose --env-file "$ENV_FILE" "$@"; }
psql() { compose exec -T db psql -U essenapp -v ON_ERROR_STOP=1 -q "$@"; }

probe=0
if [ "${1:-}" = "--test" ]; then probe=1; shift; fi
archive=${1:?Archiv angeben, z.B. /var/backups/essenapp/essenapp-2026-11-03-0330.tar.enc}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:BACKUP_PASSPHRASE -in "$archive" | tar -C "$tmp" -xf -

if [ "$probe" = 1 ]; then
  test_db=essenapp_restore_test
  psql -d postgres -c "DROP DATABASE IF EXISTS $test_db" -c "CREATE DATABASE $test_db"
  compose exec -T db pg_restore -U essenapp -d "$test_db" --no-owner < "$tmp/db.dump"
  fail=0
  for t in household member meal_plan meal_plan_entry shopping_list shopping_item recipe pantry_item offer; do
    live=$(psql -d essenapp -tAc "SELECT count(*) FROM $t")
    back=$(psql -d "$test_db" -tAc "SELECT count(*) FROM $t")
    echo "$t: live $live, Backup $back"
    [ "$back" -gt 0 ] || [ "$live" = 0 ] || fail=1
  done
  live=$(compose exec -T api find /app/media -type f | wc -l)
  back=$(tar -tf "$tmp/media.tar" | grep -vc '/$' || true)
  echo "media: live $live Dateien, Backup $back"
  psql -d postgres -c "DROP DATABASE $test_db"
  [ "$fail" = 0 ] && echo "Probe OK (Abweichungen = Änderungen seit dem Backup)" || { echo "Probe FEHLER: Backup leer"; exit 1; }
  exit 0
fi

read -r -p "Datenbank und /media durch $archive ersetzen? (ja/nein) " answer
[ "$answer" = "ja" ] || { echo "Abgebrochen"; exit 1; }
compose stop api scheduler
compose exec -T db pg_restore -U essenapp -d essenapp --clean --if-exists --no-owner < "$tmp/db.dump"
compose run --rm --no-deps -T api sh -c 'find /app/media -mindepth 1 -delete && tar -C /app -xf -' < "$tmp/media.tar"
compose up -d --wait
echo "Wiederhergestellt aus $archive"
