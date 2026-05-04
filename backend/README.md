# Backend

Two ways to run the Torznab backend that powers the Torrex app.

## Recommended: Hugging Face Space (free, no credit card)

See [`huggingface-space/README.md`](huggingface-space/README.md) for the
manifest itself.

You don't have to upload anything by hand — this repo ships a workflow
([`.github/workflows/deploy-backend.yml`](../.github/workflows/deploy-backend.yml))
that mirrors `backend/huggingface-space/` to your Space on every
`backend-v*` tag (or via manual dispatch).

**One-time setup:**

1. Create the Space (empty Docker SDK, public):
   <https://huggingface.co/new-space> → name e.g. `torrex-backend`.
2. Generate an HF access token with **write** scope:
   <https://huggingface.co/settings/tokens>.
3. Add three repo secrets in GitHub
   (`Settings → Secrets and variables → Actions`):
   - `HF_TOKEN` — the token from step 2
   - `HF_USERNAME` — your HF username
   - `HF_SPACE` — the Space name from step 1
4. Trigger the deploy:
   ```pwsh
   git tag backend-v1
   git push origin backend-v1
   ```
   …or run **Actions → Deploy backend to Hugging Face → Run workflow**.

The Space rebuilds automatically (≈3–5 min). Plug the Space URL +
Jackett API key into the app's Settings.

## Local / self-hosted

```pwsh
cd backend
docker compose up -d
# open http://localhost:9117
```

State is persisted under `backend/data/` (gitignored).

## Why Jackett (and not Prowlarr)?

Both speak the same Torznab API the app consumes, but Jackett is leaner
(~150 MB RAM) and fits the Hugging Face Space free tier comfortably. If you
self-host on a real VM, Prowlarr is also a great choice — point the app at
its `/<base>/api/v1/indexer/...` Torznab endpoint.
