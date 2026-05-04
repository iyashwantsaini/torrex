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

- Free Spaces use **ephemeral disk**. After ~weekly rebuilds Jackett's config
  is wiped — you'll have to re-add indexers. To make this stick, fork the
  Space and commit a `ServerConfig.json` plus your `Indexers/` folder.
- Spaces **sleep after 48h idle**. First search after sleep takes ~30s.
- Keep the Space URL low-profile. The Torznab API needs the API key to work,
  but the admin UI is only protected by your password — pick a strong one.
- This is metadata-only. No torrents are downloaded on the Space.
