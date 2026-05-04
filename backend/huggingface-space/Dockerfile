# Use the maintained LinuxServer Jackett image. It bundles Mono + Jackett +
# all the indexer cardigans and gets weekly updates.
FROM lscr.io/linuxserver/jackett:latest

# HF Spaces injects a non-root user; the LinuxServer image uses s6-overlay and
# expects to be PID 1 as root, which Spaces allows for Docker SDK images. We
# only need to make sure config/downloads paths are world-writable so the
# container can rewrite them on every cold start (HF disk is ephemeral).
RUN mkdir -p /config /downloads && chmod -R 0777 /config /downloads

# Bake the seed configuration into the image. On every container boot the
# entrypoint copies any indexers from /seed into /config/Jackett/Indexers/
# (only if they aren't already there) and stamps the API key + admin
# password from environment variables — so HF rebuilds no longer wipe state.
COPY seed /seed
COPY torrex-init.sh /etc/cont-init.d/99-torrex-seed
RUN chmod +x /etc/cont-init.d/99-torrex-seed

# Jackett listens on 9117 by default. The matching `app_port: 9117` in the
# Space README tells HF to route public traffic here.
EXPOSE 9117

ENV PUID=0 \
    PGID=0 \
    TZ=Etc/UTC \
    AUTO_UPDATE=true
