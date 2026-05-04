---
title: Torrex Backend
emoji: 🧲
colorFrom: indigo
colorTo: gray
sdk: docker
app_port: 9117
pinned: false
---

# Torrex backend (Jackett on Hugging Face Spaces)

This Space runs **Jackett** — a Torznab API server that proxies queries to
500+ torrent indexers — for the [Torrex](https://github.com/iyashwantsaini/torrex)
Flutter app.

## One-time setup

> The fastest path is the CI workflow — see
> [`backend/README.md`](../README.md). It mirrors this folder to your Space
> on every `backend-v*` tag, so you never have to upload files by hand.
>
> The manual steps below remain valid if you just want a one-off Space.

1. **Create a new Space** on https://huggingface.co/new-space
   - SDK: **Docker**
   - Visibility: **Public** (so the app can reach it without an HF token)
2. Upload the contents of this folder (`Dockerfile` + this `README.md`).
3. Wait for the build to finish (≈3–5 min).
4. Open the Space URL → Jackett UI loads.
5. **Set an admin password** (top-right Settings → Admin password). Restart.
6. Add a few indexers (e.g. 1337x, TheRarBg, Nyaa).
7. Copy the **API key** shown on the Jackett dashboard.

## Plug it into the app

In Torrex → Settings:

- **Base URL:** `https://<your-space>.hf.space`
- **API key:** the one from the dashboard
- **Indexer:** `all` (aggregate across every indexer you added)

## Caveats

- Spaces **sleep after 48h idle**. First search after sleep takes ~30s.
- Keep the Space URL low-profile. The Torznab API needs the API key to work,
  but the admin UI is only protected by your password — pick a strong one.
- This is metadata-only. No torrents are downloaded on the Space.

## Persistence across HF rebuilds

Free Spaces have **ephemeral disk** — anything Jackett writes to `/config`
at runtime is wiped when HF rebuilds (≈weekly, or on every deploy).

This image works around that with two small s6-overlay scripts:

1. **`torrex-init.sh`** runs *before* Jackett starts and stamps the
   `JACKETT_API_KEY` env var into `ServerConfig.json`, so the Torznab key
   stays stable across rebuilds. Without this, Jackett generates a new
   random key on every fresh install and the app stops working.
2. **`torrex-seed-service.sh`** runs *in parallel with* Jackett. It logs
   in via the `/UI/Dashboard` form POST (using `JACKETT_ADMIN_PASSWORD`)
   to obtain a session cookie, then for each indexer listed in
   `seed/indexers.txt` it `GET`s the default config schema and `POST`s it
   back — Jackett treats that as "configure with defaults", which is the
   right thing for public indexers. Indexers that are already configured
   are skipped (idempotent).

   `torrex-init.sh` also pre-computes the `AdminPassword` hash that
   Jackett expects — `SHA512(UTF-16LE(password + APIKey))` lowercase hex,
   matching `Jackett.Server/Services/SecurityService.cs` — and writes it
   into `ServerConfig.json`. So the admin password also survives rebuilds
   and you never have to re-enter it in the UI.

### Required Space secrets

Open your Space → **Settings → Variables and secrets → New secret**
(use *Secrets*, not Variables — Variables appear in build logs):

| Name | Value | Notes |
|---|---|---|
| `JACKETT_API_KEY` | any 32-char hex string you choose | Reuse your existing key so the app keeps working without a settings change |
| `JACKETT_ADMIN_PASSWORD` | any password you choose | Used to log in to the Jackett admin UI; also needed by the seed service to authenticate before configuring indexers |

### What ships in `seed/indexers.txt`

The four public indexers known to work without FlareSolverr:

- `linuxtracker` — legal Linux ISOs
- `nyaasi` — anime
- `thepiratebay` — general
- `therarbg` — general / movies / TV

To add more, append the indexer's slug (lowercase ID — find it under
`<base_url>/api/v2.0/indexers` in the JSON `id` field) to that file and
push a new `backend-v*` tag.

> ⚠️ **Never commit private-tracker configs** here. Their on-disk JSONs
> contain your passkey/cookies, and this folder is public on GitHub.
> The API-seeding flow only sends *default* config (no auth fields), so
> private trackers won't work via this path anyway.
