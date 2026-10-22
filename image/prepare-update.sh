#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
cd /app
state=/app/var/raptor
mkdir -p "$state/extensions"
# Record the installed set before Watchtower replaces this container.
inventory=.blueprint/extensions/blueprint/private/db/installed_extensions
if [[ -f "$inventory" ]]; then
  tr '|,' '\n\n' < "$inventory" | sed '/^$/d; /^blueprint$/d' > "$state/extensions.list.tmp"
  while IFS= read -r identifier; do
    [[ $identifier =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Invalid extension identifier' >&2; exit 1; }
    package="/blueprint_extensions/$identifier.blueprint"
    if [[ ! -f "$package" && -f "/app/$identifier.blueprint" ]]; then cp -a "/app/$identifier.blueprint" "$package"; fi
    [[ -f "$package" ]] || { echo "Missing extension archive: $identifier" >&2; exit 1; }
    private=".blueprint/extensions/$identifier/private"
    if [[ -d "$private" && ! -L "$private" ]]; then
      mkdir -p "$state/extensions/$identifier"
      cp -a "$private/." "$state/extensions/$identifier/"
    fi
  done < "$state/extensions.list.tmp"
  mv "$state/extensions.list.tmp" "$state/extensions.list"
fi
