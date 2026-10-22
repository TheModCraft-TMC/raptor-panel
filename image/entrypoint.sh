#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
cd /app
state=/app/var/raptor
mkdir -p "$state/extensions" "$state/filesystems"
# PHP-FPM must traverse to extension state; backup directories remain root-only.
chmod 711 "$state"
exec 9>"$state/lock"
flock -n 9 || { echo 'Another panel initialization is running.' >&2; exit 1; }
[[ -s var/.env ]] || { echo 'Mount the existing panel var/.env with its APP_KEY before starting.' >&2; exit 1; }
ln -sfn /app/var/.env /app/.env
if [[ -f "$state/in-progress" ]]; then
  echo 'An earlier upgrade failed. Restore or repair the snapshot recorded here before retrying:' >&2
  cat "$state/in-progress" >&2
  exit 1
fi
if [[ ! -f /app/.raptor-ready ]]; then
  version=$(cat /opt/raptor/version)
  [[ $version =~ ^v1\.[0-9]+\.[0-9]+$ ]] || { echo 'Refusing a non-1.x image.' >&2; exit 1; }
  identifiers=()
  packages=()
  if [[ -f "$state/extensions.list" ]]; then
    while IFS= read -r identifier; do
      [[ -n "$identifier" ]] || continue
      [[ $identifier =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Invalid extension identifier.' >&2; exit 1; }
      package="/blueprint_extensions/$identifier.blueprint"
      [[ -f "$package" ]] || { echo "Missing extension archive: $identifier" >&2; exit 1; }
      identifiers+=("$identifier")
      packages+=("$identifier.blueprint")
    done < "$state/extensions.list"
  fi
  : "${DB_HOST:?}" "${DB_DATABASE:?}" "${DB_USERNAME:?}" "${DB_PASSWORD:?}"
  backup="$state/backups/$(date -u +%Y%m%dT%H%M%SZ)-$version"
  mkdir -p "$backup"
  chmod 700 "$state" "$state/backups" "$backup"
  # The old container has stopped, and this one has not started HTTP, cron or queue workers.
  MYSQL_PWD="$DB_PASSWORD" mariadb-dump --host="$DB_HOST" --port="${DB_PORT:-3306}" \
    --user="$DB_USERNAME" --single-transaction --quick --skip-lock-tables --no-tablespaces \
    "$DB_DATABASE" | gzip > "$backup/database.sql.gz"
  gzip -t "$backup/database.sql.gz"
  cp -aL var/.env "$backup/panel.env"
  if [[ -f "$state/extensions.list" ]]; then cp "$state/extensions.list" "$backup/"; fi
  if [[ -d "$state/extensions" ]]; then tar -czf "$backup/extension-data.tar.gz" -C "$state" extensions; fi
  if [[ -d "$state/filesystems" ]]; then tar -czf "$backup/extension-filesystems.tar.gz" -C "$state" filesystems; fi
  printf '%s\n' "$backup" > "$state/in-progress"
  trap 'echo "Panel initialization failed; snapshot: $backup" >&2' ERR
  if [[ -f "$state/site-config/services.php" ]]; then
    mv config/services.php config/services.image.php
    cat > config/services.php <<'PHP'
<?php
$services = require __DIR__ . '/services.image.php';
$site = require '/app/var/raptor/site-config/services.php';
if (isset($site['authentik'])) {
    $services['authentik'] = $site['authentik'];
}
return $services;
PHP
    chmod 644 config/services.php
    chown -R nginx:nginx "$state/site-config"
  fi
  php artisan down
  php artisan config:clear
  php artisan migrate --seed --force
  for identifier in "${identifiers[@]}"; do
    mkdir -p "$state/extensions/$identifier" ".blueprint/extensions/$identifier"
    private=".blueprint/extensions/$identifier/private"
    # Persist extension state, while keeping Blueprint and the Panel supplied by the image.
    if [[ -d "$private" && ! -L "$private" ]]; then
      cp -an "$private/." "$state/extensions/$identifier/"
      mv "$private" "$private.image"
    fi
    ln -sfn "$state/extensions/$identifier" "$private"
    filesystem=".blueprint/extensions/$identifier/fs"
    mkdir -p "$state/filesystems/$identifier"
    if [[ -d "$filesystem" && ! -L "$filesystem" ]]; then
      cp -an "$filesystem/." "$state/filesystems/$identifier/"
      mv "$filesystem" "$filesystem.image"
    fi
    ln -sfn "$state/filesystems/$identifier" "$filesystem"
    cp -a "/blueprint_extensions/$identifier.blueprint" "/app/$identifier.blueprint"
  done
  if (( ${#packages[@]} )); then
    IgnoreRebuild=true blueprint -i "${packages[@]}"
    inventory=.blueprint/extensions/blueprint/private/db/installed_extensions
    for identifier in "${identifiers[@]}"; do
      grep -Fq "|$identifier," "$inventory" || { echo "Extension failed to install: $identifier" >&2; exit 1; }
    done
    yarn run build:production
  fi
  php artisan migrate --force
  php artisan view:clear
  php artisan config:clear
  php artisan queue:restart
  chown -R nginx:nginx /app/storage /app/bootstrap/cache "$state/extensions" "$state/filesystems"
  php artisan up
  touch /app/.raptor-ready
  rm -f "$state/in-progress"
  echo "Panel $version initialized; backup: $backup"
fi
flock -u 9
exec 9>&-
exec /bin/ash .github/docker/entrypoint.sh "$@"
