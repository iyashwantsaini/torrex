# Changelog

All notable changes to Torrex are recorded here.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## App

### [0.1.1] – 2026-05-05

#### Fixed
- **Release APK could not reach the backend** ("Cannot reach backend. Is the
  URL correct?"). The release Android manifest was missing
  `android.permission.INTERNET` — Flutter only injects it into the `debug`
  and `profile` manifests automatically. Added it to
  `app/android/app/src/main/AndroidManifest.xml`.

### [0.1.0] – 2026-05-05

#### Added
- Initial public release.
- Torznab search against any Jackett / Prowlarr backend.
- Result list with sort (seeders / size / date) and magnet-only filter.
- Detail view with magnet open, .torrent download, copy link, view on
  indexer.
- Settings: backend URL + API key (Keystore-backed) + default indexer +
  theme.
- Demo mode (`Base URL = demo`) for offline previewing.
- Signed APK release pipeline (`v*` tags → 4 ABI-split + universal APKs).

## Backend (Hugging Face Space image)

### [backend-v11] – 2026-05-05

#### Added
- `torrex-init.sh` (s6 `cont-init.d`) pre-stamps `ServerConfig.json` with
  `APIKey`, `InstanceId`, and the SHA-512 `AdminPassword` hash from
  `JACKETT_API_KEY` and `JACKETT_ADMIN_PASSWORD` env vars, so both
  survive HF Space rebuilds.
- `torrex-seed-service.sh` (s6 `services.d`) logs in via the Jackett
  dashboard form, then API-seeds default config for every indexer listed
  in `seed/indexers.txt` (`linuxtracker`, `nyaasi`, `thepiratebay`,
  `therarbg`). Idempotent — already-configured indexers are skipped.
- `deploy-backend.yml` workflow now syncs `JACKETT_API_KEY` and
  `JACKETT_ADMIN_PASSWORD` into the Space's own secrets via the HF API.

#### Notes
- Admin password hash format verified against
  `Jackett.Server/Services/SecurityService.cs`:
  `SHA512(UTF-16LE(password + APIKey))` lowercase hex.
- HF Spaces send permissive CORS headers (reflect `Origin`,
  `Access-Control-Allow-Credentials: true`), so the Flutter web build
  can call the backend cross-origin without a proxy.
