# Corcho

A native canvas for personal development. Notes, websites, tasks, timers and
sensory fragments on an infinite grid.

Built with **Rust** and **Qt 6** (Qt Quick + QtWebEngine). Linux only.
No Electron shell, no telemetry, no analytics.

![Corcho canvas](docs/screenshots/canvas.png)

![Corcho settings](docs/screenshots/settings.png)

## Features

- Infinite grid canvas with pan, zoom, snapping, minimap and undo/redo.
- Thirteen card types: note, website, bookmark, API data, AI processor, script,
  fragment, grid link, checklist, kanban, whiteboard, pomodoro, now playing.
- Eight fragment modes: Haptic, Nebula, Spectrum, Artifact, Boson, Vector,
  Calendar, Hypercube.
- Five AI providers (Anthropic, OpenAI, Google, xAI, Mistral) plus a local
  OpenAI-compatible server, with streaming and context injection.
- Isolated website sessions, a host-based ad blocker and a session self-test.
- Folder sync, Google Drive sync and **git sync** to any remote (GitHub,
  Codeberg, GitLab, self-hosted): pull at start, debounced auto-push, and a
  union merge that never drops a grid or card. Conflict copies are kept in
  `backups/`.
- Stable, beta and experimental update channels, MPRIS, scripts, launch at
  startup and a `corcho://` protocol handler. Every feature is free.
- A working **MCP server** over stdio (`corcho --mcp`) with workspace, grid,
  card, settings, AI, git, sync, backup and update tools;
  see [`docs/MCP.md`](docs/MCP.md).

## Palette

Two base neutrals and one distinct accent, following the 60-30-10 rule:

| Role | Color | Share |
| --- | --- | --- |
| Base 1 — ink (canvas, chrome) | `#121417` | 60% |
| Base 2 — paper (text, light surfaces) | `#ECE7DE` | 30% |
| Accent — ember (actions, selection) | `#D98E5C` | 10% |

Surfaces are derived from the ink base (`#1B1E23`, `#272B31`), borders are the
paper tone at 9% alpha, and semantic colors are muted (success `#7FAE83`, danger
`#D97A72`). The accent is reserved for the primary action, the current
selection and one highlighted figure.

References consulted: the 60-30-10 color rule and “two neutrals + one accent”
guidance from [Color Scheme Calculator](https://colorschemecalculator.com/create-color-palette/)
and [Sky Rye Design](https://skyryedesign.com/inspiration/color-palette-inspiration/).

## Accessibility

See [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md) for contrast targets,
focus behaviour and reduced motion.

## Build

Requires Rust 1.85+, Qt 6.8+ development packages (Core, Gui, Qml, Quick,
QuickControls2, Svg, WebEngine, Network) and ALSA headers.

```sh
QMAKE=/usr/bin/qmake6 cargo build
QMAKE=/usr/bin/qmake6 cargo run
```

The build is Cargo-only; CMake is not required.

## Data

`~/.local/share/corcho/workspace.json` holds the workspace, with `attachments/`,
`backups/` and `updates/` beside it.

## License

MIT. See [LICENSE](LICENSE). Bundled Inter fonts are under the SIL Open Font
License; Lucide icons are ISC.
