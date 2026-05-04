#!/usr/bin/with-contenv bash
# Torrex post-start seeder.
# Runs in parallel with Jackett under s6-overlay (services.d). Polls until
# the API is up, sets the admin password if env-provided, logs in, then
# POSTs default config for each indexer in /seed/indexers.txt.
# s6 services must not exit, so we sleep at the end.
#
# Auth model: ?apikey= only authorizes Torznab read endpoints. Admin
# endpoints (config writes, indexer add) require the cookie set by the
# /UI/Dashboard form POST. We do that login here and reuse the cookie jar.

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

# do_login: POSTs the password to /UI/Dashboard and verifies a session
# cookie was issued. Returns 0 on success, 1 otherwise.
do_login () {
    local pwd="$1"
    rm -f "$COOKIE_JAR"
    curl -s -c "$COOKIE_JAR" -o /tmp/seed-login -w "" \
        -X POST "$BASE/UI/Dashboard" \
        --data-urlencode "password=$pwd" >/dev/null 2>&1 || true
    # Curl cookie-jar lines start with the domain; a successful login
    # writes a Jackett auth cookie. Empty jar (only the comment header)
    # means login failed.
    if [ -s "$COOKIE_JAR" ] && grep -qE '^[^#]' "$COOKIE_JAR"; then
        return 0
    fi
    return 1
}

# 1. Wait for Jackett. /UI/Dashboard returns 200 (no pwd) or 302 (locked).
echo "[torrex-seed] waiting for Jackett..."
for i in $(seq 1 90); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/UI/Dashboard")
    if [ "$code" = "200" ] || [ "$code" = "302" ]; then
        echo "[torrex-seed] Jackett is up after ${i}s (HTTP $code)"
        break
    fi
    sleep 2
done

# 2. Try to log in with the env password. If that fails AND a password env
#    is provided, the container is fresh - set the password (open endpoint
#    on a fresh install) then log in.
if [ -n "$ADMIN_PWD" ]; then
    if do_login "$ADMIN_PWD"; then
        echo "[torrex-seed] login OK (existing password)"
    else
        echo "[torrex-seed] login failed - assuming fresh install, setting admin password..."
        code=$(curl -sL -o /tmp/seed-pwd -w "%{http_code}" \
            -X POST "$BASE/api/v2.0/server/adminpassword?apikey=$API_KEY" \
            -H "Content-Type: application/json" \
            -d "\"$ADMIN_PWD\"")
        echo "[torrex-seed] adminpassword set HTTP $code"
        sleep 2
        if do_login "$ADMIN_PWD"; then
            echo "[torrex-seed] login OK (after pwd set)"
        else
            echo "[torrex-seed] login STILL failed - admin endpoints will 302; aborting seed"
            exec sleep infinity
        fi
    fi
fi

AUTH_OPTS=(-b "$COOKIE_JAR" -c "$COOKIE_JAR")

# 3. For each indexer, fetch its default config schema and POST it back.
#    Jackett interprets that as "configure with defaults" - exactly right
#    for public indexers.
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
