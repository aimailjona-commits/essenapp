#!/usr/bin/env bash
# Einmaliges Einrichten auf frischem Ubuntu 24.04 (Spezifikation 72, E86). Idempotent: darf erneut laufen
# (z.B. nach einem Update per rsync). Als root:
#   DOMAIN=essenapp.example.de bash /opt/essenapp/deploy/setup-vps.sh
# Erwartet das Repo im übergeordneten Ordner (rsync aus WSL oder git clone), optional dazu:
#   backend/.env (App-Keys wie lokal), backend/secrets/AuthKey_….p8 (APNs),
#   deploy/import/essenapp.db + deploy/import/media.tar (einmaliger Umzug, nur in eine leere Datenbank)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Bitte als root starten (sudo)"; exit 1; }
DEPLOY=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$DEPLOY")
APP_USER=${APP_USER:-essenapp}
export DEBIAN_FRONTEND=noninteractive

echo "== Pakete und automatische Sicherheitsupdates"
apt-get update -q
apt-get install -y -q ca-certificates curl git openssl rsync sudo ufw unattended-upgrades
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' \
  > /etc/apt/apt.conf.d/20auto-upgrades

echo "== Docker (offizielles Repository, docs.docker.com/engine/install/ubuntu)"
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc]" \
    "https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -q
  apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker

echo "== Firewall: nur SSH, HTTP, HTTPS (Postgres ist nicht veröffentlicht)"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw allow 443/udp >/dev/null  # HTTP/3
ufw --force enable

echo "== Benutzer $APP_USER (Docker, gleicher SSH-Schlüssel wie root)"
id "$APP_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$APP_USER"
usermod -aG docker "$APP_USER"
home=$(getent passwd "$APP_USER" | cut -d: -f6)
if [ -s /root/.ssh/authorized_keys ]; then
  install -d -m 700 -o "$APP_USER" -g "$APP_USER" "$home/.ssh"
  [ -f "$home/.ssh/authorized_keys" ] || install -m 600 -o "$APP_USER" -g "$APP_USER" /root/.ssh/authorized_keys "$home/.ssh/"
  # Login nur noch mit Schlüssel (nur wenn einer hinterlegt ist, sonst sperrt man sich aus)
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/01-essenapp.conf  # vor 50-cloud-init.conf: erster Wert gilt
  systemctl try-reload-or-restart ssh
fi

echo "== Konfiguration deploy/.env"
ENV="$DEPLOY/.env"
if [ ! -f "$ENV" ]; then
  : "${DOMAIN:?DOMAIN=essenapp.<deine-domain> angeben}"
  sed -e "s|^DOMAIN=.*|DOMAIN=$DOMAIN|" \
      -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 24)|" \
      -e "s|^BACKUP_PASSPHRASE=.*|BACKUP_PASSPHRASE=$(openssl rand -hex 32)|" \
      -e "s|^APP_UID=.*|APP_UID=$(id -u "$APP_USER")|" \
      "$DEPLOY/.env.example" > "$ENV"
  echo ">>> Neue Passwörter in $ENV – BACKUP_PASSPHRASE zusätzlich im Passwortmanager sichern!"
fi
set -a; . "$ENV"; set +a
mkdir -p "$ROOT/backend/secrets" "${BACKUP_DIR:-/var/backups/essenapp}"
chown -R "$APP_USER:$APP_USER" "$ROOT" "${BACKUP_DIR:-/var/backups/essenapp}"
chmod 600 "$ENV"
[ -f "$ROOT/backend/.env" ] && chmod 600 "$ROOT/backend/.env"
chmod 700 "$ROOT/backend/secrets"
find "$ROOT/backend/secrets" -type f -exec chmod 600 {} +
chmod +x "$DEPLOY"/*.sh

echo "== Start: Datenbank, Migrationen, Umzug, alle Dienste"
cd "$DEPLOY"
as_app() { sudo -H -u "$APP_USER" -- "$@"; }
as_app docker compose build
as_app docker compose up -d --wait db
as_app docker compose run --rm api alembic upgrade head
if [ -f import/essenapp.db ] && [ ! -f import/.imported ]; then
  as_app docker compose run --rm -v "$DEPLOY/import:/import:ro" \
    -v "$DEPLOY/migrate_sqlite_to_postgres.py:/tmp/migrate.py:ro" api python /tmp/migrate.py /import/essenapp.db
  if [ -f import/media.tar ]; then
    as_app docker compose run --rm -T api tar -C /app -xf - < import/media.tar
  fi
  touch import/.imported
fi
as_app docker compose up -d --wait --remove-orphans

echo "== Tägliches Backup 03:30 (Log /var/log/essenapp-backup.log)"
touch /var/log/essenapp-backup.log
chown "$APP_USER:$APP_USER" /var/log/essenapp-backup.log
echo "30 3 * * * $APP_USER $DEPLOY/backup.sh >> /var/log/essenapp-backup.log 2>&1" > /etc/cron.d/essenapp-backup

echo "Fertig: https://$DOMAIN/health"
