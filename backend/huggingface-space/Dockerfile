# Use the maintained LinuxServer Jackett image. It bundles Mono + Jackett +
# all the indexer cardigans and gets weekly updates.
FROM lscr.io/linuxserver/jackett:latest

# HF Spaces injects a non-root user; the LinuxServer image uses s6-overlay and
# expects to be PID 1 as root, which Spaces allows for Docker SDK images. We
# only need to make sure config/downloads paths are world-writable so the
# container can rewrite them on every cold start (HF disk is ephemeral).
RUN mkdir -p /config /downloads && chmod -R 0777 /config /downloads

# Bake the seed configuration into the image.
#
# - /etc/cont-init.d/99-torrex-init  (runs once before Jackett starts) stamps
#   a stable APIKey from $JACKETT_API_KEY into ServerConfig.json so the
#   Torznab key survives HF rebuilds.
# - /etc/services.d/torrex-seed/run  (runs in parallel with Jackett) waits
#   for the API to come up, then POSTs default config for each indexer
#   listed in /seed/indexers.txt — using Jackett's own HTTP API rather than
#   trying to forge its on-disk JSON format.
COPY seed /seed
COPY torrex-init.sh /etc/cont-init.d/99-torrex-init
COPY torrex-seed-service.sh /etc/services.d/torrex-seed/run
RUN chmod +x /etc/cont-init.d/99-torrex-init /etc/services.d/torrex-seed/run

# Jackett listens on 9117 by default. The matching `app_port: 9117` in the
# Space README tells HF to route public traffic here.
EXPOSE 9117

ENV PUID=0 \
    PGID=0 \
    TZ=Etc/UTC \
    AUTO_UPDATE=true
