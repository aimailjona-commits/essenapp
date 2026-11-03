#!/usr/bin/env bash
# Tägliches Backup (Spezifikation 72): pg_dump + /media → ein verschlüsseltes Archiv (AES-256, Passphrase aus .env),
# BACKUP_KEEP_DAYS Tage aufbewahrt, optional per rsync kopiert. cron legt setup-vps.sh an (03:30).
# Entschlüsseln/Wiederherstellen: restore.sh
set -euo pipefail
cd "$(dirname "$0")"
ENV_FILE=${ENV_FILE:-./.env}
set -a; . "$ENV_FILE"; set +a
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE fehlt in $ENV_FILE}"
DIR=${BACKUP_DIR:-/var/backups/essenapp}
KEEP=${BACKUP_KEEP_DAYS:-14}
compose() { docker compose --env-file "$ENV_FILE" "$@"; }

umask 077
mkdir -p "$DIR"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

compose exec -T db pg_dump -U essenapp -Fc essenapp > "$tmp/db.dump"
compose exec -T api tar -C /app -cf - media > "$tmp/media.tar"
out="$DIR/essenapp-$(date +%F-%H%M).tar.enc"
tar -C "$tmp" -cf - db.dump media.tar \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass env:BACKUP_PASSPHRASE -out "$out.part"
mv "$out.part" "$out"  # halbe Archive nie unter dem echten Namen

find "$DIR" -name 'essenapp-*.tar.enc' -mtime +$((KEEP - 1)) -delete
if [ -n "${BACKUP_RSYNC_TARGET:-}" ]; then
  rsync -a "$out" "$BACKUP_RSYNC_TARGET"  # shortcut: alte Kopien am Ziel räumt rsync nicht weg
fi
echo "$(date '+%F %T') Backup: $out ($(du -h "$out" | cut -f1))"
