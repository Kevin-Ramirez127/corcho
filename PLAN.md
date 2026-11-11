# Corcho-RS: Rust + Qt6 Native Rewrite

## 1. Objective

Rebuild the Corcho / Corcho v1.20.0 feature set as a **native Linux desktop app** in **Rust** with **Qt 6**, replacing the Electron/Chromium shell.

- **Shell/UI:** Qt Quick (QML): GPU-rendered, native window, no Electron, no bundled web shell.
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

Bridge library: **cxx-qt 0.10** (KDAB) supports all Qt 6, MSRV 1.85, `QAbstractListModel`, QObject signal/slot, Qt threading. Clone used for reference: `KDAB/cxx-qt`.

**Do not clone Qt or the Rust toolchain**: Qt source is ~several GB and unnecessary; use the installed Qt dev packages + docs. Clone only small binding repos when an API is unclear (cxx-qt done).

### Feasibility spike result
`examples/qml_minimal` from cxx-qt **configures and builds** against the installed Qt 6.12 (see build log verification). This de-risks the core stack.

---

## 3. Architecture

```
┌───────────────────────────────────────────────┐
│ Qt Quick (QML)                                │
│  Shell · Canvas · Cards · Dialogs · Launcher  │
│  QtWebEngine (website cards)                  │
│  Calendar and Timbre cards                    │
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
│  └─ integrations/              # mpris, script runner, adblock, updates, hotkeys
├─ cpp/                          # minimal C++ shims (WebEngine interceptor, portal)
├─ qml/
│  ├─ Main.qml
│  ├─ shell/                     # Sidebar, Topbar, StatusBar, MobileShell
│  ├─ canvas/                    # CanvasView, CardLayer, Minimap, Selection
│  ├─ cards/                     # Note, Website, Bookmark, ApiData, Ai, Script,
│  │                             # Calendar, Timbre, GridPortal, Checklist,
│  │                             # Kanban, Whiteboard, Pomodoro, Mpris
│  ├─ dialogs/                   # Settings*, Launcher, ContextMenu, Tutorials,
│  │                             # Onboarding, Update, Changelog
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
                Calendar, Timbre, GridPortal, Checklist, Kanban, Whiteboard, Pomodoro, Mpris }
```

- **Store:** one JSON file per grid (`grids/<id>.json`) + `workspace.json` + `settings.json`, atomic write (temp + rename), `.bak` rotation. Same shape as the original for easy migration.
- **History:** append-only command log with inverse ops; cap `undoSteps` (default 20). Snapshot fallback for large structural changes.
- **Search:** in-memory index rebuilt from cards (title/text/tags). Upgrade to `tantivy` only if needed.
- **Backups:** `.corcho` ZIP via `zip`; optional AES-GCM + Argon2 passphrase.
- **Migration:** importer for the original `Nova`/`.nova` data folder and `.corcho` backups.

---

## 6. Rust ↔ Qt bridge

- `AppController` (QObject): `#[qinvokable]` methods: `create_card`, `delete_card`, `move_card`, `resize_card`, `duplicate_card`, `switch_grid`, `create_folder`, `rename_*`, `set_theme`, `run_launcher`, `open_settings`, `connect_ai`, etc.
- `GridListModel` / `CardListModel`: `QAbstractListModel` (cxx-qt todo_app pattern). Card role returns a `QVariantMap` for heterogeneous payloads; QML delegates by `kind`.
- `SettingsObject`: Q_PROPERTY-backed settings with `changed` signals.
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
| Calendar | Month view, reminders and date links across cards. |
| Timbre | Noise and pure-tone audio with volume, pitch and mix. |
| Grid Portal | Rust model navigation + canvas switch. |
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

### 7.4 Calendar and Timbre
- **Calendar**: QML month grid with previous/next month and Today navigation,
  a selected-day agenda, and per-calendar filters.
- **Date links**: reminders and dates from any card or kanban/checklist item
  are stored as date links that reference one or more calendars.
- **Timbre**: noise and pure-tone synth via `cpal` in Rust (low latency), with
  volume, pitch and mix controls. Playback is manual and owned by one card.

### 7.5 Web / adblock (`crates/integrations` + `cpp/`)
- Per-website persistent `WebEngineProfile` (isolated storage/cookies).
- `adblock-rust` (Brave) filter engine + tiny `QWebEngineUrlRequestInterceptor` C++ shim.
- Cookie/debug panel incl. the **Session Probe** self-test (reimplement in a sandboxed test profile).
- Permission handler, window-open handler, clear-partition-data.

### 7.6 Sync, backup, data (`crates/sync`, `crates/storage`)
- **Folder sync** provider: any local/cloud-mounted directory (works for iCloud Drive on macOS, Nextcloud/Dropbox mounts on Linux) via `notify` watcher + debounce. This replaces the macOS-only iCloud helper on Linux.
- **Google Drive**: `oauth2` (PKCE, local redirect) + `reqwest` Drive v3 `appDataFolder`; refresh tokens; conflict backup files; delete/clear data.
- **Peer sync**: Iroh Documents with one document per workspace, per-record Lamport clocks, tombstones, conflict copies in `backups/`, content-addressed attachments, an optional read-only `--sync-daemon`, and daily snapshot zips.
- Conflict resolution: mtime + content hash + `.backup_<ts>` like upstream; never overwrite on unknown cloud state.
- Import/export `.corcho` ZIP; selective wipe; data-folder selection.

### 7.7 Updates and OS integration
- Updater: GitHub Releases (`reqwest` + `semver`), channels **stable/beta/experimental**, mandatory-update gate, AppImage/DEB installer strategy per package type.
- Launch-at-startup (XDG autostart / portal), single instance (D-Bus name), `corcho://` protocol handler, native file dialogs, About panel, changelog.
- Global Launcher hotkey via XDG `GlobalShortcuts` portal (`ashpd`) with X11 fallback.
- MPRIS card, media art cache, clipboard, open-in-browser.

### 7.8 UI shell
- Sidebar (grids, folders, sync indicator, settings, launcher), topbar, status bar, responsive/mobile layout.
- Launcher (command palette): grids/cards search, create commands, zoom, undo/redo, themes, easter eggs.
- Settings: General / Interface / Appearance / Data / AI / Security / About, porting all options from §11 of the inventory.
- Themes: 19 standard + custom editor; 14 fonts; opacity, audio, visual-effect toggles.
- Tutorials/onboarding, splash, easter eggs, changelog, legal links, local diagnostics (no telemetry).

---

## 8. Feature coverage matrix

Everything in the inventory maps as follows. Nothing is dropped; OS-specific items are substituted.

| Area | Coverage |
|---|---|
| Canvas/grid (pan, zoom, snap, magnet, ripple, parallax, minimap, folders, grid portals, lock, undo/redo) | Full (QML + Rust) |
| 14 card types | Full |
| Calendar + date links + Timbre | Full (QML + cpal) |
| 19 themes + custom, 14 fonts, opacity/volume/effects | Full |
| AI: 5 providers + local, model lists, streaming, web search, refresh, context injection, stats | Full |
| Website cards: webview/bookmark/API, isolated sessions, nav/zoom, scroll memory, adblock, cookie debug, session probe | Full |
| Cloud sync: folder provider (iCloud substitute) + Google Drive + Git remote, conflicts, indicator, troubleshoot | Full |
| Backups import/export, data folder, migration, wipe/reset | Full |
| Updates: channels, auto modes, mandatory flow, changelog | Full |
| Licensing | Removed; Corcho is fully free software |
| Launcher + tutorials + onboarding + easter eggs + legal + diagnostics + analytics (opt-in) | Full |
| MPRIS/now-playing | Full (`mpris`/zbus + playerctl fallback); Linux |
| Script card `/bin/sh` | Full, disabled-by-default menu entry like upstream |
| Debug tools (test data, simulated failures, mandatory-update test, memory/logs) | Full behind `--debug`/dev build |

**Deliberate substitutions:**
- macOS-only iCloud helper and `Corcho.app` handoff → generic folder sync + documented macOS path (build target).
- Electron auto-updater → GitHub-release updater per packaging format.
- Amplitude SDK → opt-in telemetry (own sender or Sentry), default off.

---

## 9. Key dependencies (crates)

`cxx-qt`, `cxx-qt-lib`, `cxx-qt-build`, `serde`, `serde_json`, `tokio`, `reqwest` (rustls), `eventsource-stream`, `futures`, `notify`, `zip`, `aes-gcm`, `argon2`, `mpris`/`zbus`, `adblock-rust`, `oauth2`, `semver`, `uuid`, `time`/`chrono`, `anyhow`, `thiserror`, `tracing`, `tracing-subscriber`, `comrak`, `html5ever`/`scraper`, `cpal`, `ashpd` (portal), `rand`, `base64`, `image`, `open`/`QDesktopServices`, `directories`.

Keep the dependency surface small; prefer Qt for rendering/OS and Rust for logic.

---

## 10. Milestones

Sizing assumes one developer; rough, not a commitment.

**M0: Spike (S).** cxx-qt window + QML shell + one `CardListModel` + create/move/delete card + JSON persistence. *Accept:* card survives restart; `cargo test` + QML smoke test pass.

**M1: Canvas & core model (M).** Grids, folders, pan/zoom, snap, minimap, undo/redo, sidebar, contexts. *Accept:* 200-card grid at 60 fps; undo/redo 20 steps.

**M2: Productivity cards (M).** Note, Checklist, Kanban, Whiteboard, Pomodoro, Grid Portal, Script (flagged). *Accept:* all persist and edit correctly.

**M3: Web cards & adblock (M).** Website/Bookmark/API Data, profiles, nav, adblock, cookie debug. *Accept:* site isolation + adblock verified against a test site.

**M4: AI (M).** Providers, streaming, AI cards, context injection, refresh, stats. *Accept:* streaming from each provider (mock in CI) + local server.

**M5: Calendar and Timbre (M).** Month view, reminders, date links, calendar filters, and the audio synth. *Accept:* date links survive restart; audio starts and stops cleanly.

**M6: Sync/data (M).** Folder sync + Google Drive, conflicts, backups, import/export, migration. *Accept:* two-instance convergence test + conflict backup.

**M7: Platform (M).** Updates, launch-at-startup, protocol, hotkey, single instance, MPRIS, legal. *Accept:* end-to-end update on AppImage.

**M8: Polish & packaging (M).** Themes/fonts parity, tutorials/onboarding, accessibility, AppImage/DEB/Flatpak, docs. *Accept:* clean install on fresh VM; feature matrix checklist green.

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
| Legal | Clean-room reimplementation; do not reuse the original product's assets. Verify font/icon licenses (Lucide ISC, OFL fonts). |
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

Corcho is free software under the MIT license. It is a clean-room reimplementation of behaviour. Do not copy the original product's binaries, icons, fonts, or bundled assets. Use:
- Lucide icons (ISC); fetch from upstream.
- Fonts under their own licenses (Inter/DM Sans/Manrope/JetBrains Mono/Fira Code/Source Code Pro/IBM Plex/Space Mono are OFL; check OCR-A and OpenDyslexic).
- Own branding and visual design.

---

## 15. Immediate next steps

1. `M0` spike inside this folder: CMake + cxx-qt + QML window + `CardListModel` + JSON persistence.
2. Land the workspace/crate skeleton from §4 with empty modules and CI.
3. Port the v1.20 JSON schema reader and a sample workspace for migration tests.
4. Lock the theme/font/icon asset set and licenses.
5. Start M1 canvas + model.

Reference repos cloned: `KDAB/cxx-qt` (binding API). Qt/Rust toolchains cloned? **No**: installed versions are sufficient; clone only if a specific API needs reading.

---

## 15. Optimization pass

Goal: keep interaction at 60 fps with hundreds of cards, and keep idle work at
zero.

- **Card model:** replace the Repeater-over-JS-array with a `ListModel` that is
  diffed by card id. Geometry and text updates patch the row in place instead of
  destroying and recreating every delegate. (Done.)
- **Light refresh:** card updates refresh only `cardsJson`; grids/folders/
  settings are refreshed only when their shape changes.
- **Culling:** cards outside the viewport plus a margin are unloaded by the
  `Loader`, so off-screen webviews and timbre visualizers cost nothing.
- **Canvas:** dot grid redraws are coalesced per frame; minimap redraws only on
  pan/zoom; ripple and spawn animations are single-shot.
- **Timbre:** visualizer timer runs only while audio is playing and stops
  when the card is off-screen or **Reduced motion** is on.
- **Persistence:** view changes stay in memory and save on release; JSON writes
  are atomic; a future pass adds a 400 ms debounce for text edits.
- **Network:** AI streams are emitted per chunk without re-serialising the
  workspace; sync/update tasks run on the tokio pool, never on the GUI thread.
- **Startup:** QML is compiled ahead of time by `qmlcachegen`; fonts/icons are
  qrc resources; no network at launch.

Acceptance: 200 cards at 60 fps on the reference machine; pan with a webview
card visible stays above 50 fps; idle CPU < 1% with no timbre playing.

## 16. Theme and accessibility color grading pass

Research basis: WCAG 2.1 SC 1.4.3 (4.5:1 body text, 3:1 large text and UI
graphics) and APCA (Lc 75 minimum for body text, Lc 60 for content, Lc 45 for
large text, Lc 30 for placeholders/disabled). Also the 60-30-10 rule: 60%
ink, 30% neutral surfaces, 10% ember accent.

Procedure:
1. Build every surface from one tinted neutral ramp (ink → surface → hover).
2. Keep three text roles. Target WCAG AA for `text` and `text2` on every
   surface; `muted` must still clear 4.5:1 at 13 px.
3. Accent is checked both as ink on ink (≥ 4.5:1) and as a surface with
   `accentInk` text (≥ 4.5:1).
4. Non-text UI (borders, focus rings, icons) targets ≥ 3:1 against adjacent
   colors.
5. Audit all 19 themes, not only the default. Light themes get darker `muted`
   and `text2` values; dark themes get lighter ones.
6. Add a visible focus ring, keyboard activation, and screen-reader roles/names
   to every control.
7. Honour the OS/reduced-motion setting: no spawn, ripple, parallax or timbre
   animation when enabled.

Acceptance: a contrast script over the theme table reports no body-text pair
below 4.5:1 and no focus ring below 3:1; Tab reaches every control; every
interactive element exposes `Accessible.name` and a role.

## 17. Unslop pass (skill: `unslop`)

Run the skill's nine passes over every screen: spacing, color, icons, copy,
type, layout, details, visuals, motion.

- 4 px rhythm; identical rows share height and gap; sidebar is the densest area.
- Quiet chrome, one accent; no hue gradients, glows, gradient text or blobs.
- One Lucide set at 16/18 px and 1.5 stroke; no emoji; no gems, crowns, keys or
  other premium iconography.
- Sentence case, no exclamation marks, no trailer periods, no greeting
  headlines, no unverified claims.
- 400/500 weights, 600 rare; no negative tracking on small text; tabular figures.
- Nested radii: controls 8, cards 14, panels 16.
- The canvas is the one rich moment; chrome stays quiet.
- One easing curve; short feedback transitions; no looping decoration.
- Re-run the checklist and compare against the before screenshots.

Acceptance: the checklist at the end of the skill is fully checked, and the
screens look like Corcho specifically, not a generic dark app.

---

## 18. Status

Delivered in this repository:

- [x] Cargo-only `cxx-qt` build, Qt 6 QML shell, AppController bridge.
- [x] Model, atomic JSON storage, snapshot undo/redo, search, tests.
- [x] Infinite canvas: pan, zoom, snap, minimap, folders, grid portals, lock,
      spawn/ripple, reduced motion, culling.
- [x] Fourteen card types, including website, API, AI, script, calendar,
      timbre, kanban, whiteboard, pomodoro and MPRIS.
- [x] Multi-calendar date links, reminders, month navigation and per-calendar
      filters.
- [x] Timbre audio card with manual start/stop and visualizer.
- [x] Five AI providers plus local server, streaming, context, key validation.
- [x] Isolated website sessions, host ad blocker, cookie panel, session probe.
- [x] Folder sync, Google Drive sync, Iroh peer sync, conflict copies,
      zip backup/restore, legacy import.
- [x] Updates (stable/beta/experimental), MPRIS, scripts, launch at startup,
      single instance, `corcho://` deep links.
- [x] Launcher, six settings tabs, 19 themes, custom theme editor, fonts,
      onboarding, tutorials, changelog.
- [x] Fully FOSS: no licensing, premium locks, premium icons or telemetry.
- [x] Optimization pass: ListModel diffing, light card refresh, culling,
      View state kept in memory, timbre visualizer stopped off-screen.
- [x] Accessibility pass: WCAG/APCA targets, contrast test in `model.rs`,
      focus rings, keyboard activation, `Accessible` names/roles.
- [x] Unslop pass: 4 px rhythm, quiet chrome, one ember accent, one icon set,
      no emoji, no gem/crown/key iconography, calm motion.
- [x] MCP server: stdio and HTTP (bearer token), 60+ tools, resources, prompts.
- [x] CI (fmt, clippy `-D warnings`, tests, release build), packaging recipes,
      screenshots.

Known limits, deliberately documented rather than hidden:

- Card parallax is a subtle pointer-driven tilt, not a depth-parallax plane.
- Website ad blocking covers top-level navigation, `fetch`/XHR calls to known
  hosts, and a DOM cleanup pass; it is not a full network interceptor.
- MCP SSE event subscriptions, the Unix-socket GUI transport and web-card tools
  that need QtWebEngine are not implemented; everything else is available over
  stdio and HTTP.
- AppImage/Flatpak manifests are recipes; they need `linuxdeploy`/`flatpak-builder`
  on the build machine.

---

## 19. Stability and UI polish (post-plan pass)

- [x] Resize grip moved inside the card border, with a hover hint:
      “Ctrl + right-click to resize”.
- [x] Ctrl + right-click drag on any card resizes it (Hyprland-style),
      in addition to the corner grip.
- [x] Settings → Appearance → **Card roundness** slider (0–28 px) applied to
      every card and persisted as `card_radius`.
- [x] Folder entries open a new folder card; image/Markdown entries open a
      dedicated file card; PDFs and other files open in the system default viewer.
- [x] Compact “open in default application” button on every file card.
- [x] Opening files no longer blocks the GUI thread (`open::that_detached`).
- [x] File logs, Qt message capture, panic backtraces and crash dumps under
      `~/.local/share/corcho/logs/`; `--crash-test` verifies the pipeline.
- [x] QML guards for cards created before `card`/`th`/`app` are attached, and a
      watchdog that exits if the QML window never initializes.

---

## 20. RAM footprint pass

Measured with `smaps_rollup`, debug build, 1900x1034 window:

| State | RSS | PSS |
| --- | --- | --- |
| Notes only | 253 MB | 150 MB |
| One website card | 729 MB | 411 MB |
| Headless MCP server | 48 MB | 5.7 MB |

After the pass, release build: notes-only **139 MB PSS** (253 MB RSS), one
website **409 MB PSS** (727 MB RSS), three websites **473 MB PSS** (997 MB RSS).
A sleeping website released its ~80 MB renderer; the two zygotes and the
in-process QtWebEngine state remain.

A single website costs ~270 MB PSS: one renderer plus two zygotes on top of
QtWebEngine's in-process network/GPU state; each additional visible site adds
roughly 30 MB. The changes below target that,
without removing features:

- [x] One shared `WebEngineProfile` for all website cards (settings toggle for
      per-card isolation), created lazily by `WebProfileHost.qml` only when a
      website card exists.
- [x] `WebEngineView` is created through a `Loader` only when a URL exists and
      the card is awake, so blank cards cost nothing.
- [x] Website cards sleep after 10 minutes by default (configurable 0–60 in
      Settings > General). A coffee button on each card keeps it awake and
      persists `noSleep` with the card.
- [x] PDFs no longer start QtWebEngine; PDF entries and cards open in the
      system viewer.
- [x] Website cards use a 48 px culling margin instead of 320 px.
- [x] `MALLOC_ARENA_MAX=2`, a throttled `malloc_trim(0)` after saves, and a
      256 KiB cap on persisted API/AI bodies.
- [x] Optional low-memory mode (Settings > General): restart-scoped Chromium
      flags `--renderer-process-limit=2 --process-per-site`,
      `--js-flags=--max-old-space-size=256` and `--aggressive-cache-discard`.

---

## 21. UI audit fixes

Manual pass over every shell surface and all 15 card kinds found and fixed:

- Toggle switch thumb sat high in its track; now vertically centered.
- Ctrl-click selected nothing additively on the card header because the title
  input swallowed the event. Header now uses a MouseArea with a real
  `mouse.modifiers` check; title editing moved to double-click.
- Double-clicking a card header could fall through and create a background note;
  the background create gesture now ignores points inside an existing card.
- Group outlines and the marquee were invisible because they built colors from
  `accent.r/g/b` on a color string; switched to `Qt.alpha(accent, …)`.
- Group create/ungroup now refresh the card model, so grouped moves move every
  member and the outline appears immediately.
- Website header was fixed-width and broke below 512 px; it now uses a
  RowLayout and hides zoom/coffee controls at narrow widths.
- Removed startup TypeErrors from SelectField and the Kanban column delegates
  evaluating theme tokens before `th` is attached.

---

## 22. AI context links and providers

- AI cards can link other cards from their own "linked" picker. Links are stored
  as `linkedIds` on the AI card; toggling uses `Core::toggle_ai_link`.
- On Run, `Core::ai_context` serializes each linked card into readable context:
  note text, calendar dates, kanban columns/items, checklist state, API body,
  script, timbre, pomodoro, portal target, file path and media player.
- Linked cards are drawn as curved node lines under the cards. Lines are static
  normally and switch to an animated dashed flow for 4.5 s when the AI card is
  activated.
- AI remains provider-agnostic: the card reads the provider/model from Settings.
  Added OpenRouter (`https://openrouter.ai/api/v1`) and OpenCode Go
  (`https://opencode.ai/inference/openai/v1`) with settings entries and model
  presets.

---

## 23. Git cards, AI presets and card sync

- **Git card:** new `git` kind tracks a repository URL. GitHub (api.github.com),
  GitLab (`/api/v4`) and Forgejo/Gitea (`/api/v1`) are detected from the host;
  `owner/repo` shorthand defaults to GitHub. Shows open issues, open pull
  requests, latest commit, and CI state. Tokens are separate reusable Settings
  fields per provider (`repo_token_github|gitlab|forgejo`), never stored on the
  card.
- **AI presets:** Settings → AI now has reusable presets of name + provider +
  model. Credentials stay in the per-provider key store; a preset only
  references the provider. AI cards choose a preset (or "Settings default")
  and Run uses that provider/model.
- **Card sync:** card context menu has “Sync with card” (same-kind cards, any
  grid) and “Stop syncing”. Synced cards share content/title/payload; geometry,
  colour, group and pinning stay per-card. Editing either side mirrors changes.
- **Minimum sizes:** card resize now enforces per-kind minimums (Calendar
  420×500, Git/Kanban 360×260, AI 300 px tall, etc.).
- **Calendar readability:** larger weekday/day type, roomier chips, agenda rows
  and dots; new calendars default to 520×560.
