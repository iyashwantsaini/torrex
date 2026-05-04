#!/usr/bin/with-contenv bash
# Torrex post-start seeder.
# s6-overlay runs everything under /etc/services.d/* in parallel with Jackett,
# so this script polls localhost:9117 until Jackett's API is up, then
# POSTs default config for each indexer listed in /seed/indexers.txt.
# Once it's done seeding it sleeps forever (s6 services must not exit).

set -u

API_KEY="${JACKETT_API_KEY:-}"
SEED_FILE=/seed/indexers.txt
BASE=http://127.0.0.1:9117

if [ -z "$API_KEY" ] || [ ! -f "$SEED_FILE" ]; then
    echo "[torrex-seed] nothing to do (api_key=${API_KEY:+set} seed=$SEED_FILE)"
    exec sleep infinity
fi

# 1. Wait for Jackett to be reachable. Cap at ~3min.
echo "[torrex-seed] waiting for Jackett..."
for i in $(seq 1 90); do
    if curl -fsS "$BASE/api/v2.0/server/config" -H "X-Api-Key: $API_KEY" >/dev/null 2>&1; then
        echo "[torrex-seed] Jackett is up after ${i}s"
        break
    fi
    sleep 2
done

# 2. For each desired indexer, fetch the default config schema and POST it
#    back. Jackett treats that as "configure with defaults", which is exactly
#    what we want for public indexers.
while IFS= read -r line; do
    # strip comments + whitespace
    id="${line%%#*}"
    id="$(echo -n "$id" | tr -d '[:space:]')"
    [ -z "$id" ] && continue

    cfg_path="/config/Jackett/Indexers/${id}.json"
    if [ -f "$cfg_path" ]; then
        echo "[torrex-seed] $id already configured, skipping"
        continue
    fi

    echo "[torrex-seed] configuring $id..."
    schema=$(curl -fsS "$BASE/api/v2.0/indexers/$id/config" -H "X-Api-Key: $API_KEY") || {
        echo "[torrex-seed]   ! could not fetch schema for $id"
        continue
    }

    resp_code=$(curl -s -o /tmp/seed-resp -w "%{http_code}" -X POST \
        "$BASE/api/v2.0/indexers/$id/config" \
        -H "X-Api-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$schema")
    if [ "$resp_code" = "204" ] || [ "$resp_code" = "200" ]; then
        echo "[torrex-seed]   ok ($resp_code)"
    else
        echo "[torrex-seed]   ! $id failed: HTTP $resp_code $(cat /tmp/seed-resp 2>/dev/null | head -c 200)"
    fi
done < "$SEED_FILE"

echo "[torrex-seed] done."
exec sleep infinity
