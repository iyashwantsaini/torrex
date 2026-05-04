#!/usr/bin/with-contenv bash
# Torrex post-start seeder.
# Runs in parallel with Jackett under s6-overlay (services.d). Polls until
# the API is up, then POSTs default config for each indexer in
# /seed/indexers.txt. s6 services must not exit, so we sleep at the end.
#
# Auth model: once an admin password is set, Jackett's /api/v2.0/indexers/*/config
# admin endpoints redirect unauthenticated requests to /UI/Login, even when
# ?apikey=... is present (apikey only authorizes Torznab read endpoints).
# So we POST the password to /api/v2.0/server/logon first to grab the
# Jackett auth cookie and reuse it for the admin calls.

set -u

API_KEY="${JACKETT_API_KEY:-}"
ADMIN_PWD="${JACKETT_ADMIN_PASSWORD:-}"
SEED_FILE=/seed/indexers.txt
BASE=http://127.0.0.1:9117
COOKIE_JAR=/tmp/torrex-seed-cookies

if [ -z "$API_KEY" ] || [ ! -f "$SEED_FILE" ]; then
    echo "[torrex-seed] nothing to do (api_key=${API_KEY:+set} seed=$SEED_FILE)"
    exec sleep infinity
fi

# 1. Wait for Jackett. Hit the dashboard root since admin endpoints require
#    auth and the torznab probe needs an indexer that may not exist yet.
echo "[torrex-seed] waiting for Jackett..."
for i in $(seq 1 90); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/UI/Dashboard")
    if [ "$code" = "200" ] || [ "$code" = "302" ]; then
        echo "[torrex-seed] Jackett is up after ${i}s (HTTP $code)"
        break
    fi
    sleep 2
done

# 2. Log in if an admin password is set. Try the JSON logon endpoint (newer
#    Jackett) and the legacy form POST; whichever works seeds the cookie jar.
rm -f "$COOKIE_JAR"
if [ -n "$ADMIN_PWD" ]; then
    echo "[torrex-seed] logging in..."
    curl -s -c "$COOKIE_JAR" -o /dev/null \
        -H "Content-Type: application/json" \
        -X POST "$BASE/api/v2.0/server/logon" \
        -d "{\"password\":\"$ADMIN_PWD\"}" || true
    curl -s -b "$COOKIE_JAR" -c "$COOKIE_JAR" -o /dev/null \
        -X POST "$BASE/UI/Dashboard" \
        --data-urlencode "password=$ADMIN_PWD" || true
    if grep -q Jackett "$COOKIE_JAR" 2>/dev/null; then
        echo "[torrex-seed] login OK"
    else
        echo "[torrex-seed] login produced no cookie - admin endpoints may 302"
    fi
fi

AUTH_OPTS=(-b "$COOKIE_JAR" -c "$COOKIE_JAR")

# 3. For each desired indexer, fetch its default config schema and POST it
#    back. Jackett interprets that as "configure with defaults" - exactly
#    right for public indexers.
ok=0; fail=0
while IFS= read -r line; do
    id="${line%%#*}"
    id="$(echo -n "$id" | tr -d '[:space:]')"
    [ -z "$id" ] && continue

    cfg_path="/config/Jackett/Indexers/${id}.json"
    if [ -f "$cfg_path" ]; then
        echo "[torrex-seed] $id already configured, skipping"
        continue
    fi

    echo "[torrex-seed] configuring $id..."
    schema=$(curl -fsSL "${AUTH_OPTS[@]}" \
        "$BASE/api/v2.0/indexers/$id/config?apikey=$API_KEY") || {
        echo "[torrex-seed]   ! could not fetch schema for $id"
        fail=$((fail+1)); continue
    }

    resp_code=$(curl -sL "${AUTH_OPTS[@]}" -o /tmp/seed-resp -w "%{http_code}" \
        -X POST "$BASE/api/v2.0/indexers/$id/config?apikey=$API_KEY" \
        -H "Content-Type: application/json" \
        -d "$schema")
    if [ "$resp_code" = "204" ] || [ "$resp_code" = "200" ]; then
        echo "[torrex-seed]   ok ($resp_code)"
        ok=$((ok+1))
    else
        body=$(head -c 200 /tmp/seed-resp 2>/dev/null)
        echo "[torrex-seed]   ! $id failed: HTTP $resp_code $body"
        fail=$((fail+1))
    fi
done < "$SEED_FILE"

echo "[torrex-seed] done. ok=$ok fail=$fail"
exec sleep infinity
