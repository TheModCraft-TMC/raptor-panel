ARG BASE_IMAGE=ghcr.io/blueprintframework/blueprint:v1.15.2
FROM ${BASE_IMAGE}
ARG PANEL_VERSION=v1.15.2
LABEL org.opencontainers.image.title="Raptor Panel" \
      org.opencontainers.image.source="https://github.com/TheModCraft-TMC/raptor-panel"
RUN apk add --no-cache util-linux \
    && printf 'session.upload_progress.enabled=Off\n' > /usr/local/etc/php/conf.d/zz-upload-progress.ini \
    && mkdir -p /opt/raptor \
    && printf '%s\n' "$PANEL_VERSION" > /opt/raptor/version
COPY entrypoint.sh prepare-update.sh /opt/raptor/
RUN chmod 755 /opt/raptor/*.sh
ENTRYPOINT ["/bin/bash", "/opt/raptor/entrypoint.sh"]
