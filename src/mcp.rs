use std::io::{BufRead, Write};

use anyhow::{anyhow, Result};
use serde_json::{json, Value};

use crate::ai::{self, AIRequest};
use crate::core::{merge_settings_value, Core};
use crate::integrations;
use crate::model::{self, Settings};
use crate::updates;

const VERSION: &str = env!("CARGO_PKG_VERSION");

pub fn serve() -> Result<()> {
    let mut core = Core::boot()?;
    let stdin = std::io::stdin();
    let mut stdout = std::io::stdout();
    for line in stdin.lock().lines() {
        let line = line?;
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let Ok(request) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        if let Some(response) = handle(&mut core, request) {
            serde_json::to_writer(&mut stdout, &response)?;
            stdout.write_all(b"\n")?;
            stdout.flush()?;
        }
    }
    Ok(())
}

pub fn handle(core: &mut Core, request: Value) -> Option<Value> {
    let id = request.get("id").cloned();
    let method = request.get("method").and_then(|m| m.as_str()).unwrap_or("");
    match method {
        "initialize" => Some(ok(
            id,
            json!({
                "protocolVersion": request.get("params")
                    .and_then(|p| p.get("protocolVersion"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("2024-11-05"),
                "capabilities": {
                    "tools": {},
                    "resources": {},
                    "prompts": {}
                },
                "serverInfo": { "name": "corcho", "version": VERSION }
            }),
        )),
        "ping" => Some(ok(id, json!({}))),
        "tools/list" => Some(ok(id, json!({ "tools": tools() }))),
        "tools/call" => {
            let name = request
                .get("params")
                .and_then(|p| p.get("name"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let args = request
                .get("params")
                .and_then(|p| p.get("arguments"))
                .cloned()
                .unwrap_or_else(|| json!({}));
            match call_tool(core, name, &args) {
                Ok(text) => Some(ok(
                    id,
                    json!({ "content": [{ "type": "text", "text": text }] }),
                )),
                Err(err) => Some(ok(
                    id,
                    json!({
                        "content": [{ "type": "text", "text": err.to_string() }],
                        "isError": true
                    }),
                )),
            }
        }
        "resources/list" => Some(ok(id, json!({ "resources": resources() }))),
        "resources/read" => {
            let uri = request
                .get("params")
                .and_then(|p| p.get("uri"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            match read_resource(core, uri) {
                Ok((mime, text)) => Some(ok(
                    id,
                    json!({
                        "contents": [{ "uri": uri, "mimeType": mime, "text": text }]
                    }),
                )),
                Err(err) => Some(err_result(id, -32602, &err.to_string())),
            }
        }
        "prompts/list" => Some(ok(id, json!({ "prompts": prompts() }))),
        "prompts/get" => {
            let name = request
                .get("params")
                .and_then(|p| p.get("name"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            Some(ok(id, get_prompt(name)))
        }
        _ => id.map(|id| err_result(Some(id), -32601, "method not found")),
    }
}

fn ok(id: Option<Value>, result: Value) -> Value {
    json!({ "jsonrpc": "2.0", "id": id, "result": result })
}

fn err_result(id: Option<Value>, code: i64, message: &str) -> Value {
    json!({ "jsonrpc": "2.0", "id": id, "error": { "code": code, "message": message } })
}

fn text_arg(args: &Value, key: &str) -> String {
    args.get(key)
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string()
}

fn required(args: &Value, key: &str) -> Result<String> {
    let value = text_arg(args, key);
    if value.is_empty() {
        Err(anyhow!("missing argument: {key}"))
    } else {
        Ok(value)
    }
}

fn num_arg(args: &Value, key: &str, fallback: f64) -> f64 {
    args.get(key).and_then(|v| v.as_f64()).unwrap_or(fallback)
}

fn bool_arg(args: &Value, key: &str, fallback: bool) -> bool {
    args.get(key).and_then(|v| v.as_bool()).unwrap_or(fallback)
}

fn settings_public(settings: &Settings) -> Value {
    let mut value = serde_json::to_value(settings).unwrap_or_else(|_| json!({}));
    if let Some(obj) = value.as_object_mut() {
        obj.insert("aiApiKeys".into(), json!({}));
        obj.insert("gdrive_refresh_token".into(), json!(null));
        obj.insert("gdrive_client_secret".into(), json!(null));
    }
    value
}

fn call_tool(core: &mut Core, name: &str, args: &Value) -> Result<String> {
    match name {
        "workspace.get" => Ok(serde_json::to_string_pretty(&core.ws.clone())?),
        "workspace.export" => {
            let path = required(args, "path")?;
            core.export_backup(&path)?;
            Ok(format!("exported to {path}"))
        }
        "workspace.import" => {
            let path = required(args, "path")?;
            if text_arg(args, "format") == "legacy" {
                core.import_legacy(&path)?;
            } else {
                core.import_backup(&path)?;
            }
            Ok("imported".into())
        }
        "grid.list" => Ok(serde_json::to_string_pretty(&core.ws.grids)?),
        "grid.get" => {
            let id = required(args, "gridId")?;
            Ok(serde_json::to_string_pretty(
                core.ws.grid(&id).ok_or_else(|| anyhow!("grid not found"))?,
            )?)
        }
        "grid.create" => {
            let name = text_arg(args, "name");
            let grid = core.create_grid(if name.is_empty() { "New Grid" } else { &name });
            Ok(serde_json::to_string_pretty(&grid)?)
        }
        "grid.rename" => {
            let id = required(args, "gridId")?;
            let name = required(args, "name")?;
            core.rename_grid(&id, &name);
            Ok("renamed".into())
        }
        "grid.delete" => {
            let id = required(args, "gridId")?;
            if core.delete_grid(&id) {
                Ok("deleted".into())
            } else {
                Err(anyhow!("cannot delete the last grid"))
            }
        }
        "grid.switch" => {
            let id = required(args, "gridId")?;
            if core.switch_grid(&id) {
                Ok("switched".into())
            } else {
                Err(anyhow!("grid not found"))
            }
        }
        "grid.move" => {
            let grid = required(args, "gridId")?;
            let folder = text_arg(args, "folderId");
            core.move_grid_to_folder(
                &grid,
                if folder.is_empty() {
                    None
                } else {
                    Some(&folder)
                },
            );
            Ok("moved".into())
        }
        "card.list" => {
            let cards = core
                .ws
                .active_grid()
                .map(|g| g.cards.clone())
                .unwrap_or_default();
            Ok(serde_json::to_string_pretty(&cards)?)
        }
        "card.get" => {
            let id = required(args, "cardId")?;
            let card = core
                .ws
                .card(&id)
                .map(|(_, c)| c.clone())
                .ok_or_else(|| anyhow!("card not found"))?;
            Ok(serde_json::to_string_pretty(&card)?)
        }
        "card.create" => {
            let kind = text_arg(args, "kind");
            let card = core
                .create_card(
                    if kind.is_empty() { "note" } else { &kind },
                    num_arg(args, "x", 64.0),
                    num_arg(args, "y", 64.0),
                )
                .ok_or_else(|| anyhow!("could not create card"))?;
            Ok(serde_json::to_string_pretty(&card)?)
        }
        "card.update" => {
            let id = required(args, "cardId")?;
            let patch = args.get("patch").cloned().unwrap_or_else(|| args.clone());
            let mut object = patch;
            if let Some(obj) = object.as_object_mut() {
                obj.insert("id".into(), json!(id));
            }
            if core.update_card_json(&object.to_string()) {
                Ok("updated".into())
            } else {
                Err(anyhow!("card not found"))
            }
        }
        "card.delete" => {
            let id = required(args, "cardId")?;
            if core.delete_card(&id) {
                Ok("deleted".into())
            } else {
                Err(anyhow!("card not found"))
            }
        }
        "card.duplicate" => {
            let id = required(args, "cardId")?;
            let card = core
                .duplicate_card(&id)
                .ok_or_else(|| anyhow!("card not found"))?;
            Ok(serde_json::to_string_pretty(&card)?)
        }
        "card.move" => {
            let card = required(args, "cardId")?;
            let grid = required(args, "gridId")?;
            if core.send_card_to_grid(&card, &grid) {
                Ok("moved".into())
            } else {
                Err(anyhow!("card or grid not found"))
            }
        }
        "card.search" => {
            let query = text_arg(args, "query");
            Ok(core.search_json(&query))
        }
        "settings.get" => Ok(serde_json::to_string_pretty(&settings_public(
            &core.ws.settings,
        ))?),
        "settings.set" => {
            let key = required(args, "key")?;
            let value = args.get("value").cloned().unwrap_or(Value::Null);
            if core.set_setting_json(&key, &value.to_string()) {
                Ok("ok".into())
            } else {
                Err(anyhow!("invalid setting"))
            }
        }
        "settings.batch" => {
            let patch = args.get("patch").cloned().unwrap_or_else(|| json!({}));
            let mut value = patch;
            merge_settings_value(&mut core.ws.settings, &mut value);
            core.save()?;
            Ok("ok".into())
        }
        "theme.list" => Ok(model::themes().to_string()),
        "theme.set" => {
            let id = required(args, "themeId")?;
            core.set_setting_json("theme", &json!(id).to_string());
            Ok("ok".into())
        }
        "font.list" => Ok(model::fonts().to_string()),
        "powerbar.search" => {
            let query = text_arg(args, "query");
            Ok(core.search_json(&query))
        }
        "powerbar.run" => {
            let id = required(args, "commandId")?;
            Ok(core.command(&id).to_string())
        }
        "ai.providers" => Ok(model::models_by_provider().to_string()),
        "ai.complete" => {
            let provider = if text_arg(args, "provider").is_empty() {
                core.ws.settings.ai_provider.clone()
            } else {
                text_arg(args, "provider")
            };
            let key = core
                .ws
                .settings
                .ai_api_keys
                .get(&provider)
                .cloned()
                .unwrap_or_default();
            let prompt = required(args, "prompt")?;
            let req = AIRequest {
                provider: provider.clone(),
                model: {
                    let model = text_arg(args, "model");
                    if model.is_empty() {
                        core.ws
                            .settings
                            .ai_model
                            .get(&provider)
                            .cloned()
                            .unwrap_or_else(|| ai::default_model(&provider).to_string())
                    } else {
                        model
                    }
                },
                api_key: key,
                prompt,
                system_prompt: ai::system_prompt(),
                web_search: core.ws.settings.ai_web_search,
                server_url: core.ws.settings.ai_local_server_url.clone(),
            };
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()?;
            Ok(runtime.block_on(ai::complete(req, |_| {}))?)
        }
        "sync.now" => {
            let provider = core.ws.settings.cloud_provider.clone();
            if provider == "folder" {
                let folder = core
                    .ws
                    .settings
                    .cloud_folder
                    .clone()
                    .ok_or_else(|| anyhow!("no sync folder configured"))?;
                let (status, ws) =
                    crate::sync::sync_folder(&core.data_dir, std::path::Path::new(&folder))?;
                if let Some(ws) = ws {
                    core.ws = ws;
                    let snapshot = core.ws.clone();
                    core.history.reset(&snapshot);
                }
                Ok(status)
            } else {
                Err(anyhow!(
                    "use git.sync for git, or configure the folder provider"
                ))
            }
        }
        "git.status" => Ok(core.git.status_json()),
        "git.configure" => {
            if let Some(enabled) = args.get("enabled").and_then(|v| v.as_bool()) {
                core.set_setting_json("git_sync_enabled", &enabled.to_string());
            }
            if let Some(remote) = args.get("remote").and_then(|v| v.as_str()) {
                core.set_setting_json("git_remote", &json!(remote).to_string());
            }
            if let Some(branch) = args.get("branch").and_then(|v| v.as_str()) {
                core.set_setting_json("git_branch", &json!(branch).to_string());
            }
            if let Some(auto) = args.get("autoPush").and_then(|v| v.as_bool()) {
                core.set_setting_json("git_auto_push", &auto.to_string());
            }
            if let Some(auto) = args.get("autoPull").and_then(|v| v.as_bool()) {
                core.set_setting_json("git_auto_pull", &auto.to_string());
            }
            Ok(core.git.status_json())
        }
        "git.sync" => {
            let config = core.git_config();
            let dir = core.data_dir.clone();
            let status = core.git.sync_now(&dir, &config)?;
            core.reload_from_disk()?;
            Ok(status)
        }
        "backup.export" => {
            let path = required(args, "path")?;
            core.export_backup(&path)?;
            Ok(format!("exported to {path}"))
        }
        "backup.import" => {
            let path = required(args, "path")?;
            core.import_backup(&path)?;
            Ok("imported".into())
        }
        "update.check" => {
            let channel = core.ws.settings.update_channel.clone();
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()?;
            let state = runtime.block_on(updates::check(&channel))?;
            core.update = state.clone();
            Ok(serde_json::to_string_pretty(&state)?)
        }
        "update.channel.set" => {
            let channel = required(args, "channel")?;
            core.set_setting_json("update_channel", &json!(channel).to_string());
            Ok("ok".into())
        }
        "app.about" => Ok(json!({
            "name": "Corcho",
            "version": VERSION,
            "license": "MIT",
            "features": [
                "infinite canvas", "13 card types", "8 fragments",
                "5 AI providers + local", "folder/Drive/git sync",
                "stable/beta/experimental updates", "MCP server"
            ]
        })
        .to_string()),
        "app.changelog" => Ok(CHANGELOG.into()),
        "attachments.list" => Ok(serde_json::to_string_pretty(
            &crate::storage::list_attachments(&core.data_dir),
        )?),
        "attachments.read" => {
            let name = required(args, "name")?;
            let bytes = crate::storage::read_attachment(&core.data_dir, &name)?;
            use base64::Engine;
            Ok(base64::engine::general_purpose::STANDARD.encode(bytes))
        }
        "script.run" => {
            let script = required(args, "script")?;
            let value = integrations::run_script(&script, std::time::Duration::from_secs(30))?;
            Ok(value.to_string())
        }
        "mpris.list" => Ok(integrations::mpris_players().to_string()),
        "mpris.action" => {
            let player = required(args, "player")?;
            let action = required(args, "action")?;
            Ok(integrations::mpris_action(&player, &action).to_string())
        }
        "dialog.open" => Err(anyhow!("dialog.open is GUI-only")),
        "quit" => {
            let confirm = bool_arg(args, "confirm", false);
            if confirm {
                std::process::exit(0);
            }
            Err(anyhow!("pass confirm=true"))
        }
        _ => Err(anyhow!("unknown tool: {name}")),
    }
}

fn tools() -> Vec<Value> {
    let empty = json!({});
    let mut list = Vec::new();
    let mut add = |name: &str, description: &str, props: Value, required: Vec<&str>| {
        list.push(json!({
            "name": name,
            "description": description,
            "inputSchema": {
                "type": "object",
                "properties": props,
                "required": required,
                "additionalProperties": false
            }
        }));
    };

    add(
        "workspace.get",
        "Return the full workspace.",
        empty.clone(),
        vec![],
    );
    add(
        "workspace.export",
        "Write a backup zip.",
        json!({"path":{"type":"string"}}),
        vec!["path"],
    );
    add(
        "workspace.import",
        "Import a backup or legacy folder.",
        json!({"path":{"type":"string"},"format":{"type":"string","enum":["corcho","legacy"]}}),
        vec!["path"],
    );
    add("grid.list", "List grids.", empty.clone(), vec![]);
    add(
        "grid.get",
        "Return one grid with its cards.",
        json!({"gridId":{"type":"string"}}),
        vec!["gridId"],
    );
    add(
        "grid.create",
        "Create a grid and switch to it.",
        json!({"name":{"type":"string"}}),
        vec![],
    );
    add(
        "grid.rename",
        "Rename a grid.",
        json!({"gridId":{"type":"string"},"name":{"type":"string"}}),
        vec!["gridId", "name"],
    );
    add(
        "grid.delete",
        "Delete a grid (not the last one).",
        json!({"gridId":{"type":"string"}}),
        vec!["gridId"],
    );
    add(
        "grid.switch",
        "Switch the active grid.",
        json!({"gridId":{"type":"string"}}),
        vec!["gridId"],
    );
    add(
        "grid.move",
        "Move a grid into a folder.",
        json!({"gridId":{"type":"string"},"folderId":{"type":"string"}}),
        vec!["gridId"],
    );
    add(
        "card.list",
        "List cards in the active grid.",
        empty.clone(),
        vec![],
    );
    add(
        "card.get",
        "Return one card.",
        json!({"cardId":{"type":"string"}}),
        vec!["cardId"],
    );
    add(
        "card.create",
        "Create a card in the active grid.",
        json!({"kind":{"type":"string"},"x":{"type":"number"},"y":{"type":"number"}}),
        vec![],
    );
    add(
        "card.update",
        "Patch a card. Pass geometry/title/text/payload fields.",
        json!({"cardId":{"type":"string"},"patch":{"type":"object"}}),
        vec!["cardId"],
    );
    add(
        "card.delete",
        "Delete a card.",
        json!({"cardId":{"type":"string"}}),
        vec!["cardId"],
    );
    add(
        "card.duplicate",
        "Duplicate a card.",
        json!({"cardId":{"type":"string"}}),
        vec!["cardId"],
    );
    add(
        "card.move",
        "Move a card to another grid.",
        json!({"cardId":{"type":"string"},"gridId":{"type":"string"}}),
        vec!["cardId", "gridId"],
    );
    add(
        "card.search",
        "Search cards and grids.",
        json!({"query":{"type":"string"}}),
        vec!["query"],
    );
    add(
        "settings.get",
        "Read settings (secrets redacted).",
        empty.clone(),
        vec![],
    );
    add(
        "settings.set",
        "Set one setting.",
        json!({"key":{"type":"string"},"value":{}}),
        vec!["key", "value"],
    );
    add(
        "settings.batch",
        "Apply a settings patch atomically.",
        json!({"patch":{"type":"object"}}),
        vec!["patch"],
    );
    add("theme.list", "List themes.", empty.clone(), vec![]);
    add(
        "theme.set",
        "Set the active theme.",
        json!({"themeId":{"type":"string"}}),
        vec!["themeId"],
    );
    add("font.list", "List fonts.", empty.clone(), vec![]);
    add(
        "powerbar.search",
        "Search the Powerbar.",
        json!({"query":{"type":"string"}}),
        vec!["query"],
    );
    add(
        "powerbar.run",
        "Run a Powerbar command.",
        json!({"commandId":{"type":"string"}}),
        vec!["commandId"],
    );
    add(
        "ai.providers",
        "List providers and models.",
        empty.clone(),
        vec![],
    );
    add(
        "ai.complete",
        "Run a completion with the configured provider.",
        json!({"provider":{"type":"string"},"model":{"type":"string"},"prompt":{"type":"string"}}),
        vec!["prompt"],
    );
    add(
        "sync.now",
        "Sync the folder provider.",
        empty.clone(),
        vec![],
    );
    add("git.status", "Git sync status.", empty.clone(), vec![]);
    add(
        "git.configure",
        "Configure git sync.",
        json!({"enabled":{"type":"boolean"},"remote":{"type":"string"},"branch":{"type":"string"},"autoPush":{"type":"boolean"},"autoPull":{"type":"boolean"}}),
        vec![],
    );
    add(
        "git.sync",
        "Commit, merge and push git sync.",
        empty.clone(),
        vec![],
    );
    add(
        "backup.export",
        "Export a backup zip.",
        json!({"path":{"type":"string"}}),
        vec!["path"],
    );
    add(
        "backup.import",
        "Import a backup zip.",
        json!({"path":{"type":"string"}}),
        vec!["path"],
    );
    add(
        "update.check",
        "Check the update channel.",
        empty.clone(),
        vec![],
    );
    add(
        "update.channel.set",
        "Set stable/beta/experimental.",
        json!({"channel":{"type":"string","enum":["stable","beta","experimental"]}}),
        vec!["channel"],
    );
    add(
        "app.about",
        "App version and features.",
        empty.clone(),
        vec![],
    );
    add(
        "app.changelog",
        "Return the changelog.",
        empty.clone(),
        vec![],
    );
    add(
        "attachments.list",
        "List attachments.",
        empty.clone(),
        vec![],
    );
    add(
        "attachments.read",
        "Read an attachment as base64.",
        json!({"name":{"type":"string"}}),
        vec!["name"],
    );
    add(
        "script.run",
        "Run a script in /bin/sh (30s timeout).",
        json!({"script":{"type":"string"}}),
        vec!["script"],
    );
    add("mpris.list", "List media players.", empty.clone(), vec![]);
    add(
        "mpris.action",
        "Control a media player.",
        json!({"player":{"type":"string"},"action":{"type":"string"}}),
        vec!["player", "action"],
    );
    add(
        "quit",
        "Quit the app (confirm=true).",
        json!({"confirm":{"type":"boolean"}}),
        vec!["confirm"],
    );
    list
}

fn resources() -> Vec<Value> {
    vec![
        json!({"uri":"corcho://workspace","name":"Workspace","mimeType":"application/json"}),
        json!({"uri":"corcho://settings","name":"Settings","mimeType":"application/json"}),
        json!({"uri":"corcho://themes","name":"Themes","mimeType":"application/json"}),
        json!({"uri":"corcho://changelog","name":"Changelog","mimeType":"text/markdown"}),
    ]
}

fn read_resource(core: &mut Core, uri: &str) -> Result<(&'static str, String)> {
    if uri == "corcho://workspace" {
        return Ok(("application/json", serde_json::to_string_pretty(&core.ws)?));
    }
    if uri == "corcho://settings" {
        return Ok((
            "application/json",
            serde_json::to_string_pretty(&settings_public(&core.ws.settings))?,
        ));
    }
    if uri == "corcho://themes" {
        return Ok(("application/json", model::themes().to_string()));
    }
    if uri == "corcho://changelog" {
        return Ok(("text/markdown", CHANGELOG.into()));
    }
    if let Some(id) = uri.strip_prefix("corcho://grid/") {
        let grid = core.ws.grid(id).ok_or_else(|| anyhow!("grid not found"))?;
        return Ok(("application/json", serde_json::to_string_pretty(grid)?));
    }
    if let Some(id) = uri.strip_prefix("corcho://card/") {
        let card = core
            .ws
            .card(id)
            .map(|(_, c)| c)
            .ok_or_else(|| anyhow!("card not found"))?;
        return Ok(("application/json", serde_json::to_string_pretty(card)?));
    }
    Err(anyhow!("unknown resource: {uri}"))
}

fn prompts() -> Vec<Value> {
    vec![
        json!({"name":"organize-inbox","description":"Triage uncategorized notes into grids and checklists."}),
        json!({"name":"summarize-grid","description":"Summarize the active grid and its open work."}),
        json!({"name":"weekly-review","description":"Collect pomodoros, checklists and notes into a weekly review."}),
    ]
}

fn get_prompt(name: &str) -> Value {
    let text = match name {
        "organize-inbox" => "Read corcho://workspace, find notes that are not in a meaningful grid, and propose card.create calls to organize them. Use card.move for existing cards.",
        "summarize-grid" => "Read the active grid with grid.get and card.list, then write a short summary of themes, open tasks and stale items.",
        "weekly-review" => "Collect completed checklists, pomodoro sessions and notes from the last seven days. Write a weekly review card with highlight, blockers and next steps.",
        _ => "Unknown prompt.",
    };
    json!({
        "description": name,
        "messages": [{ "role": "user", "content": { "type": "text", "text": text } }]
    })
}

const CHANGELOG: &str = "Corcho 0.1.0\n\n- Native Rust + Qt6 rewrite.\n- Infinite canvas and thirteen card types.\n- Eight fragment modes, including Spectrum audio.\n- Five AI providers plus a local server.\n- Folder, Google Drive and git sync with union conflict merge.\n- Stable, beta and experimental update channels.\n- MCP server with tools, resources and prompts.\n- Fully free software (MIT), no telemetry.\n";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initialize_and_tools_list_are_valid() {
        let mut core = Core::fallback();
        let init = handle(
            &mut core,
            json!({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}),
        )
        .unwrap();
        assert_eq!(init["result"]["serverInfo"]["name"], "corcho");

        let list = handle(
            &mut core,
            json!({"jsonrpc":"2.0","id":2,"method":"tools/list"}),
        )
        .unwrap();
        let tools = list["result"]["tools"].as_array().unwrap();
        assert!(tools.iter().any(|t| t["name"] == "card.create"));
        assert!(tools.iter().any(|t| t["name"] == "git.sync"));
    }

    #[test]
    fn missing_argument_is_an_error_result() {
        let mut core = Core::fallback();
        let response = handle(
            &mut core,
            json!({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"grid.get","arguments":{}}}),
        )
        .unwrap();
        assert_eq!(response["result"]["isError"], true);
    }
}
