# Raptor Panel

Pterodactyl Panel 1.x with Blueprint, patched PHP, and Watchtower-compatible persistent data.

Image: `ghcr.io/themodcraft-tmc/raptor-panel:1`. The moving `1` tag follows stable Panel 1.x releases only; versioned tags are also published. A daily build refreshes the upstream Blueprint image and checks PHP before publishing. If Blueprint has not yet published the corresponding Panel version, the build fails instead of silently selecting another major version.

## Persistence

Do **not** mount a volume at `/app`. That hides the new panel code in every replacement image. Persist these paths instead:

- `/app/var`: existing `.env` with the original `APP_KEY`, upgrade metadata, backups, and extension private data.
- `/app/storage`: uploads and Laravel storage.
- `/blueprint_extensions`: original `.blueprint` archives, named by extension identifier.
- Existing Nginx configuration, TLS certificates and logs as appropriate.

The database remains in its separate database service. Keep the original `APP_KEY`; generating a replacement makes encrypted database values unreadable.

On container creation, the entrypoint verifies extension archives, backs up the database and `.env`, migrates the database and restores recorded extensions against the image's fresh code. Normal container restarts skip completed initialization. Extension private directories point into the persistent var directory.

Enable Watchtower lifecycle hooks and set:

```yaml
labels:
  com.centurylinklabs.watchtower.enable: 'true'
  com.centurylinklabs.watchtower.lifecycle.pre-update: '/bin/bash /opt/raptor/prepare-update.sh'
  com.centurylinklabs.watchtower.lifecycle.pre-update-timeout: '3'
```

Run `prepare-update.sh` before manually recreating a container after changing its installed extensions, too. It records only installed extensions and verifies that their archives exist. Do not use an uninstall pre-update hook.

## Migrating an existing whole-app volume

1. Back up the database, `.env` and complete old application volume.
2. Run `prepare-update.sh` in the old container to save its extension manifest and private data, and copy its original extension archives into `/blueprint_extensions`.
3. Copy `/app/storage` into the new storage mount. Preserve any site-specific source customizations separately; package them as an extension or image change before switching.
4. Remove the `/app` mount, retain `/app/var`, add the storage mount, and deploy this image.
5. Verify the version, login, extensions, queues and nodes. Keep the old application volume for recovery.

No server `.env`, credentials, licensed extension packages, or live panel data belong in this repository or image.

## Recovery

A failed initialization leaves `/app/var/raptor/in-progress` naming its recovery snapshot and refuses automatic retries. Restore the database and original `.env`, restore extension data if needed, and select a compatible previous image. Remove `in-progress` only after completing recovery. Backups are not automatically deleted; monitor disk usage and archive them separately.

CI checks the PHP patch level and disabled session upload progress, then tests a real upgrade from Panel 1.12.3 with MariaDB, Redis and persistent data. Third-party extension compatibility must also be checked on deployment.
