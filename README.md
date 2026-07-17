# BubbleSearch

Fast, fully local search for your entire iMessage history — a native macOS app that does what Messages' built-in search can't.

Messages search is slow, misses matches, and can't filter. BubbleSearch reads your local `chat.db` (read-only), decodes the message text, and builds its own SQLite FTS5 index for instant full-text search with sender, chat, and date filters — plus an iMessage-style browser with tapbacks, reply threading, link previews, and a per-conversation media gallery.

Everything runs on your Mac. Search never leaves your machine.

## Features

- **Instant full-text search** across every message, with `from`, `in-chat`, and date-range filters (⌘K quick palette + a dedicated Advanced Search tab).
- **iMessage-style browsing** — conversation sidebar with contact photos (incl. group photos/collages), bubble threads with day separators, infinite scroll, tapbacks with Apple's own glyphs, reply quotes, link-preview cards, and a photos/videos grid.
- **Live** — a file-system watcher re-indexes new messages automatically; ⌘R force-reloads.
- **Jump to date**, per-conversation search, keyboard-driven navigation (⌘1/⌘2 tabs, arrow-key sidebar).
- **Auto-updates** via [Sparkle](https://sparkle-project.org).

## Requirements

- macOS 14 or later
- **Full Disk Access** (System Settings → Privacy & Security → Full Disk Access) — needed to read the Messages and Contacts databases. The app has a first-run screen that walks you through it.

## Building

Zero third-party runtime dependencies beyond Sparkle (fetched by SwiftPM); uses the system SQLite.

```sh
cd native
swift run bubblesearch             # dev run (inherits the terminal's Full Disk Access)
./make-app.sh                      # build a signed BubbleSearch.app
./make-dmg.sh                      # build a drag-to-install DMG
swift run bubblesearch --selftest  # engine checks against the live databases
```

Distribution builds are signed with a Developer ID and notarized (`make-dmg.sh` handles it when a `bubblesearch-notary` keychain profile is configured). Without a certificate, builds are ad-hoc signed and run locally.

## How it works

- **`Engine/TypedStream.swift`** — on modern macOS the `message.text` column is almost always empty; the real content lives in `attributedBody`, a NeXTSTEP `typedstream` blob. This decodes it (verified 99.98% on a real database).
- **`Engine/Engine.swift`** — incremental FTS5 indexer keyed on a `ROWID` watermark; filters out tapbacks and group events; resolves contact names/photos from the AddressBook databases. Threads render live from `chat.db`, so attachments, tapbacks, and replies appear without being indexed.
- **`Engine/SQLiteDB.swift`** — a thin wrapper over the system `libsqlite3`.
- The UI is SwiftUI (`UI/`), the engine is actor-isolated, and there are no servers or IPC — it's a single native process.

## Privacy & telemetry

Searching, indexing, and browsing are entirely local — your messages, contacts, and queries never leave your Mac.

The app sends one small usage ping per day: a persistent install ID, the app version, and your macOS version (and, because the ID persists, your IP / approximate location are recorded server-side). Never message content, contacts, or search queries. You can turn it off in **Settings** (⌘,).

## License

MIT — see [LICENSE](LICENSE).

The tapback glyphs are Apple's artwork, loaded at runtime from your own macOS frameworks and **not** redistributed in this repository.
