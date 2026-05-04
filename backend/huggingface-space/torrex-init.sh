#!/usr/bin/with-contenv bash
# Torrex seed init — runs once before Jackett starts (s6-overlay cont-init.d hook).
#
# - Copies any indexer JSONs from /seed/Indexers/ to /config/Jackett/Indexers/
#   *only if the destination file doesn't already exist*. This means user-added
#   indexers persist across container restarts within the same lifetime, but
#   the seeded ones are guaranteed present after every HF rebuild.
# - If JACKETT_API_KEY env var is set, writes/patches ServerConfig.json so the
#   Torznab API key stays stable across rebuilds. Without this, Jackett
#   regenerates a new random key every fresh install and the app breaks.
# - If JACKETT_ADMIN_PASSWORD is set, writes its bcrypt-style hash so the
#   admin UI is locked from the first boot.
#
# Set both via Hugging Face Space → Settings → Variables and secrets
# (use *Secrets*, not Variables, so they don't appear in build logs).

set -e

CONFIG_DIR=/config/Jackett
INDEXERS_DIR=$CONFIG_DIR/Indexers
SERVER_CONFIG=$CONFIG_DIR/ServerConfig.json

mkdir -p "$INDEXERS_DIR"

# 1. Seed indexers (don't clobber user changes).
if [ -d /seed/Indexers ]; then
    for src in /seed/Indexers/*.json; do
        [ -e "$src" ] || continue
        name=$(basename "$src")
        dst="$INDEXERS_DIR/$name"
        if [ ! -f "$dst" ]; then
            cp "$src" "$dst"
            echo "[torrex-seed] installed $name"
        fi
    done
fi

# 2. Stable API key. Jackett's ServerConfig.json is created by Jackett on
#    first run; we generate a minimal one if missing, otherwise we patch it.
if [ -n "$JACKETT_API_KEY" ]; then
    if [ ! -f "$SERVER_CONFIG" ]; then
        cat > "$SERVER_CONFIG" <<JSON
{
  "Port": 9117,
  "AllowExternal": true,
  "APIKey": "$JACKETT_API_KEY"
}
JSON
        echo "[torrex-seed] created ServerConfig.json with stable API key"
    else
        # Patch in place — sed is fine, the field is on a single line.
        if grep -q '"APIKey"' "$SERVER_CONFIG"; then
            sed -i -E "s|\"APIKey\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"APIKey\": \"$JACKETT_API_KEY\"|" "$SERVER_CONFIG"
        else
            sed -i -E "s|^\{|\{ \"APIKey\": \"$JACKETT_API_KEY\",|" "$SERVER_CONFIG"
        fi
        echo "[torrex-seed] patched APIKey in existing ServerConfig.json"
    fi
fi

# 3. Stable admin password (only if you supplied a *bcrypt* hash).
#    Generate one locally with: htpasswd -bnBC 10 "" 'YourPasswordHere' | tr -d ':\n'
if [ -n "$JACKETT_ADMIN_PASSWORD_HASH" ] && [ -f "$SERVER_CONFIG" ]; then
    # Replace AdminPassword field; harmless if the field already exists.
    if grep -q '"AdminPassword"' "$SERVER_CONFIG"; then
        sed -i -E "s|\"AdminPassword\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"AdminPassword\": \"$JACKETT_ADMIN_PASSWORD_HASH\"|" "$SERVER_CONFIG"
    fi
fi

chmod -R 0777 /config
