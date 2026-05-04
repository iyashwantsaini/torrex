# Torrex · screenshot gallery

All shots captured from the live release web build (`flutter build web --release`)
served over `python -m http.server 8765`, against a portrait viewport of
**511 × 682 logical px** (= 639 × 853 physical at DPR 1.25).

Reproducible from `main` — every screen is reachable via URL params:

| URL | Screen |
|-----|--------|
| `/?theme=light` | Search · empty (no backend configured) |
| `/?theme=dark&demo=1` | Search · results (built-in demo data) |
| `/?theme=light&demo=1` | Search · results · light |
| `/?theme=dark&demo=1&page=detail` | Detail page |
| `/?theme=dark&page=settings` | Settings |

> The `demo=1` query param activates a small in-app sample dataset so the
> design system is visible without standing up a real Jackett/Prowlarr
> backend. It never makes a network call.
>
> The **theme toggle in the top-right of every screen** cycles
> system → light → dark → system.

## Search

| Empty (light) | Results (dark) | Results (light) |
|---|---|---|
| ![](screenshots/01-search-empty-light.png) | ![](screenshots/02-search-results-dark.png) | ![](screenshots/03-search-results-light.png) |

The home screen starts as a single search field — no clutter. **Filters
and sort only appear after the first search** (`SEEDERS / SIZE / DATE`
segmented control, `MAGNET ONLY` toggle chip, results count, and
client-side pagination of 10 per page based on the filter, not on the
indexer's page).

## Detail

| Detail (dark) |
|---|
| ![](screenshots/04-detail-dark.png) |

The detail page uses three [`WlmStat`](../../app/lib/features/detail/detail_page.dart)
big-number tiles for the swarm stats, a spec-row block for metadata, and
two `WlmCodeBlock`s for the info hash and full magnet URI (horizontally
scrollable so they never overflow). Below the visible portion sit four
actions:

1. **Open magnet** → Android system chooser → installed torrent client
2. **Download .torrent** → indexer-hosted blob
3. **Copy link** → clipboard
4. **Indexer page** → original page in browser

## Settings

| Settings (dark) |
|---|
| ![](screenshots/05-settings-dark.png) |

Three uniformly-styled `WlmTextField`s with leading icons (URL, key,
indexer), the API key obscured + clearable, and a `WlmSegmentedControl`
for theme. Persisted via `shared_preferences` + `flutter_secure_storage`
(API key never touches plain prefs).
