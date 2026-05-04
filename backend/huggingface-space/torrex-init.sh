#!/usr/bin/with-contenv bash
# Torrex pre-start init - runs before Jackett (s6-overlay cont-init.d).
#
# We bake APIKey, InstanceId and AdminPassword directly into
# ServerConfig.json so a fresh HF rebuild boots into a fully
# pre-authenticated Jackett:
#   - APIKey       = $JACKETT_API_KEY  (Torznab key the app uses)
#   - InstanceId   = $JACKETT_API_KEY  (re-used as a stable salt; Jackett
#                                       only requires it to be a non-empty
#                                       string and uses it as the password
#                                       hash salt)
#   - AdminPassword = SHA512( UTF-16LE( InstanceId + plain_password ) )
#                     in uppercase hex with no separators - this is exactly
#                     what Jackett's SecurityService.HashPassword produces.
#
# Doing this here (cont-init.d, before Jackett starts) avoids the API
# chicken-and-egg where /api/v2.0/server/adminpassword requires auth to set
# the password.

set -e

CONFIG_DIR=/config/Jackett
SERVER_CONFIG=$CONFIG_DIR/ServerConfig.json
mkdir -p "$CONFIG_DIR"

API_KEY="${JACKETT_API_KEY:-}"
ADMIN_PWD="${JACKETT_ADMIN_PASSWORD:-}"

if [ -z "$API_KEY" ]; then
    echo "[torrex-init] no JACKETT_API_KEY set - skipping config bake"
    chmod -R 0777 /config
    exit 0
fi

# Compute Jackett's password hash if a password is provided.
# Jackett uses: SHA512( UTF-16LE(InstanceId + plain) ) as uppercase hex.
# We re-use the API key as InstanceId so it's a stable known salt.
PWD_HASH=""
if [ -n "$ADMIN_PWD" ]; then
    if command -v python3 >/dev/null; then
        PWD_HASH=$(python3 - <<PY
import hashlib, os
salt = os.environ['JACKETT_API_KEY']
pwd  = os.environ['JACKETT_ADMIN_PASSWORD']
h = hashlib.sha512((salt + pwd).encode('utf-16le')).hexdigest().upper()
print(h)
PY
)
        echo "[torrex-init] computed admin password hash (len=${#PWD_HASH})"
    else
        echo "[torrex-init] python3 missing - cannot pre-hash password"
    fi
fi

# Write ServerConfig.json. We always overwrite since the env values are the
# source of truth - that's the whole point of this image.
cat > "$SERVER_CONFIG" <<JSON
{
  "Port": 9117,
  "AllowExternal": true,
  "APIKey": "$API_KEY",
  "InstanceId": "$API_KEY",
  "AdminPassword": "$PWD_HASH",
  "UpdateDisabled": false,
  "UpdatePrerelease": false,
  "BasePathOverride": "",
  "BaseUrlOverride": "",
  "OmdbApiKey": "",
  "OmdbApiUrl": "",
  "ProxyType": 0,
  "ProxyUrl": "",
  "ProxyPort": null,
  "ProxyUsername": "",
  "ProxyPassword": "",
  "FlareSolverrUrl": "",
  "FlareSolverrMaxTimeout": 55000,
  "CacheEnabled": true,
  "CacheTtl": 2100,
  "CacheMaxResultsPerIndexer": 1000
}
JSON

echo "[torrex-init] wrote ServerConfig.json (api_key set, password ${PWD_HASH:+set}${PWD_HASH:-empty})"
chmod -R 0777 /config
