# Torrex

A Flutter torrent-search client built on the
[WolwoLoom](https://github.com/iyashwantsaini/WolwoLoom) design system.
Talks to any **Torznab**-compatible backend (Jackett or Prowlarr), so a single
search hits every indexer you've configured.

> ⚠️ Torrex is metadata only. It searches public Torznab indexers and hands
> magnet links to whatever torrent client you have installed. It does not
> download or seed anything itself. Use it for legal content only.

## Repo layout

```
torrex/
├── app/        # Flutter app (Android + iOS), depends on wolwoloom
└── backend/    # Jackett deployment — Hugging Face Space + docker-compose
```

## Quick start

1. **Stand up a backend** — easiest path is the free Hugging Face Space:
   see [backend/huggingface-space/README.md](backend/huggingface-space/README.md).
2. **Run the app:**
   ```pwsh
   cd app
   flutter pub get
   flutter run
   ```
3. In the app's **Settings** screen, paste the backend URL + Jackett API key.
4. Search.

## Design

- Mono / editorial aesthetic from **WolwoLoom 0.3.4**
- Periwinkle accent, hairline borders, ink-on-paper palette
- Dark + light themes, system-default

## Tech

| Layer       | Choice                              |
|-------------|-------------------------------------|
| UI          | Flutter 3.24+, WolwoLoom            |
| Networking  | Dio                                 |
| Parsing     | `xml` (Torznab is RSS+attrs)        |
| Storage     | shared_preferences + secure_storage |
| Magnet open | url_launcher (`magnet:` intent)     |

## License

MIT — see [LICENSE](LICENSE).
