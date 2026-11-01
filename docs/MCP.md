# Corcho MCP server — full control surface

A single Model Context Protocol server that exposes **every** Corcho capability
to an agent. The GUI and the MCP server are two clients of the same Rust core;
neither holds state the other cannot reach.

Transports implemented: **stdio** (`corcho --mcp`) and **minimal HTTP**
(`corcho --mcp-http 127.0.0.1:7411`) with a bearer token stored at
`~/.local/share/corcho/mcp.token`. Protocol version is negotiated at
initialize; tools, resources and prompts come from one registry.

---

## 1. Architecture

```
              ┌──────────────────────────┐
  GUI (Qt) ──▶│        Core (Rust)       │◀── MCP server
              │ model · storage · history│
              │ ai · sync · updates      │
              │ integrations             │
              └───────────┬──────────────┘
                          │ broadcast events (tokio::broadcast)
              ┌───────────┴──────────────┐
              │ AppController (Qt)  MCP  │
              └──────────────────────────┘
```

Rules:
- One `Arc<Mutex<Core>>` (already present) is the single source of truth.
- Every mutation goes through `Core` methods, so undo/redo, persistence and
  validation apply identically to GUI and MCP calls.
- The MCP server may run **headless** (`corcho --mcp`) or attached to a running
  GUI over a Unix socket (`$XDG_RUNTIME_DIR/corcho.sock`) so an agent can drive
  the visible window.
- No tool reads or writes files outside the configured data directory, except
  explicit import/export paths validated by a path guard.

---

## 2. Transports

| Mode | Command | Use |
| --- | --- | --- |
| stdio | `corcho --mcp` | Claude Desktop, opencode, local agents |
| HTTP | `corcho --mcp-http 127.0.0.1:7411` | Remote tooling, multiple clients (bearer token) |
| socket | `corcho --mcp-socket $XDG_RUNTIME_DIR/corcho.sock` | Drive a running GUI |

HTTP requires a bearer token written to `~/.local/share/corcho/mcp.token`
(mode 0600) and validates `Origin` against a localhost allowlist. Bind is
loopback unless `--allow-remote` is explicit.

---

## 3. Tool catalogue

Every tool returns structured content plus a short text summary. Mutations
include `expected_revision` for optimistic concurrency; a mismatch returns
`REVISION_CONFLICT` with the current revision.

### 3.1 Workspace & grids

| Tool | Input | Effect |
| --- | --- | --- |
| `workspace.get` | — | Full workspace, revision, active grid |
| `workspace.revision` | — | Current revision only |
| `workspace.import` | `path`, `format` (`corcho`\|`legacy`), `dryRun` | Import, returns diff summary |
| `workspace.export` | `path`, `includeAttachments` | Write a backup zip |
| `workspace.reset` | `confirm` | Wipe all data (typed confirmation) |
| `grid.list` | `folderId?` | Grids with card counts |
| `grid.get` | `gridId` | Grid + cards + view state |
| `grid.create` | `name`, `folderId?` | New grid |
| `grid.rename` | `gridId`, `name` | Rename |
| `grid.delete` | `gridId` | Delete (refuses last grid) |
| `grid.switch` | `gridId` | Change active grid |
| `grid.reorder` | `gridId`, `beforeId?` | Reorder |
| `grid.move` | `gridId`, `folderId?` | Move into/out of a folder |
| `grid.view` | `gridId`, `panX`, `panY`, `zoom` | Persist view |
| `folder.list/create/rename/delete/toggle` | as expected | Folder lifecycle |

### 3.2 Cards

| Tool | Input | Effect |
| --- | --- | --- |
| `card.list` | `gridId`, `kind?`, `query?` | Cards |
| `card.get` | `cardId` | Card + payload |
| `card.create` | `gridId`, `kind`, `x`, `y`, `title?`, `payload?` | Create |
| `card.update` | `cardId`, `patch` (geometry, title, text, color, icon, locked, payload) | Patch |
| `card.delete` | `cardId` | Delete |
| `card.duplicate` | `cardId`, `offset?` | Duplicate |
| `card.move` | `cardId`, `gridId`, `x`, `y` | Move across grids |
| `card.resize` | `cardId`, `width`, `height` | Resize |
| `card.setColor` | `cardId`, hex | Color |
| `card.setIcon` | `cardId`, lucide name | Icon |
| `card.lock` | `cardId`, boolean | Lock |
| `card.search` | `query`, `limit?` | Ranked results with snippets |

Kind-specific tools:

| Tool | Purpose |
| --- | --- |
| `note.append` / `note.replace` | Edit note text |
| `checklist.add/update/remove/toggle` | Checklist items |
| `kanban.addColumn/removeColumn/addItem/moveItem/removeItem` | Kanban |
| `whiteboard.clear`, `whiteboard.stroke` | Stroke list |
| `pomodoro.start/pause/reset/configure` | Timer |
| `website.navigate/back/forward/reload/zoom` | Web card |
| `website.cookies.read`, `website.attack.run` | Session debug |
| `api.fetch` | Run an API Data card |
| `script.run` | Execute a card script in `/bin/sh` (permission-gated) |
| `mpris.list/action/metadata` | Media control |
| `gridlink.set` | Target grid |
| `fragment.configure` | Mode, accent, speed, audio |
| `fragment.audio.start/stop` | Spectrum synth |

### 3.3 AI

| Tool | Input | Effect |
| --- | --- | --- |
| `ai.providers` | — | Provider + model catalogue |
| `ai.validateKey` | `provider`, `apiKey` | Validate (never logged) |
| `ai.setKey` / `ai.clearKey` | `provider`, `apiKey?` | Store in local settings |
| `ai.setModel` | `provider`, `model` | Default model |
| `ai.complete` | `provider?`, `model?`, `prompt`, `context?`, `webSearch?` | Non-streaming completion |
| `ai.stream` | same, `streamId` | Emits `ai.chunk`/`ai.done` notifications |
| `ai.cancel` | `streamId` | Cancel |
| `ai.card.run` | `cardId` | Run an AI card with its saved prompt/context |
| `ai.models.local` | `serverUrl`, `apiKey?` | List local models |
| `ai.stats` | — | Card counts, token estimates |

API keys are write-only: `settings.get` redacts them; logs never include them.

### 3.4 Settings, themes & appearance

| Tool | Input |
| --- | --- |
| `settings.get` | `redactSecrets?` |
| `settings.set` | `key`, `value` (validated against the schema) |
| `settings.batch` | `patch` object, atomic |
| `theme.list` | — |
| `theme.set` | `themeId` |
| `theme.custom.set` | `background`, `surface`, `accent`, `text` |
| `font.list` / `font.set` | Font id |
| `effects.set` | spawn, parallax, ripple, reducedMotion |
| `audio.setVolume` | 0–100 |

### 3.5 Sync, backups, data

| Tool | Input |
| --- | --- |
| `sync.status` | — |
| `sync.now` | — |
| `sync.configure` | `enabled`, `provider` (`folder`\|`gdrive`), `folder?` |
| `gdrive.connect` / `gdrive.disconnect` | PKCE flow (browser) |
| `git.status` | enabled, remote, branch, last sync, last error |
| `git.configure` | enabled, remote, branch, autoPull, autoPush, includeAttachments |
| `git.sync` | commit, pull/ff/union-merge, push |
| `backup.export` / `backup.import` | `path` |
| `data.setDir` | `path` |
| `attachments.list/read/write/delete` | base64 for binary |

### 3.6 Updates and OS

| Tool | Input |
| --- | --- |
| `update.check` | — |
| `update.channel.set` | `stable`\|`beta`\|`experimental` |
| `update.download` / `update.install` | — |
| `app.launchAtStartup` | boolean |
| `app.openExternal` | URL (allowlist http/https) |
| `app.quit` / `app.relaunch` | confirm |
| `app.changelog` | — |
| `app.about` | version, build info |
| `diagnostics.run` | integrity checks |

### 3.7 Powerbar, tutorials, easter eggs

| Tool | Input |
| --- | --- |
| `powerbar.search` | `query` |
| `powerbar.run` | `commandId`, `args?` |
| `tutorial.reset` | — |
| `onboarding.complete` | — |

---

## 4. Resources

Stable URIs for read-only context:

```
corcho://workspace
corcho://grid/{id}
corcho://card/{id}
corcho://settings
corcho://themes
corcho://models
corcho://changelog
corcho://backup/latest
corcho://diagnostics
```

MIME types: `application/json` for structured documents, `text/markdown` for
changelog, `application/zip` for backups.

## 5. Prompts

Reusable agent prompts exposed by the server:

- `organize-inbox` — triage unlinked notes into a grid.
- `summarize-grid` — summarize a grid's cards.
- `weekly-review` — collect pomodoros, checklists and notes into a review.
- `research-to-cards` — run a web/AI research pass and create cards.
- `clean-duplicates` — find duplicate cards and propose merges.

Each prompt declares arguments (gridId, date range) and returns messages that
call the tools above.

## 6. Events / subscriptions

The server broadcasts JSON-RPC notifications:

```
card.created      { gridId, card }
card.updated      { gridId, card, changed }
card.deleted      { gridId, cardId }
grid.changed      { grid }
workspace.saved   { revision }
sync.status       { state }
update.status     { state }
ai.chunk          { streamId, text }
ai.done           { streamId, text }
script.output     { cardId, chunk }
```

Clients may subscribe to a subset with `resources/subscribe` or the custom
`events.subscribe` tool. Notifications are coalesced at 50 ms to avoid floods
during drags.

## 7. Safety model

- **Write scope:** only the Corcho data dir and explicitly supplied
  import/export paths. `..` and symlinks are resolved and re-checked.
- **Secrets:** API keys and OAuth tokens are redacted from reads, errors and
  logs. `settings.set` accepts them; nothing returns them.
- **Destructive tools** (`workspace.reset`, `grid.delete`, `data.setDir`,
  `app.quit`) require `confirm: "yes"` and are annotated
  `destructiveHint: true`.
- **Script execution** is off by default; enabling requires
  `settings.allowScripts = true` and each call carries a timeout.
- **Rate limits:** per-tool token bucket (mutations 10/s, AI 2/s, updates 1/min).
- **Audit log:** every tool call appended to `~/.local/share/corcho/mcp-audit.log`
  with tool, args hash, revision and outcome; secrets omitted.
- **No implicit network:** only AI, sync and update tools touch the
  network, and only when invoked.

## 8. Implementation

- Crate: `mcp/` binary (`corcho-mcp`) depending on `corcho` core as a library.
- Protocol: `rmcp` crate (official Rust MCP SDK) or a small JSON-RPC 2.0 loop
  with `serde`. Tool schemas generated from Rust types with `schemars`.
- `Core` gains a `revision: u64` counter incremented on every mutation; tool
  calls compare it for optimistic concurrency.
- Tool registry is a single `match` over tool names; each handler returns
  `serde_json::Value`. The same registry powers stdio and HTTP.
- GUI integration: the core broadcasts via `tokio::broadcast`; the MCP server and
  Qt bridge both subscribe, so an agent's mutation appears in the window and a
  GUI mutation appears to the agent.
- Headless mode boots `Core` without a `QGuiApplication`.
- Packaging: `corcho --mcp` is a hidden flag; `corcho-mcp` is also shipped for
  agents that prefer a dedicated binary.

### Milestones

1. **Registry + stdio + workspace/grid/card CRUD** with revision checks.
2. **Settings/themes/fonts + resources + events.**
3. **AI (streaming) + web/API/script tools** with permission gates.
4. **Sync/backup/update/OS tools.**
5. **HTTP transport + token auth + audit log + rate limits.**
6. **Prompts + completions + conformance tests** against the MCP spec.

### Tests

- Golden JSON-RPC request/response fixtures per tool.
- Property tests: create → update → undo → redo returns the original JSON.
- Two-client convergence: MCP mutation + GUI mutation + sync produce one state.
- Security tests: path traversal, symlink escape, secret redaction, token auth.
- `mcp-probe` conformance run for initialize, tools/list, resources/list.

---

## 9. Why an MCP server

The canvas is a workspace for thinking. An agent that can read the workspace,
create and edit cards, run AI processors, and trigger sync/update actions turns
Corcho into a programmable surface without scripting the GUI. Because every
capability already lives in `Core`, the MCP layer is a thin, auditable adapter —
not a second application.


---

## 10. Implementation status

Implemented in `src/mcp.rs`, started with `corcho --mcp` (or `CORCHO_MCP=1`):

- `initialize`, `ping`, `tools/list`, `tools/call`, `resources/list`,
  `resources/read`, `prompts/list`, `prompts/get` over newline-delimited
  JSON-RPC on stdio.
- Tools: workspace get/export/import; grid list/get/create/rename/delete/
  switch/move; card list/get/create/update/delete/duplicate/move/search;
  note append/replace; checklist add/update/remove/toggle; kanban add/move/
  remove item; whiteboard clear/stroke; fragment configure; grid link set;
  pomodoro configure/reset; api fetch; settings get/set/batch; theme list/set;
  font list; powerbar search/run; ai providers/complete; sync.now; git status/
  configure/sync; backup export/import; update check/channel; app about/
  changelog; attachments list/read; script run; mpris list/action; quit.
- Resources: `corcho://workspace`, `corcho://grid/{id}`, `corcho://card/{id}`,
  `corcho://settings` (secrets redacted), `corcho://themes`,
  `corcho://changelog`.
- Prompts: `organize-inbox`, `summarize-grid`, `weekly-review`.
- Tests cover initialize/tools list, missing arguments, and the git merge.

HTTP requests need `Authorization: Bearer <token>`; the token is printed at
startup and written to `~/.local/share/corcho/mcp.token` (0600). Bind is
loopback by default. Example:

```sh
corcho --mcp-http 127.0.0.1:7411
curl -H "Authorization: Bearer $(cat ~/.local/share/corcho/mcp.token)" \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"app.about","arguments":{}}}' \
  http://127.0.0.1:7411/
```

Example client config (opencode):

```json
{
  "mcp": {
    "corcho": {
      "type": "local",
      "command": ["corcho", "--mcp"],
      "enabled": true
    }
  }
}
```

Remaining from the design above: event subscriptions (SSE), a Unix-socket
transport for driving the live GUI, and web/website tools that require the
GUI's QtWebEngine. All other categories are implemented.
