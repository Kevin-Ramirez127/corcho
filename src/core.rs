use std::path::PathBuf;

use anyhow::Result;
use serde_json::{json, Value};

use crate::history::History;
use crate::integrations::Adblock;
use crate::model::{Card, Folder, Grid, Settings, Workspace};
use crate::search;
use crate::storage;

pub struct Core {
    pub data_dir: PathBuf,
    pub ws: Workspace,
    pub history: History,
    pub adblock: Adblock,
    pub update: crate::updates::UpdateState,
    pub last_saved: Option<std::time::Instant>,
}

impl Core {
    pub fn boot() -> Result<Self> {
        let default_dir = storage::default_data_dir();
        storage::ensure_dirs(&default_dir)?;
        let ws = storage::load_workspace(&default_dir)?;
        let mut core = Self {
            data_dir: default_dir,
            history: History::new(ws.settings.undo_steps, ws.clone()),
            ws,
            adblock: Adblock::new(),
            update: crate::updates::UpdateState::default(),
            last_saved: None,
        };
        core.adblock.set_enabled(core.ws.settings.ad_blocker);
        core.adblock.load_lists(&core.data_dir);
        Ok(core)
    }

    pub fn fallback() -> Self {
        let ws = Workspace::default();
        Self {
            data_dir: storage::default_data_dir(),
            history: History::new(ws.settings.undo_steps, ws.clone()),
            ws,
            adblock: Adblock::new(),
            update: crate::updates::UpdateState::default(),
            last_saved: None,
        }
    }

    pub fn save(&mut self) -> Result<()> {
        storage::save_workspace(&self.data_dir, &self.ws)?;
        self.last_saved = Some(std::time::Instant::now());
        Ok(())
    }

    pub fn save_quiet(&mut self) {
        if let Err(e) = self.save() {
            tracing::error!("save failed: {e}");
        }
    }

    /// Snapshot the pre-mutation state so undo can restore it.
    pub fn checkpoint(&mut self) {
        self.history.push(&self.ws);
    }

    pub fn undo(&mut self) -> bool {
        if let Some(ws) = self.history.undo() {
            self.ws = ws;
            self.save_quiet();
            true
        } else {
            false
        }
    }

    pub fn redo(&mut self) -> bool {
        if let Some(ws) = self.history.redo() {
            self.ws = ws;
            self.save_quiet();
            true
        } else {
            false
        }
    }

    pub fn grids_json(&self) -> String {
        serde_json::to_string(&self.ws.grids).unwrap_or_else(|_| "[]".into())
    }

    pub fn cards_json(&self) -> String {
        let cards: Vec<Card> = self
            .ws
            .active_grid()
            .map(|g| g.cards.clone())
            .unwrap_or_default();
        serde_json::to_string(&cards).unwrap_or_else(|_| "[]".into())
    }

    pub fn folders_json(&self) -> String {
        serde_json::to_string(&self.ws.folders).unwrap_or_else(|_| "[]".into())
    }

    pub fn settings_json(&self) -> String {
        serde_json::to_string(&self.ws.settings).unwrap_or_else(|_| "{}".into())
    }

    pub fn active_grid_id(&self) -> String {
        self.ws.active_grid_id.clone().unwrap_or_default()
    }

    pub fn active_grid_view(&self) -> (f64, f64, f64) {
        self.ws
            .active_grid()
            .map(|g| (g.pan_x, g.pan_y, g.zoom))
            .unwrap_or((0.0, 0.0, 1.0))
    }

    pub fn set_view(&mut self, pan_x: f64, pan_y: f64, zoom: f64) {
        if let Some(g) = self.ws.active_grid_mut() {
            g.pan_x = pan_x;
            g.pan_y = pan_y;
            g.zoom = zoom.clamp(0.2, 3.0);
        }
    }

    pub fn switch_grid(&mut self, id: &str) -> bool {
        if self.ws.grid(id).is_some() {
            self.ws.active_grid_id = Some(id.to_string());
            self.save_quiet();
            true
        } else {
            false
        }
    }

    pub fn create_card(&mut self, kind: &str, x: f64, y: f64) -> Option<Card> {
        self.checkpoint();
        let mut card = Card::new(kind, x.round(), y.round());
        populate_defaults(&mut card, &self.ws);
        if let Some(g) = self.ws.active_grid_mut() {
            g.cards.push(card.clone());
        } else {
            return None;
        }
        self.save_quiet();
        Some(card)
    }

    pub fn update_card_json(&mut self, json_str: &str) -> bool {
        let Ok(value) = serde_json::from_str::<Value>(json_str) else {
            return false;
        };
        let Some(id) = value.get("id").and_then(|v| v.as_str()).map(str::to_string) else {
            return false;
        };
        self.checkpoint();
        let Some(card) = self.ws.card_mut(&id) else {
            return false;
        };
        if let Some(v) = value.get("x").and_then(|v| v.as_f64()) {
            card.x = v;
        }
        if let Some(v) = value.get("y").and_then(|v| v.as_f64()) {
            card.y = v;
        }
        if let Some(v) = value.get("width").and_then(|v| v.as_f64()) {
            card.width = v.max(80.0);
        }
        if let Some(v) = value.get("height").and_then(|v| v.as_f64()) {
            card.height = v.max(64.0);
        }
        if let Some(v) = value.get("title").and_then(|v| v.as_str()) {
            card.title = v.to_string();
        }
        if let Some(v) = value.get("text").and_then(|v| v.as_str()) {
            card.text = v.to_string();
        }
        if let Some(v) = value.get("color").and_then(|v| v.as_str()) {
            card.color = v.to_string();
        }
        if let Some(v) = value.get("icon").and_then(|v| v.as_str()) {
            card.icon = v.to_string();
        }
        if let Some(v) = value.get("locked").and_then(|v| v.as_bool()) {
            card.locked = v;
        }
        if let Some(obj) = value.get("payload").and_then(|v| v.as_object()) {
            for (k, v) in obj {
                card.set(k, v.clone());
            }
        }
        self.save_quiet();
        true
    }

    pub fn delete_card(&mut self, id: &str) -> bool {
        self.checkpoint();
        let removed = self.ws.remove_card(id).is_some();
        if removed {
            self.save_quiet();
        }
        removed
    }

    pub fn duplicate_card(&mut self, id: &str) -> Option<Card> {
        let (grid_id, mut card) = {
            let (g, c) = self.ws.card(id)?;
            (g.id.clone(), c.clone())
        };
        self.checkpoint();
        card.id = uuid::Uuid::new_v4().to_string();
        card.x += 32.0;
        card.y += 32.0;
        if let Some(g) = self.ws.grid_mut(&grid_id) {
            g.cards.push(card.clone());
        }
        self.save_quiet();
        Some(card)
    }

    pub fn send_card_to_grid(&mut self, card_id: &str, grid_id: &str) -> bool {
        let Some(card) = self.ws.remove_card(card_id) else {
            return false;
        };
        self.checkpoint();
        if let Some(g) = self.ws.grid_mut(grid_id) {
            g.cards.push(card);
            self.save_quiet();
            true
        } else {
            false
        }
    }

    pub fn create_grid(&mut self, name: &str) -> Grid {
        self.checkpoint();
        let g = self.ws.add_grid(name);
        self.ws.active_grid_id = Some(g.id.clone());
        self.save_quiet();
        g
    }

    pub fn rename_grid(&mut self, id: &str, name: &str) -> bool {
        self.checkpoint();
        let ok = if let Some(g) = self.ws.grid_mut(id) {
            g.name = name.to_string();
            true
        } else {
            false
        };
        if ok {
            self.save_quiet();
        }
        ok
    }

    pub fn delete_grid(&mut self, id: &str) -> bool {
        if self.ws.grids.len() <= 1 {
            return false;
        }
        self.checkpoint();
        self.ws.grids.retain(|g| g.id != id);
        if self.ws.active_grid_id.as_deref() == Some(id) {
            self.ws.active_grid_id = self.ws.grids.first().map(|g| g.id.clone());
        }
        self.save_quiet();
        true
    }

    pub fn create_folder(&mut self, name: &str) -> Folder {
        self.checkpoint();
        let f = self.ws.add_folder(name);
        self.save_quiet();
        f
    }

    pub fn rename_folder(&mut self, id: &str, name: &str) -> bool {
        self.checkpoint();
        let ok = if let Some(f) = self.ws.folders.iter_mut().find(|f| f.id == id) {
            f.name = name.to_string();
            true
        } else {
            false
        };
        if ok {
            self.save_quiet();
        }
        ok
    }

    pub fn delete_folder(&mut self, id: &str, keep_content: bool) -> bool {
        self.checkpoint();
        if !keep_content {
            self.ws.grids.retain(|g| g.folder_id.as_deref() != Some(id));
        } else {
            for g in &mut self.ws.grids {
                if g.folder_id.as_deref() == Some(id) {
                    g.folder_id = None;
                }
            }
        }
        self.ws.folders.retain(|f| f.id != id);
        if self.ws.grids.is_empty() {
            self.ws = {
                let mut w = self.ws.clone();
                let g = w.add_grid("Grid A");
                w.active_grid_id = Some(g.id);
                w
            };
        }
        self.save_quiet();
        true
    }

    pub fn toggle_folder(&mut self, id: &str) {
        if let Some(f) = self.ws.folders.iter_mut().find(|f| f.id == id) {
            f.collapsed = !f.collapsed;
        }
        self.save_quiet();
    }

    pub fn move_grid_to_folder(&mut self, grid_id: &str, folder_id: Option<&str>) -> bool {
        self.checkpoint();
        let ok = if let Some(g) = self.ws.grid_mut(grid_id) {
            g.folder_id = folder_id.map(str::to_string);
            true
        } else {
            false
        };
        if ok {
            self.save_quiet();
        }
        ok
    }

    pub fn reorder_grid(&mut self, id: &str, before_id: Option<&str>) -> bool {
        let Some(pos) = self.ws.grids.iter().position(|g| g.id == id) else {
            return false;
        };
        self.checkpoint();
        let g = self.ws.grids.remove(pos);
        let insert = before_id
            .and_then(|b| self.ws.grids.iter().position(|x| x.id == b))
            .unwrap_or(self.ws.grids.len());
        self.ws.grids.insert(insert, g);
        self.save_quiet();
        true
    }

    pub fn set_setting_json(&mut self, key: &str, value_json: &str) -> bool {
        let Ok(value) = serde_json::from_str::<Value>(value_json) else {
            return false;
        };
        let mut extra = serde_json::Map::new();
        extra.insert(key.to_string(), value);
        let mut value = Value::Object(extra);
        merge_settings_value(&mut self.ws.settings, &mut value);
        if key == "undo_steps" {
            self.history.set_limit(self.ws.settings.undo_steps);
        }
        if key == "ad_blocker" {
            self.adblock.set_enabled(self.ws.settings.ad_blocker);
        }
        self.save_quiet();
        true
    }

    pub fn search_json(&self, query: &str) -> String {
        serde_json::to_string(&search::search(&self.ws, query)).unwrap_or_else(|_| "[]".into())
    }

    pub fn export_backup(&mut self, dest: &str) -> Result<()> {
        self.save()?;
        storage::export_zip(&self.data_dir, &PathBuf::from(dest))
    }

    pub fn import_backup(&mut self, src: &str) -> Result<()> {
        let ws = storage::import_zip(&self.data_dir, &PathBuf::from(src))?;
        self.ws = ws;
        self.history.reset(&self.ws);
        self.adblock.set_enabled(self.ws.settings.ad_blocker);
        self.save()
    }

    pub fn import_legacy(&mut self, src: &str) -> Result<()> {
        let ws = storage::import_legacy(&PathBuf::from(src))?;
        self.ws = ws;
        self.history.reset(&self.ws);
        self.save()
    }

    pub fn set_data_dir(&mut self, dir: &str) -> Result<()> {
        self.data_dir = PathBuf::from(dir);
        storage::ensure_dirs(&self.data_dir)?;
        self.ws.settings.data_dir = Some(dir.to_string());
        self.save()
    }

    pub fn spawn(&mut self, kind: &str) -> Option<Card> {
        let n = self.ws.active_grid().map(|g| g.cards.len()).unwrap_or(0);
        let x = 64.0 + (n % 4) as f64 * 380.0;
        let y = 64.0 + (n / 4) as f64 * 330.0;
        self.create_card(kind, x, y)
    }

    pub fn command(&mut self, id: &str) -> Value {
        tracing::info!("powerbar command: {id}");
        match id {
            "create-note" => self.spawn("note").map(card_json).unwrap_or(Value::Null),
            "create-website" => self.spawn("website").map(card_json).unwrap_or(Value::Null),
            "create-bookmark" => self.spawn("bookmark").map(card_json).unwrap_or(Value::Null),
            "create-api" => self.spawn("api").map(card_json).unwrap_or(Value::Null),
            "create-ai" => self.spawn("ai").map(card_json).unwrap_or(Value::Null),
            "create-script" => self.spawn("script").map(card_json).unwrap_or(Value::Null),
            "create-fragment" => self.spawn("fragment").map(card_json).unwrap_or(Value::Null),
            "create-checklist" => self.spawn("checklist").map(card_json).unwrap_or(Value::Null),
            "create-kanban" => self.spawn("kanban").map(card_json).unwrap_or(Value::Null),
            "create-whiteboard" => self.spawn("whiteboard").map(card_json).unwrap_or(Value::Null),
            "create-pomodoro" => self.spawn("pomodoro").map(card_json).unwrap_or(Value::Null),
            "create-mpris" => self.spawn("mpris").map(card_json).unwrap_or(Value::Null),
            "create-grid" => json!({"grid": self.create_grid("New Grid")}),
            "create-folder" => json!({"folder": self.create_folder("New Folder")}),
            "undo" => json!({"ok": self.undo()}),
            "redo" => json!({"ok": self.redo()}),
            _ if id.starts_with("theme-") => {
                let theme = id.trim_start_matches("theme-");
                self.set_setting_json("theme", &serde_json::to_string(theme).unwrap());
                json!({"ok": true})
            }
            _ => json!({"ok": false, "error": "unknown command"}),
        }
    }


    pub fn reset_tutorials(&mut self) {
        let s = &mut self.ws.settings;
        s.onboarding_completed = false;
        s.card_tutorial_completed = false;
        s.context_tutorial_completed = false;
        s.fragment_tutorial_completed = false;
        s.powerbar_tutorial_completed = false;
        self.save_quiet();
    }
}

pub fn card_json(card: Card) -> Value {
    serde_json::to_value(card).unwrap_or(Value::Null)
}

pub fn merge_settings_value(settings: &mut Settings, value: &mut Value) {
    let mut base = serde_json::to_value(&*settings).unwrap_or_else(|_| json!({}));
    if let (Some(base_obj), Some(extra)) = (base.as_object_mut(), value.as_object()) {
        for (k, v) in extra {
            base_obj.insert(k.clone(), v.clone());
        }
    }
    if let Ok(next) = serde_json::from_value::<Settings>(base) {
        *settings = next;
    }
}

fn populate_defaults(card: &mut Card, ws: &Workspace) {
    match card.kind.as_str() {
        "website" => {
            card.set("url", json!(""));
            card.set("websiteMode", json!("webview"));
        }
        "bookmark" => {
            card.set("url", json!(""));
            card.set("websiteMode", json!("bookmark"));
        }
        "api" => {
            card.set("apiUrl", json!(""));
            card.set("method", json!("GET"));
            card.set("fields", json!([]));
            card.set("refreshSeconds", json!(0));
            card.set("lastBody", json!(""));
        }
        "ai" => {
            card.set("prompt", json!(""));
            card.set("provider", json!(ws.settings.ai_provider));
            card.set("model", json!(""));
            card.set("lastResult", json!(""));
            card.set("webSearch", json!(ws.settings.ai_web_search));
        }
        "script" => {
            card.set("script", json!(""));
            card.set("lastOutput", json!(""));
        }
        "fragment" => {
            card.set("fragmentMode", json!("pop"));
            card.set("accent", json!("#d98e5c"));
            card.set("speed", json!("medium"));
        }
        "gridlink" => {
            card.set("targetGridId", json!(""));
        }
        "checklist" => {
            card.set("items", json!([]));
        }
        "kanban" => {
            card.set(
                "columns",
                json!([
                    {"id":"todo","title":"To do","items":[]},
                    {"id":"doing","title":"In progress","items":[]},
                    {"id":"done","title":"Done","items":[]}
                ]),
            );
        }
        "whiteboard" => {
            card.set("strokes", json!([]));
            card.set("penColor", json!("#e8e8ea"));
            card.set("penWidth", json!(3));
        }
        "pomodoro" => {
            card.set("workMinutes", json!(25));
            card.set("breakMinutes", json!(5));
            card.set("sessions", json!(0));
            card.set("phase", json!("work"));
            card.set("remaining", json!(25 * 60));
        }
        "mpris" => {
            card.set("playerName", json!(""));
        }
        _ => {}
    }
}

pub fn now_iso() -> String {
    time::OffsetDateTime::now_utc()
        .replace_nanosecond(0)
        .unwrap_or_else(|_| time::OffsetDateTime::now_utc())
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap_or_default()
}


