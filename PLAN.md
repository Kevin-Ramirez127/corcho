# Corcho-RS — Rust + Qt6 Native Rewrite

## 1. Objective

Rebuild the Corcho / Corcho v1.20.0 feature set as a **native Linux desktop app** in **Rust** with **Qt 6**, replacing the Electron/Chromium shell.

- **Shell/UI:** Qt Quick (QML) — GPU-rendered, native window, no Electron, no bundled web shell.
- **Logic:** Rust owns the model, storage, AI, sync, integrations.
- **Web content:** QtWebEngine is embedded *only* for website cards (the original app needs a real browser engine there).
- **Targets:** Linux first (AppImage, DEB, Flatpak). Keep macOS/Windows buildable but out of scope for v1.

Non-goals for v1: cloud account service, mobile, web version, byte-for-byte UI clone, reusing proprietary assets.

---

## 2. Verified environment (this machine)

| Tool | Version |
|---|---|
| Rust | 1.99.1 |
| Cargo | 1.99.1 |
| CMake | 4.4.4 |
| Qt | 6.12.0 |
| QML modules | QtQuick, QtQuick3D, QtWebEngine, QtMultimedia, QtNetwork, QtQml, QtTest, QtDBus |
| QML dev | `Qt6QmlImportScanner`, `Qt6LinguistTools` present |

Bridge library: **cxx-qt 0.10** (KDAB) — supports all Qt 6, MSRV 1.85, `QAbstractListModel`, QObject signal/slot, Qt threading. Clone used for reference: `KDAB/cxx-qt`.

**Do not clone Qt or the Rust toolchain** — Qt source is ~several GB and unnecessary; use the installed Qt dev packages + docs. Clone only small binding repos when an API is unclear (cxx-qt done).

### Feasibility spike result
`examples/qml_minimal` from cxx-qt **configures and builds** against the installed Qt 6.12 (see build log verification). This de-risks the core stack.

---

## 3. Architecture

```
┌───────────────────────────────────────────────┐
│ Qt Quick (QML)                                │
│  Shell · Canvas · Cards · Dialogs · Powerbar  │
│  QtWebEngine (website cards)                  │
│  QtQuick3D (Artifact/Hypercube fragments)     │
└───────────────▲───────────────┬───────────────┘
                │ signals        │ invoke()
┌───────────────┴───────────────▼───────────────┐
│ cxx-qt bridge (QObject / QAbstractListModel)  │
└───────────────▲───────────────────────────────┘
                │
┌───────────────┴───────────────────────────────┐
│ Rust core                                      │
│  model · storage · history · search            │
│  ai · sync · backups · integrations            │
│  tokio runtime · reqwest · zbus · cpal         │
└────────────────────────────────────────────────┘
```

Design rules:
1. **Rust is the source of truth.** QML never owns persistent state.
2. **QML owns transient interaction state** (drag delta, zoom animation). Commit to Rust on release/debounce for 60 fps.
3. **Async in Rust:** tokio tasks → `qt_thread().queue(...)` → Qt signal. Never block the GUI thread.
4. **Small C++ shims allowed** where Qt exposes no Rust binding (e.g. `QWebEngineUrlRequestInterceptor`, global shortcuts portal). Keep them tiny and isolated in `cpp/`.

---

## 4. Repository layout

```
corcho-rs/
├─ Cargo.toml                    # workspace
├─ CMakeLists.txt                # top-level Qt/cxx-qt build
├─ CMakePresets.json
├─ README.md
├─ crates/
│  ├─ app/                       # binary: main.rs, QML registration, cxx-qt bridges
│  ├─ model/                     # Grid, Card, Folder, Settings, Theme, History
│  ├─ storage/                   # JSON store, atomic writes, backups, import/export
│  ├─ sync/                      # folder sync, Google Drive, conflicts
│  ├─ ai/                        # providers, streaming, prompts, context
│  └─ integrations/              # mpris, script runner, adblock, updates, license, hotkeys
├─ cpp/                          # minimal C++ shims (WebEngine interceptor, portal)
├─ qml/
│  ├─ Main.qml
│  ├─ shell/                     # Sidebar, Topbar, StatusBar, MobileShell
│  ├─ canvas/                    # CanvasView, CardLayer, Minimap, Selection
│  ├─ cards/                     # Note, Website, Bookmark, ApiData, Ai, Script,
│  │                             # Fragment, GridLink, Checklist, Kanban,
│  │                             # Whiteboard, Pomodoro, Mpris
│  ├─ fragments/                 # Haptic, Nebula, Spectrum, Artifact, Boson,
│  │                             # Vector, Calendar, Hypercube
│  ├─ dialogs/                   # Settings*, Powerbar, ContextMenu, Tutorials,
│  │                             # Onboarding, License, Update, Changelog
│  └─ style/                     # Themes.qml, Fonts.qml, Icons.qml, Metrics.qml
├─ assets/                       # fonts/, icons/lucide/, images/
├─ tests/                        # Rust unit/integration, QML (QtQuickTest)
└─ packaging/                    # appimage/, deb/, flatpak/
```

---

## 5. Data model & persistence

```rust
struct Workspace { grids: Vec<Grid>, folders: Vec<Folder>, settings: Settings }

struct Grid { id, name, folder_id, min_x/min_y/max_x/max_y, cards: Vec<Card>, view: ViewState }

struct Card { id, kind: CardKind, x: f32, y: f32, w: f32, h: f32,
              color, icon, title, locked: bool, payload: serde_json::Value }

enum CardKind { Note, Website, Bookmark, ApiData, Ai, Script,
                Fragment, GridLink, Checklist, Kanban, Whiteboard, Pomodoro, Mpris }
```

- **Store:** one JSON file per grid (`grids/<id>.json`) + `workspace.json` + `settings.json`, atomic write (temp + rename), `.bak` rotation. Same shape as the original for easy migration.
- **History:** append-only command log with inverse ops; cap `undoSteps` (default 20). Snapshot fallback for large structural changes.
- **Search:** in-memory index rebuilt from cards (title/text/tags). Upgrade to `tantivy` only if needed.
- **Backups:** `.corcho` ZIP via `zip`; optional AES-GCM + Argon2 passphrase.
- **Migration:** importer for the original `Nova`/`.nova` data folder and `.corcho` backups.

---

## 6. Rust ↔ Qt bridge

- `AppController` (QObject) — `#[qinvokable]` methods: `create_card`, `delete_card`, `move_card`, `resize_card`, `duplicate_card`, `switch_grid`, `create_folder`, `rename_*`, `set_theme`, `run_powerbar`, `open_settings`, `connect_ai`, etc.
- `GridListModel` / `CardListModel` — `QAbstractListModel` (cxx-qt todo_app pattern). Card role returns a `QVariantMap` for heterogeneous payloads; QML delegates by `kind`.
- `SettingsObject` — Q_PROPERTY-backed settings with `changed` signals.
- Async streams (AI tokens, download progress, sync status) emit Qt signals from tokio via `qt_thread()`.
- High-frequency drag/resize stays in QML; one `commit_card_geometry` call per gesture end.

---

## 7. Subsystem design

### 7.1 Canvas / grid (`qml/canvas`)
- Custom QQuickItem/`Flickable`-based infinite canvas: world transform (scale/offset), z-ordered card layer, minimap, marquee selection.
- Pan/zoom (50–200 % + reset), grid snap/magnetism, ripple, parallax, spawn animations.
- Cards as QML components positioned by world coords; only visible cards instantiated (virtualisation).
- Undo/redo wired to Rust history.

### 7.2 Cards
| Card | Implementation |
|---|---|
| Note | QML `TextEdit` rich text (bold/italic/underline/strike, headings, lists, task lists, tables, code, links, images/video/PDF/file embeds). Markdown parse/serialize in Rust (`comrak`) for portability. |
| Website | QML `WebEngineView` + per-site `WebEngineProfile` (storageName), nav/zoom controls, scroll memory, link behaviour integrated/browser, adblock shim. |
| Bookmark | Compact website variant with metadata fetch (`reqwest` + `scraper`/`html5ever`). |
| API Data | `reqwest` fetch, JSON field mappings, test fetch, refresh timer. |
| AI | Provider/model/prompt/config, streaming, context injection, field mappings, refresh schedule. |
| Script | `tokio::process::Command` in `/bin/sh` (feature-flagged and sandboxed; menu disabled by default like upstream). |
| Fragment | see 7.4. |
| Grid Link | Rust model navigation + canvas switch. |
| Checklist | QML list model, reorder, progress. |
| Kanban | Columns + drag/drop, per-column limits. |
| Whiteboard | QML `Canvas`/`Shape` strokes, pen/eraser/colour/width, stroke persistence. |
| Pomodoro | Rust timer service (survives view recreation), work/break/sessions. |
| MPRIS | `mpris`/`zbus` (preferred over invoking `playerctl`); fallback to `playerctl` via process runner. |

### 7.3 AI (`crates/ai`)
- Providers: Anthropic, OpenAI, Google Gemini, xAI Grok, Mistral, local OpenAI-compatible server.
- `reqwest` + rustls, SSE streaming via `eventsource-stream`; validated API keys; per-provider model lists (port the v1.20 list).
- Context injection from linked Notes/Websites; web-search toggle; refresh intervals.
- Proxy through Rust (no keys in QML).

### 7.4 Fragments
- **Haptic** — QML pressure/release interaction + elastic animation.
- **Nebula** — animated mesh gradient (`ShaderEffect`/`Canvas`).
- **Spectrum** — noise + pure-tone synth via `cpal` in Rust (low latency) with volume/tone controls.
- **Artifact / Hypercube** — QtQuick3D wireframe meshes (cube, icosahedron, torus, hypercube).
- **Boson** — particle field in `ShaderEffect`/`Canvas` with pointer ripples.
- **Vector** — time-passage visual.
- **Calendar** — QML calendar fragment.
- **Haptic/Nebula/Spectrum/Artifact/Boson/Vector/Calendar/Hypercube** all with persisted config.

### 7.5 Web / adblock (`crates/integrations` + `cpp/`)
- Per-website persistent `WebEngineProfile` (isolated storage/cookies).
- `adblock-rust` (Brave) filter engine + tiny `QWebEngineUrlRequestInterceptor` C++ shim.
- Cookie/debug panel incl. the **"Simulate Attack"** self-test (reimplement in a sandboxed test profile).
- Permission handler, window-open handler, clear-partition-data.

### 7.6 Sync, backup, data (`crates/sync`, `crates/storage`)
- **Folder sync** provider: any local/cloud-mounted directory (works for iCloud Drive on macOS, Nextcloud/Dropbox mounts on Linux) via `notify` watcher + debounce. This replaces the macOS-only iCloud helper on Linux.
- **Google Drive**: `oauth2` (PKCE, local redirect) + `reqwest` Drive v3 `appDataFolder`; refresh tokens; conflict backup files; delete/clear data.
- Conflict resolution: mtime + content hash + `.backup_<ts>` like upstream; never overwrite on unknown cloud state.
- Import/export `.corcho` ZIP; selective wipe; data-folder selection.

### 7.7 Updates, licensing, OS integration
- Updater: GitHub Releases (`reqwest` + `semver`), channels **stable/beta/experimental**, mandatory-update gate, AppImage/DEB installer strategy per package type.
- Licensing: Gumroad verify (`reqwest`), grace period/offline token, "Corcho / Corcho" feature gate.
- Launch-at-startup (XDG autostart / portal), single instance (D-Bus name), `corcho://`/`corcho://` protocol handler, native file dialogs, About panel, changelog.
- Global Powerbar hotkey via XDG `GlobalShortcuts` portal (`ashpd`) with X11 fallback.
- MPRIS card, media art cache, clipboard, open-in-browser.

### 7.8 UI shell
- Sidebar (grids, folders, sync indicator, settings, powerbar), topbar, status bar, responsive/mobile layout.
- Powerbar (command palette): grids/cards search, create commands, zoom, undo/redo, themes, easter eggs.
- Settings — General / Interface / Appearance / Data / AI / Security / About, porting all options from §11 of the inventory.
- Themes: 17 standard + custom editor + unlockable Plasma/Pulsar; 14 fonts; opacity, audio, visual-effect toggles.
- Tutorials/onboarding, splash, easter eggs (unlock Hypercube/Plasma/Pulsar), changelog, legal links, analytics **opt-in** with local diagnostics buffer.

---

## 8. Feature coverage matrix

Everything in the inventory maps as follows. Nothing is dropped; OS-specific items are substituted.

| Area | Coverage |
|---|---|
| Canvas/grid (pan, zoom, snap, magnet, ripple, parallax, minimap, folders, grid links, lock, undo/redo) | Full — QML + Rust |
| 12 card types | Full |
| 8 fragment modes | Full (QtQuick3D + QML + cpal) |
| 17 themes + custom + 2 unlockable, 14 fonts, opacity/volume/effects | Full |
| AI: 5 providers + local, model lists, streaming, web search, refresh, context injection, stats | Full |
| Website cards: webview/bookmark/API, isolated sessions, nav/zoom, scroll memory, adblock, cookie debug, attack sim | Full |
| Cloud sync: folder provider (iCloud substitute) + Google Drive, conflicts, indicator, troubleshoot | Full |
| Backups import/export, data folder, migration, wipe/reset | Full |
| Updates: channels, auto modes, mandatory flow, changelog | Full |
| Licensing: Gumroad activate/validate/grace/clear | Full |
| Powerbar + tutorials + onboarding + easter eggs + legal + diagnostics + analytics (opt-in) | Full |
| MPRIS/now-playing | Full (`mpris`/zbus + playerctl fallback) — Linux |
| Script card `/bin/sh` | Full, disabled-by-default menu entry like upstream |
| Debug tools (test data, simulated failures, mandatory-update test, memory/logs) | Full behind `--debug`/dev build |

**Deliberate substitutions:**
- macOS-only iCloud helper and `Corcho.app` handoff → generic folder sync + documented macOS path (build target).
- Electron auto-updater → GitHub-release updater per packaging format.
- Amplitude SDK → opt-in telemetry (own sender or Sentry), default off.

---

## 9. Key dependencies (crates)

`cxx-qt`, `cxx-qt-lib`, `cxx-qt-build`, `serde`, `serde_json`, `tokio`, `reqwest` (rustls), `eventsource-stream`, `futures`, `notify`, `zip`, `aes-gcm`, `argon2`, `mpris`/`zbus`, `adblock-rust`, `oauth2`, `semver`, `uuid`, `time`/`chrono`, `anyhow`, `thiserror`, `tracing`, `tracing-subscriber`, `comrak`, `html5ever`/`scraper`, `cpal`, `ashpd` (portal), `rand`, `base64`, `image`, `open`/`QDesktopServices`, `keyring` (optional license token), `directories`.

Keep the dependency surface small; prefer Qt for rendering/OS and Rust for logic.

---

## 10. Milestones

Sizing assumes one developer; rough, not a commitment.

**M0 — Spike (S).** cxx-qt window + QML shell + one `CardListModel` + create/move/delete card + JSON persistence. *Accept:* card survives restart; `cargo test` + QML smoke test pass.

**M1 — Canvas & core model (M).** Grids, folders, pan/zoom, snap, minimap, undo/redo, sidebar, contexts. *Accept:* 200-card grid at 60 fps; undo/redo 20 steps.

**M2 — Productivity cards (M).** Note, Checklist, Kanban, Whiteboard, Pomodoro, Grid Link, Script (flagged). *Accept:* all persist and edit correctly.

**M3 — Web cards & adblock (M).** Website/Bookmark/API Data, profiles, nav, adblock, cookie debug. *Accept:* site isolation + adblock verified against a test site.

**M4 — AI (M).** Providers, streaming, AI cards, context injection, refresh, stats. *Accept:* streaming from each provider (mock in CI) + local server.

**M5 — Fragments (M).** Haptic, Nebula, Spectrum (audio), Artifact/Boson/Vector, Calendar, Hypercube. *Accept:* stable frame times; audio synth works.

**M6 — Sync/data (M).** Folder sync + Google Drive, conflicts, backups, import/export, migration. *Accept:* two-instance convergence test + conflict backup.

**M7 — Platform (M).** Updates, licensing, launch-at-startup, protocol, hotkey, single instance, MPRIS, analytics opt-in, legal. *Accept:* end-to-end update on AppImage; license gate works.

**M8 — Polish & packaging (M).** Themes/fonts parity, tutorials/onboarding, accessibility, AppImage/DEB/Flatpak, docs. *Accept:* clean install on fresh VM; feature matrix checklist green.

Total: **~3–5 months solo** for parity, more with cross-platform packaging.

---

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| QtWebEngine adblock needs C++ interceptor | Tiny `cpp/` shim compiled by cxx-qt-build; keep isolated. |
| cxx-qt model/threading gaps | Validated `QAbstractListModel` + `demo_threading`; fall back to C++ model if a gap appears. |
| 3D/particle performance | Virtualise cards; QtQuick3D for meshes; `ShaderEffect` for particles; cap offscreen updates. |
| Wayland global hotkeys | XDG GlobalShortcuts portal via `ashpd`; document fallback. |
| iCloud unavailable on Linux | Folder-sync abstraction; iCloud works where a mounted path exists (macOS build). |
| Data loss during sync | Never overwrite on unknown state; hash+mtime+backup; extensive tests. |
| Licensing/legal | Reimplement code; do not reuse proprietary assets. Verify font/icon licenses (Lucide ISC, OFL fonts). |
| Qt 6.12 vs cxx-qt | Spike already configures/builds; pin versions. |

---

## 12. Testing & CI

- **Rust:** unit tests for model/storage/history/sync/AI parsers; `insta` snapshots for JSON; mock HTTP (`wiremock`).
- **QML:** QtQuickTest smoke tests for each card type and settings tab.
- **Integration:** headless `QT_QPA_PLATFORM=offscreen` runs for QML; two-process sync convergence test.
- **CI:** build + test on Linux (Qt 6.8 LTS and 6.12); `cargo clippy -D warnings`, `cargo fmt --check`, `qmllint`.
- **Manual matrix:** file provided as `tests/FEATURE_MATRIX.md` derived from the inventory.

---

## 13. Packaging

- **AppImage** (primary), **DEB**, **Flatpak** (org.kde.Platform runtime, QtWebEngine permission notes).
- Bundle fonts + Lucide icons as Qt resources (`qt_add_resources`).
- Update feed: GitHub Releases with `latest-*.yml`-style metadata + platform artifacts.
- Ship `--debug` build flag only in dev builds.

---

## 14. Legal

The original is a proprietary product ("Corcho", Gumroad licensing). This project is a clean-room reimplementation of behaviour for personal/experimental use. Do not copy the original's binaries, icons, fonts, or bundled assets. Use:
- Lucide icons (ISC) — fetch from upstream.
- Fonts under their own licenses (Inter/DM Sans/Manrope/JetBrains Mono/Fira Code/Source Code Pro/IBM Plex/Space Mono are OFL; check OCR-A and OpenDyslexic).
- Own branding and visual design.

---

## 15. Immediate next steps

1. `M0` spike inside this folder: CMake + cxx-qt + QML window + `CardListModel` + JSON persistence.
2. Land the workspace/crate skeleton from §4 with empty modules and CI.
3. Port the v1.20 JSON schema reader and a sample workspace for migration tests.
4. Lock the theme/font/icon asset set and licenses.
5. Start M1 canvas + model.

Reference repos cloned: `KDAB/cxx-qt` (binding API). Qt/Rust toolchains cloned? **No** — installed versions are sufficient; clone only if a specific API needs reading.
