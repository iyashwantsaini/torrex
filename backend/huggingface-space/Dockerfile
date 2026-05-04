# Use the maintained LinuxServer Jackett image. It bundles Mono + Jackett +
# all the indexer cardigans and gets weekly updates.
FROM lscr.io/linuxserver/jackett:latest

# HF Spaces injects a non-root user; the LinuxServer image uses s6-overlay and
# expects to be PID 1 as root, which Spaces allows for Docker SDK images. We
# only need to make sure config/downloads paths are world-writable so the
# container can rewrite them on every cold start (HF disk is ephemeral).
RUN mkdir -p /config /downloads && chmod -R 0777 /config /downloads

# Jackett listens on 9117 by default. The matching `app_port: 9117` in the
# Space README tells HF to route public traffic here.
EXPOSE 9117

ENV PUID=0 \
    PGID=0 \
    TZ=Etc/UTC \
    AUTO_UPDATE=true
