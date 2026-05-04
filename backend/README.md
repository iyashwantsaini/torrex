# Backend

Two ways to run the Torznab backend that powers the Torrex app.

## Recommended: Hugging Face Space (free, no credit card)

See [`huggingface-space/README.md`](huggingface-space/README.md). 5-minute
setup, runs Jackett in a Docker Space on HF's free tier.

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
