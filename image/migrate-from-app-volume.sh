#!/usr/bin/env bash
# Run once in the OLD container before removing its /app volume.
set -Eeuo pipefail
umask 077
cd /app
state=/app/var/raptor
mkdir -p "$state/migration" "$state/site-config"
backup="$state/migration/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup"
chmod 700 "$state" "$state/migration" "$backup"
[[ -s /app/var/.env ]] || { echo 'Original .env is missing.' >&2; exit 1; }
sha256sum /app/var/.env > "$backup/env.sha256"
cp -aL /app/var/.env "$backup/panel.env"
# Save the site-specific Authentik configuration locally, never in the image.
cp -a config/services.php "$state/site-config/services.php"
php artisan down
cleanup() {
  php artisan up
  supervisorctl start queue-worker >/dev/null 2>&1 || true
}
trap cleanup EXIT
supervisorctl stop queue-worker
: "${DB_HOST:?}" "${DB_DATABASE:?}" "${DB_USERNAME:?}" "${DB_PASSWORD:?}"
MYSQL_PWD="$DB_PASSWORD" mariadb-dump --host="$DB_HOST" --port="${DB_PORT:-3306}" \
  --user="$DB_USERNAME" --single-transaction --quick --skip-lock-tables --no-tablespaces \
  "$DB_DATABASE" | gzip > "$backup/database.sql.gz"
gzip -t "$backup/database.sql.gz"
tar --exclude=./var --exclude=./watchtower --exclude=./storage/logs -czf "$backup/app.tar.gz" .
gzip -t "$backup/app.tar.gz"
bash /tmp/raptor-prepare-update.sh
mkdir -p /app/var/storage
rsync -a --exclude=/logs/ /app/storage/ /app/var/storage/
sha256sum -c "$backup/env.sha256"
printf '%s\n' "$backup" > "$state/migration-ready"
echo "Migration prepared. Verified snapshot: $backup"
echo "Installed extensions: $(wc -l < "$state/extensions.list")"
