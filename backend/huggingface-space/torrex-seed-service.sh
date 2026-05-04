#!/usr/bin/with-contenv bash
# Torrex post-start seeder.
# Runs in parallel with Jackett under s6-overlay (services.d).
# By the time we get here, torrex-init.sh has already pre-baked
# ServerConfig.json with APIKey + InstanceId + AdminPassword hash, so
# Jackett comes up with the password already set. We just need to log in
# (form POST to /UI/Dashboard) to get a session cookie, then POST default
# config for each indexer in /seed/indexers.txt.
# s6 services must not exit, so we sleep at the end.

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

# Wait for Jackett to be reachable.
echo "[torrex-seed] waiting for Jackett..."
for i in $(seq 1 90); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/UI/Dashboard")
    if [ "$code" = "200" ] || [ "$code" = "302" ]; then
        echo "[torrex-seed] Jackett is up after ${i}s (HTTP $code)"
        break
    fi
    sleep 2
done

# Log in. Try a few times - first request after startup occasionally races
# the auth subsystem.
rm -f "$COOKIE_JAR"
login_ok=0
if [ -n "$ADMIN_PWD" ]; then
    for attempt in 1 2 3 4 5; do
        rm -f "$COOKIE_JAR"
        curl -s -c "$COOKIE_JAR" -o /dev/null \
            -X POST "$BASE/UI/Dashboard" \
            --data-urlencode "password=$ADMIN_PWD" || true
        if [ -s "$COOKIE_JAR" ] && grep -qE '^[^#].*Jackett' "$COOKIE_JAR"; then
            echo "[torrex-seed] login OK (attempt $attempt)"
            login_ok=1
            break
        fi
        sleep 2
    done
    if [ $login_ok -ne 1 ]; then
        echo "[torrex-seed] WARNING: login never succeeded - admin endpoints will 302 and seed will fail"
    fi
else
    # No password - admin endpoints are open. Empty cookie jar is fine.
    touch "$COOKIE_JAR"
fi

AUTH_OPTS=(-b "$COOKIE_JAR" -c "$COOKIE_JAR")

# For each indexer, fetch its default config schema and POST it back.
# Jackett interprets that as "configure with defaults" - exactly right for
# public indexers.
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
