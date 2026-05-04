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

This image works around that with a small init script
(`torrex-init.sh`) that runs before Jackett starts:

1. **Indexers** in `seed/Indexers/*.json` are copied into
   `/config/Jackett/Indexers/` on every boot (only if a file with the same
   name doesn't already exist, so manual additions still survive within a
   single container lifetime).
2. **API key** is read from the `JACKETT_API_KEY` env var and stamped into
   `ServerConfig.json`. Without this, Jackett generates a new random key
   on every fresh install and the app breaks.
3. **Admin password hash** is read from `JACKETT_ADMIN_PASSWORD_HASH`
   (optional) so the UI stays gated from the first request.

### Required Space secrets

Open your Space → **Settings → Variables and secrets → New secret**
(use *Secrets*, not Variables — Variables appear in build logs):

| Name | Value | Notes |
|---|---|---|
| `JACKETT_API_KEY` | any 32-char hex string you choose | Reuse your existing key so the app keeps working without a settings change |
| `JACKETT_ADMIN_PASSWORD_HASH` *(optional)* | bcrypt hash of your password | See below |

To generate the bcrypt hash for the admin password (one-liner, requires
`htpasswd` from `apache2-utils` or any bcrypt tool):

```bash
htpasswd -bnBC 10 "" 'YourStrongPassword' | tr -d ':\n'
# copy the output (starts with $2y$10$…)
```

If you don't set `JACKETT_ADMIN_PASSWORD_HASH`, just set the password
once in the UI after the first deploy — it'll then be carried inside the
patched `ServerConfig.json` until the next HF rebuild.

### What ships in `seed/Indexers/`

The four public indexers known to work without FlareSolverr:

- `linuxtracker.json` — legal Linux ISOs
- `nyaasi.json` — anime
- `thepiratebay.json` — general
- `therarbg.json` — general / movies / TV

> ⚠️ **Never commit private-tracker configs** here. Their JSONs contain
> your passkey/cookies, and this folder is public on GitHub.
