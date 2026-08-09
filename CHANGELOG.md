# Changelog

All notable changes to Torrex are recorded here.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Web (Vercel deployment)

### [vercel-v2] – 2026-05-05

#### Live
- Production URL: <https://torrex.vercel.app>

### [vercel-v1] – 2026-05-05

#### Added
- `vercel.json` + `scripts/vercel-install.sh` + `scripts/vercel-build.sh`
  for one-click Vercel deployment of the Flutter web build. Installs
  pinned Flutter (3.41.9), runs `flutter build web --release --wasm` for
  best fidelity, serves `app/build/web` as a static SPA with immutable
  caching for hashed assets and SPA-style rewrite to `/index.html`.

## App

### [0.3.1] – 2026-08-09

#### Fixed
- **Movies & TV grid ignored the window size.** The poster grid hardcoded
  `crossAxisCount: 2`, so a maximised desktop window rendered two enormous
  posters instead of a catalog. Column count is now derived from the
  available width (~190dp per tile, clamped to 2–8), giving 2 columns on a
  phone, ~5 on a tablet and 7–8 on a wide desktop window.
- **Filter sheet threw four framework assertions on current Flutter.**
  `WlmSwitchTile` (wolwoloom 0.3.4) nests a `SwitchListTile` inside
  `WlmCard`'s coloured `DecoratedBox`, which trips Flutter's *"ListTile
  background color or ink splashes may be invisible"* assertion added in a
  recent stable. It fires in **every debug build**, not just tests — so
  opening Filters with `flutter run` on an up-to-date SDK produced a red
  screen. The four toggles are now composed directly (card + row + switch,
  no `ListTile`), keeping the same look with nothing for the assertion to
  catch. Upgrading the design system does not help: wolwoloom 0.3.5/0.3.6
  are documentation-only releases.

  This is also why CI went red while the local suite stayed green — the
  workflow tracks `channel: stable` while this machine is pinned to
  3.41.9, which predates the assertion. The regression is now guarded by a
  structural test (`find.byType(ListTile)` must find nothing in the sheet)
  that fails on any SDK version.

#### Added
- Widget tests covering the boolean-option round-trip (tap the row, Apply,
  read the returned filters) and the no-`ListTile` invariant, plus unit
  tests pinning the responsive grid's column count across widths.

### [0.3.0] – 2026-08-09

#### Fixed
- **Searches no longer need two or three attempts.** Three separate
  causes were fixed together:
  - *Races.* Rapid successive searches were unsequenced, so a slow first
    request could land after a newer one and overwrite good results with
    stale empties. Every search now carries a monotonic sequence id and a
    Dio `CancelToken`; superseded responses are cancelled and discarded.
  - *Cold backends.* Jackett behind a sleeping Hugging Face Space answers
    the first request with an HTML holding page, a timeout, or a 200 with
    zero items. The Torznab client now retries transient failures — and
    empty-but-OK bodies — up to three times with backoff, and the receive
    timeout went from 30s to 75s (a cold aggregate search across 20+
    indexers routinely needs more than 30s). A "still searching" callout
    explains the wait instead of leaving the user staring at skeletons.
  - *Misleading empty state.* A completed search that genuinely found
    nothing rendered the same "Type a query above to search" copy as the
    pre-search state, so it looked like nothing had happened. There is now
    a distinct **No results for "…"** state with a retry action.
- `?page=settings` opened the Movies & TV tab instead of Settings (the
  deep-link mapped to index 1, but Settings moved to index 2 when the
  Discover tab was added).
- Tapping **Open** on a magnet with no torrent client installed threw an
  unhandled `PlatformException` on web and some Android OEM builds
  instead of showing the "no app installed" snackbar.
- Result list keys used `bestUri`, which is empty for results that carry
  neither a magnet nor a download URL — they now use a stable `id` that
  falls back through info-hash → link → title.
- Release parsing treated a bare `ISO` as a full-disc video source, so
  `ubuntu-26.04-desktop-amd64.iso` picked up a bogus **COMPLETE** quality
  badge.
- Category inference fell back to the release name even when the indexer
  *had* supplied a category we simply didn't recognise, which filed Linux
  distro images ("OS / Linux") and dataset dumps ("Data / Archive") under
  **Movies**. Release-name inference is now a last resort reserved for
  results with no category at all, and the generic "Video" bucket splits
  into Movies/TV based on whether the title carries a season tag.
- The swarm-health `LinearProgressIndicator` leaked its implicit role up
  the tree, so screen readers announced every result card as a progress
  bar. It's now wrapped in `ExcludeSemantics` — the card's own semantic
  label already describes the swarm in words.

#### Added
- **Filter by indexer, right above the results.** A horizontally
  scrolling facet bar shows every indexer that contributed to the current
  result set with its hit count, plus an "All" reset. Multi-select.
- **Category facets** in the same bar (Movies · TV · Anime · Music ·
  Games · Apps · Books · XXX), derived from Torznab category ids with a
  fallback to the human-readable category string and finally the release
  name. Selecting exactly one category also narrows the *server-side*
  query via Torznab's `cat=` parameter, so the result limit is spent on
  things you actually want.
- **Release-name parsing** (`ReleaseParser`) — resolution, source, codec,
  HDR/Dolby Vision, audio format and channel layout, season/episode,
  release group, language tags, PROPER/REPACK/EXTENDED/3D. Rendered as
  quality badges on every result card, the same way mainstream torrent
  sites do it.
- **Swarm health bar** on each card: a colour-graded seed/leech indicator
  with a Dead → Weak → Fair → Good → Excellent label.
- **Advanced filter sheet**: minimum seeders, min/max size, resolution,
  source, codec, language, indexer, magnet-only, HDR-only, safe mode
  (hide XXX), and a free-text exclude-words field.
- **Duplicate merging.** The same torrent reported by several indexers
  collapses into one row (matched by info-hash, falling back to a
  normalised title + size key), keeping the best swarm numbers and
  showing a "+N sources" badge. Toggleable.
- **More sort options**: relevance, seeders, leechers, size, date and a
  composite quality score — each with an ascending/descending toggle
  (tap the active sort chip to flip it).
- **Recent searches**, persisted and shown on both empty states, with a
  one-tap clear.
- **Pull-to-refresh** on the results list.
- **Configurable page size** (10 / 25 / 50 / 100; was a fixed 10) and a
  **configurable result limit** in Settings (100–1000; was a fixed 100).
- Two new result-card chips: **Health** and **File count**.

#### Changed
- Default result limit raised from 100 to 300 rows per search.
- The two-pane (wide screen) detail view keys off the stable result id, so
  switching between two results that share a link no longer reuses state.
- Unit tests added for the release parser, category mapping, filtering,
  sorting, dedupe and facet counting, plus widget tests covering the
  filter sheet's Apply/Cancel round-trip and result-card rendering.

### [0.2.3] – 2026-05-08

#### Fixed
- **Magnet hand-off restored.** When an indexer's RSS doesn't include a
  `magnet:` URI inline (TPB, EZTV, YTS, TheRARBG via Jackett), Torrex
  now synthesises one client-side from the `infohash` + title +
  trackers that Jackett surfaces in extended mode, and appends a small
  set of well-known public DHT trackers as a fallback. Result: the
  **Open magnet** button always produces a real `magnet:` URI that goes
  straight to Flud / qBittorrent / Transmission, instead of routing
  through Jackett's `/dl` redirect (which was flaky on web and on some
  Android browsers). The .torrent download URL is still kept as a
  secondary fallback.

### [0.2.2] – 2026-05-06

#### Fixed
- TMDB poster / synopsis enrichment now works for **every** indexer, not
  just TheRARBG. The Torznab parser was only keeping the first
  `<category>` element; PTB / Nyaa / EZTV / YTS emit a string category
  ("Video/HD") first instead of a numeric id, so the `isMedia` check
  failed and TMDB was never queried.
- `TorrentResult.isMedia` / `mediaKindHint` also recognise `video`,
  `film`, `anime`, `series`, `S01E02` episode patterns, and bare release
  years — so even category-less feeds get enriched when the filename
  looks like media.

#### Changed
- **Discover → Find torrents** now sends `"Title YEAR"` (e.g.
  `Inception 2010`) instead of just the bare title, so Torznab returns
  the actual release rather than every torrent that happens to share a
  word with the title.
- Backend seed indexer list expanded to: `eztv`, `linuxtracker`,
  `nyaasi`, `thepiratebay`, `therarbg`, `torrentgalaxyclone`, `yts`.

### [0.2.1] – 2026-05-06

#### Fixed
- Onboarding **Continue** button on the credentials step now enables as
  soon as both Base URL and Jackett API key are non-empty. Previously
  the page didn't rebuild while typing because `TextEditingController`
  doesn't trigger `setState` on its own.

### [0.2.0] – 2026-05-06

#### Added
- **Movies & TV tab** powered by TMDB. New third bottom-nav entry that
  shows trending Movies / TV in a 2-column poster grid and lets the
  user search the catalog directly. Tapping a card opens a detail
  screen with backdrop, poster, overview, genres, rating, and — for
  shows — an expandable list of seasons that lazy-loads episodes from
  TMDB on tap. A "Find torrents" CTA bridges back to the Search tab
  with the title pre-filled and the query already running.
- **TMDB enrichment in result detail**. When a result looks like a
  movie or TV episode (Torznab category 2000xxxx / 5000xxxx) and the
  user has a TMDB key configured, the detail page renders an inline
  card with poster, title + year, rating, and a synopsis. Non-media
  results (software, music, ISOs) skip the lookup entirely so we never
  waste API calls.
- **TMDB API key** in Settings (`tmdb.apiKey`, secure storage). Free,
  user-supplied, opt-in; never leaves the device. Includes a "How to
  get a TMDB key" link to themoviedb.org.
- **Customizable result-card chips**. New "Result card" section in
  Settings lets users toggle which chips show under each search result
  (Seeders, Leechers, Size, Age, Indexer, Category, Magnet). Order is
  canonical so the chip row stays predictable.
- **Extended Torznab parsing**. Search now sends `extended=1` and
  parses additional `<torznab:attr>` values: `infohash`, `imdb`,
  `tmdbid`, `tvdbid`, `coverurl`, plus repeated `filename` /
  `filesize` / `tracker` pairs. The detail page renders cover art,
  the file list (with show-more for season packs), and trackers when
  the indexer publishes them.
- **First-launch onboarding wizard** (`features/onboarding/onboarding_page.dart`).
  Three steps: welcome / pick a path → enter creds (Demo skips this) →
  done. Links to the GitHub setup guide for users who don't yet have a
  Jackett backend. Persists `ui.onboardingDone` so it never re-shows.
- **Indexer dropdown in Settings**. The page now calls Jackett's
  `/api/v2.0/indexers?configured=true` whenever creds are filled in and
  exposes a `WlmDropdown` of real indexer names with an "All indexers"
  default. Falls back to a free-text field (the previous UX) when the
  fetch fails or creds are blank. Adds a `Refresh list` button.
- **Adaptive two-pane layout** at viewport width ≥ 900 px. The Search
  tab splits into a result list (5 cols) and an inline detail pane
  (6 cols); tapping a result updates the right pane instead of pushing
  a new route. Mobile keeps the existing single-column flow.
- **Unified theme toggle** as a shared `ThemeToggleButton` widget
  (`app/lib/widgets/theme_toggle_button.dart`). The same icon now
  appears in the top-right of every full-screen surface — Search,
  Settings, Onboarding, Detail — so users have a single, predictable
  way to flip themes from anywhere in the app.
- **GitHub link in Settings** — replaces the verbose "Where do these
  come from?" callout with a single ghost button that opens the repo
  externally, plus the URL printed below in muted text.
- Tooltips on the previously-bare `Back` and `Share link` icon buttons
  for screen-reader / keyboard accessibility, and a `Semantics(button)`
  wrapper on the GitHub link.

#### Removed
- The "On a phone" web hint banner — replaced by clearer install paths
  in Settings and the new Movies & TV tab as a primary mobile-friendly
  surface.

#### Fixed
- **`.torrent` download button**. On web, `launchUrl` was either
  popup-blocked or navigated the SPA away when the indexer's response
  lacked `Content-Disposition`. The button now uses a DOM anchor with
  the `download` attribute (via a conditional-imported helper) so the
  file lands in Downloads. On mobile we keep the existing
  `LaunchMode.externalApplication` path. The button is also hidden
  outright when the indexer didn't include a `.torrent` URL — most
  public trackers (TPB, RARBG, Nyaa) only ship magnets, so a
  permanently-disabled button was just noise.

#### Changed
- `DetailPage` accepts an `embedded: true` flag that omits its
  `WlmAppScaffold` chrome — used by the wide-screen two-pane shell.
- `SearchPage` accepts an optional `onSelect` callback used by the
  shell to show the result inline on wide screens, plus a public
  `runQuery()` hook the AppShell uses to bridge from Discover.
  It also now listens to `SettingsStore` and clears stale results
  when the active backend changes (e.g. on **Exit demo**).
- `SettingsStore` gains `onboardingDone`, `tmdbKey`, and `cardChips`.
- Default `ThemeMode` is now `dark` (was `system`).
- Demo backend is now gated behind a compile-time flag
  (`kAllowDemo` / `--dart-define=ALLOW_DEMO=true`). It defaults on in
  debug builds (`flutter run`) and **off** in release builds. The
  Vercel build script does not pass the flag, so production web no
  longer exposes any demo affordance (onboarding card, settings
  shortcut, or empty-state hint). See README → **Demo mode**.
- Added dependencies: `cached_network_image` (poster/backdrop caching)
  and `flutter_staggered_grid_view` (Movies & TV poster grid).

### [0.1.4] – 2026-05-05

#### Added
- Mobile-web-only callout linking to the latest GitHub APK release.
  Mobile browsers can’t open `magnet:` links, so the Android APK is a
  much better experience there. Dismissible; only shown on web at
  viewport widths < 600px.
- Polished `web/index.html`: real `<title>`, meta description, Open
  Graph + Twitter card tags, canonical link, theme-color, lang attr.
- Polished `web/manifest.json`: proper name, scope, description,
  matching theme/background colors. Cleaner PWA install prompt.
- `robots.txt` + `sitemap.xml` for the Vercel deployment.

### [0.1.3] – 2026-05-05

#### Changed
- Warm-up notice now renders as an inset `WlmCallout` card instead of an
  edge-to-edge `WlmBanner`, so it lines up with the search field and the
  rest of the body content.

#### Added
- Web-only `?warmupDelay=<ms>` URL param to artificially keep the warm-up
  banner visible. Useful for previewing/screenshotting the state when the
  Space is already awake. Capped at 60s. No-op on mobile.

### [0.1.2] – 2026-05-05

#### Added
- **Backend warm-up on launch.** Fires a cheap `GET /UI/Dashboard` against
  the configured backend at app start so Hugging Face Spaces (which sleep
  after ~48h idle and take ~30s to spin up) are awake by the time the
  user hits Search. A thin info banner — “Waking backend…” — is shown
  above the body while the ping is in flight and disappears once the
  Space responds. Re-runs whenever the Base URL is changed in Settings.
  Skipped entirely in demo mode or when no backend is configured.

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
