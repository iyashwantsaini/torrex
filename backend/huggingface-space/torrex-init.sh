#!/usr/bin/with-contenv bash
# Torrex pre-start init — runs before Jackett (s6-overlay cont-init.d).
# Stamps a stable APIKey into ServerConfig.json so the Torznab key
# survives HF Space rebuilds (otherwise Jackett generates a fresh one
# on every clean install).

set -e

CONFIG_DIR=/config/Jackett
SERVER_CONFIG=$CONFIG_DIR/ServerConfig.json

mkdir -p "$CONFIG_DIR"

if [ -n "${JACKETT_API_KEY:-}" ]; then
    if [ ! -f "$SERVER_CONFIG" ]; then
        cat > "$SERVER_CONFIG" <<JSON
{
  "Port": 9117,
  "AllowExternal": true,
  "APIKey": "$JACKETT_API_KEY"
}
JSON
        echo "[torrex-init] created ServerConfig.json with stable API key"
    elif grep -q '"APIKey"' "$SERVER_CONFIG"; then
        sed -i -E "s|\"APIKey\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"APIKey\": \"$JACKETT_API_KEY\"|" "$SERVER_CONFIG"
        echo "[torrex-init] patched APIKey in ServerConfig.json"
    fi
fi

chmod -R 0777 /config
