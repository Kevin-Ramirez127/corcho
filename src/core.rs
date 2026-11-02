use std::path::PathBuf;

use anyhow::Result;
use serde_json::{json, Value};

use crate::history::History;
use crate::integrations::Adblock;
use crate::model::{CalendarDef, Card, DateLink, Folder, Grid, Settings, Workspace};
use crate::search;
use crate::storage;
use crate::theme;

pub struct Core {
    pub data_dir: PathBuf,
    pub ws: Workspace,
    pub history: History,
    pub adblock: Adblock,
    pub git: crate::gitsync::GitSync,
    pub update: crate::updates::UpdateState,
    pub last_saved: Option<std::time::Instant>,
    pub last_file_mtime: Option<std::time::SystemTime>,
}

impl Core {
    pub fn boot() -> Result<Self> {
        let default_dir = storage::default_data_dir();
        storage::ensure_dirs(&default_dir)?;
        let mut ws = storage::load_workspace(&default_dir)?;
        let config = crate::gitsync::config_from(&ws.settings);
        let git = crate::gitsync::GitSync::new(config.clone());

        if config.enabled && !config.remote.is_empty() {
            if let Err(err) = git.ensure_repo(&default_dir, &config) {
                tracing::warn!("git sync setup failed: {err}");
            }
            if config.auto_pull {
                match git.pull_at_start(&default_dir, &config) {
                    Ok(true) => {
                        if let Ok(fresh) = storage::load_workspace(&default_dir) {
                            ws = fresh;
                        }
                    }
                    Ok(false) => {}
                    Err(err) => tracing::warn!("git pull failed: {err}"),
                }
            }
        }
        git.start_worker(default_dir.clone());
        let last_file_mtime = storage::workspace_path(&default_dir)
            .metadata()
            .and_then(|m| m.modified())
            .ok();

        let mut core = Self {
            data_dir: default_dir,
            history: History::new(ws.settings.undo_steps, ws.clone()),
            ws,
            adblock: Adblock::new(),
            git,
            update: crate::updates::UpdateState::default(),
            last_saved: None,
            last_file_mtime,
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
            git: crate::gitsync::GitSync::default(),
            update: crate::updates::UpdateState::default(),
            last_saved: None,
            last_file_mtime: None,
        }
    }

    pub fn save(&mut self) -> Result<()> {
        self.ws.revision = self.ws.revision.saturating_add(1);
        storage::save_workspace(&self.data_dir, &self.ws)?;
        self.last_saved = Some(std::time::Instant::now());
        self.last_file_mtime = storage::workspace_path(&self.data_dir)
            .metadata()
            .and_then(|m| m.modified())
            .ok();
        self.git.mark_dirty();
        Ok(())
    }

    pub fn reload_from_disk(&mut self) -> Result<()> {
        self.ws = storage::load_workspace(&self.data_dir)?;
        self.history.reset(&self.ws);
        self.adblock.set_enabled(self.ws.settings.ad_blocker);
        self.last_file_mtime = storage::workspace_path(&self.data_dir)
            .metadata()
            .and_then(|m| m.modified())
            .ok();
        Ok(())
    }

    /// Reload when another process (typically the GUI or another MCP client)
    /// has written the workspace since this Core last loaded or saved it.
    pub fn reload_if_changed(&mut self) -> Result<bool> {
        let mtime = storage::workspace_path(&self.data_dir)
            .metadata()
            .and_then(|m| m.modified())
            .ok();
        if mtime.is_some() && mtime != self.last_file_mtime {
            self.reload_from_disk()?;
            return Ok(true);
        }
        Ok(false)
    }

    pub fn git_config(&self) -> crate::gitsync::GitConfig {
        crate::gitsync::config_from(&self.ws.settings)
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

    pub fn themes_json(&self) -> String {
        theme::themes_json(&self.data_dir).to_string()
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

    pub fn set_viewport(&mut self, width: f64, height: f64) {
        if width <= 0.0 || height <= 0.0 {
            return;
        }
        if (self.ws.viewport_width - width).abs() > 0.5
            || (self.ws.viewport_height - height).abs() > 0.5
        {
            self.ws.viewport_width = width;
            self.ws.viewport_height = height;
            self.save_quiet();
        }
    }

    /// The world-space rectangle currently visible in the canvas.
    pub fn world_frame(
        &self,
        grid_id: Option<&str>,
        width: Option<f64>,
        height: Option<f64>,
    ) -> Option<(String, f64, f64, f64, f64)> {
        let grid = match grid_id {
            Some(id) => self.ws.grid(id)?,
            None => self.ws.active_grid()?,
        };
        let zoom = grid.zoom.clamp(0.2, 3.0);
        let w = width.filter(|v| *v > 0.0).unwrap_or(self.ws.viewport_width);
        let h = height
            .filter(|v| *v > 0.0)
            .unwrap_or(self.ws.viewport_height);
        if w <= 0.0 || h <= 0.0 {
            return None;
        }
        Some((
            grid.id.clone(),
            -grid.pan_x / zoom,
            -grid.pan_y / zoom,
            w / zoom,
            h / zoom,
        ))
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
        {
            let g = self.ws.active_grid_mut()?;
            g.cards.push(card.clone());
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
        self.ws.prune_date_links();
        self.save_quiet();
        true
    }

    pub fn delete_card(&mut self, id: &str) -> bool {
        self.checkpoint();
        let removed = self.ws.remove_card(id).is_some();
        if removed {
            self.ws.prune_date_links();
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

    pub fn set_grid_icon(&mut self, id: &str, icon: &str) -> bool {
        let icon = icon.trim();
        if icon.is_empty() {
            return false;
        }
        self.checkpoint();
        let Some(grid) = self.ws.grid_mut(id) else {
            return false;
        };
        grid.icon = icon.to_string();
        self.save_quiet();
        true
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
        let known = serde_json::to_value(&self.ws.settings)
            .ok()
            .and_then(|v| v.as_object().map(|o| o.contains_key(key)))
            .unwrap_or(false);
        if !known {
            return false;
        }
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
        if key.starts_with("git_") {
            let config = crate::gitsync::config_from(&self.ws.settings);
            self.git.configure(config.clone());
            if config.enabled && !config.remote.is_empty() {
                if let Err(err) = self.git.ensure_repo(&self.data_dir.clone(), &config) {
                    tracing::warn!("git setup failed: {err}");
                }
            }
        }
        self.save_quiet();
        true
    }

    pub fn search_json(&self, query: &str) -> String {
        serde_json::to_string(&search::search(&self.ws, query)).unwrap_or_else(|_| "[]".into())
    }

    pub fn calendar_json(&self) -> String {
        let links: Vec<Value> = self
            .ws
            .date_links
            .iter()
            .filter_map(|link| self.resolve_date_link(link))
            .collect();
        json!({
            "calendars": self.ws.calendars,
            "dateLinks": links
        })
        .to_string()
    }

    fn resolve_date_link(&self, link: &DateLink) -> Option<Value> {
        let mut title = link.title.clone();
        let mut source_kind = None;
        let mut done = false;
        if let Some(card_id) = link.source_card_id.as_deref() {
            let (_, card) = self.ws.card(card_id)?;
            source_kind = Some(card.kind.clone());
            if let Some(item_id) = link.source_item_id.as_deref() {
                let (item_title, item_done) = find_item(card, item_id)?;
                if !item_title.is_empty() {
                    title = item_title;
                }
                done = item_done;
            } else if !card.title.is_empty() {
                title = card.title.clone();
            }
        }
        Some(json!({
            "id": link.id,
            "calendarIds": link.calendar_ids,
            "date": link.date,
            "title": title,
            "sourceCardId": link.source_card_id,
            "sourceItemId": link.source_item_id,
            "sourceKind": source_kind,
            "done": done
        }))
    }

    pub fn calendar_agenda(&self, from: &str, to: &str, calendar_ids: &[String]) -> Vec<Value> {
        self.ws
            .date_links
            .iter()
            .filter(|link| link.date.as_str() >= from && link.date.as_str() <= to)
            .filter(|link| {
                calendar_ids.is_empty()
                    || link
                        .calendar_ids
                        .iter()
                        .any(|id| calendar_ids.iter().any(|wanted| wanted == id))
            })
            .filter_map(|link| self.resolve_date_link(link))
            .collect()
    }

    pub fn add_calendar(&mut self, name: &str, color: &str) -> CalendarDef {
        self.checkpoint();
        let calendar = CalendarDef::new(name, color);
        self.ws.calendars.push(calendar.clone());
        self.save_quiet();
        calendar
    }

    pub fn update_calendar(&mut self, id: &str, name: Option<&str>, color: Option<&str>) -> bool {
        if !self.ws.calendars.iter().any(|c| c.id == id) {
            return false;
        }
        self.checkpoint();
        let Some(calendar) = self.ws.calendars.iter_mut().find(|c| c.id == id) else {
            return false;
        };
        if let Some(name) = name {
            calendar.name = name.to_string();
        }
        if let Some(color) = color {
            calendar.color = color.to_string();
        }
        self.save_quiet();
        true
    }

    pub fn delete_calendar(&mut self, id: &str) -> bool {
        let Some(pos) = self.ws.calendars.iter().position(|c| c.id == id) else {
            return false;
        };
        self.checkpoint();
        self.ws.calendars.remove(pos);
        for link in &mut self.ws.date_links {
            link.calendar_ids.retain(|calendar_id| calendar_id != id);
        }
        self.ws
            .date_links
            .retain(|link| !link.calendar_ids.is_empty());
        self.save_quiet();
        true
    }

    pub fn add_date_link(
        &mut self,
        calendar_ids: Vec<String>,
        date: &str,
        title: &str,
        source_card_id: Option<String>,
        source_item_id: Option<String>,
    ) -> Result<DateLink> {
        if !valid_date(date) {
            return Err(anyhow::anyhow!("date must be YYYY-MM-DD"));
        }
        if calendar_ids.is_empty() {
            return Err(anyhow::anyhow!("at least one calendar is required"));
        }
        for id in &calendar_ids {
            if !self.ws.calendars.iter().any(|c| &c.id == id) {
                return Err(anyhow::anyhow!("calendar not found: {id}"));
            }
        }
        if let Some(card_id) = source_card_id.as_deref() {
            let (_, card) = self
                .ws
                .card(card_id)
                .ok_or_else(|| anyhow::anyhow!("card not found"))?;
            if let Some(item_id) = source_item_id.as_deref() {
                if find_item(card, item_id).is_none() {
                    return Err(anyhow::anyhow!("item not found"));
                }
            }
        }
        self.checkpoint();
        let mut link = DateLink::new(date, calendar_ids, title);
        link.source_card_id = source_card_id;
        link.source_item_id = source_item_id;
        self.ws.date_links.push(link.clone());
        self.save_quiet();
        Ok(link)
    }

    pub fn update_date_link(
        &mut self,
        id: &str,
        calendar_ids: Option<Vec<String>>,
        date: Option<&str>,
        title: Option<&str>,
    ) -> Result<bool> {
        if let Some(date) = date {
            if !valid_date(date) {
                return Err(anyhow::anyhow!("date must be YYYY-MM-DD"));
            }
        }
        if let Some(ids) = calendar_ids.as_ref() {
            if ids.is_empty() {
                return Err(anyhow::anyhow!("at least one calendar is required"));
            }
            for id in ids {
                if !self.ws.calendars.iter().any(|c| &c.id == id) {
                    return Err(anyhow::anyhow!("calendar not found: {id}"));
                }
            }
        }
        if !self.ws.date_links.iter().any(|l| l.id == id) {
            return Ok(false);
        }
        self.checkpoint();
        let Some(link) = self.ws.date_links.iter_mut().find(|l| l.id == id) else {
            return Ok(false);
        };
        if let Some(ids) = calendar_ids {
            link.calendar_ids = ids;
        }
        if let Some(date) = date {
            link.date = date.to_string();
        }
        if let Some(title) = title {
            link.title = title.to_string();
        }
        self.save_quiet();
        Ok(true)
    }

    pub fn delete_date_link(&mut self, id: &str) -> bool {
        if !self.ws.date_links.iter().any(|link| link.id == id) {
            return false;
        }
        self.checkpoint();
        self.ws.date_links.retain(|link| link.id != id);
        self.save_quiet();
        true
    }

    pub fn set_calendar_month(&mut self, card_id: &str, year: i64, month: i64) -> bool {
        if !(1970..=3000).contains(&year) || !(0..=11).contains(&month) {
            return false;
        }
        self.update_card_json(
            &json!({"id": card_id, "payload": {"viewYear": year, "viewMonth": month}}).to_string(),
        )
    }

    pub fn calendar_today(&mut self, card_id: &str) -> bool {
        let now =
            time::OffsetDateTime::now_local().unwrap_or_else(|_| time::OffsetDateTime::now_utc());
        self.set_calendar_month(card_id, now.year() as i64, now.month() as i64 - 1)
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
        tracing::info!("launcher command: {id}");
        match id {
            "create-note" => self.spawn("note").map(card_json).unwrap_or(Value::Null),
            "create-website" => self.spawn("website").map(card_json).unwrap_or(Value::Null),
            "create-bookmark" => self.spawn("bookmark").map(card_json).unwrap_or(Value::Null),
            "create-api" => self.spawn("api").map(card_json).unwrap_or(Value::Null),
            "create-ai" => self.spawn("ai").map(card_json).unwrap_or(Value::Null),
            "create-script" => self.spawn("script").map(card_json).unwrap_or(Value::Null),
            "create-calendar" => self.spawn("calendar").map(card_json).unwrap_or(Value::Null),
            "create-timbre" => self.spawn("timbre").map(card_json).unwrap_or(Value::Null),
            "create-checklist" => self
                .spawn("checklist")
                .map(card_json)
                .unwrap_or(Value::Null),
            "create-kanban" => self.spawn("kanban").map(card_json).unwrap_or(Value::Null),
            "create-whiteboard" => self
                .spawn("whiteboard")
                .map(card_json)
                .unwrap_or(Value::Null),
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
        s.launcher_tutorial_completed = false;
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
        "calendar" => {
            card.set("calendarIds", json!([]));
        }
        "timbre" => {
            card.set("volume", json!(0.35));
            card.set("toneFreq", json!(220.0));
            card.set("toneMix", json!(0.4));
        }
        "portal" => {
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

#[allow(dead_code)]
fn find_item(card: &Card, item_id: &str) -> Option<(String, bool)> {
    if let Some(items) = card.payload.get("items").and_then(|v| v.as_array()) {
        for item in items {
            if item.get("id").and_then(|v| v.as_str()) == Some(item_id) {
                let text = item
                    .get("text")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let done = item.get("done").and_then(|v| v.as_bool()).unwrap_or(false);
                return Some((text, done));
            }
        }
    }
    if let Some(columns) = card.payload.get("columns").and_then(|v| v.as_array()) {
        for column in columns {
            let column_done = column.get("id").and_then(|v| v.as_str()) == Some("done");
            if let Some(items) = column.get("items").and_then(|v| v.as_array()) {
                for item in items {
                    if item.get("id").and_then(|v| v.as_str()) == Some(item_id) {
                        let text = item
                            .get("text")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();
                        return Some((text, column_done));
                    }
                }
            }
        }
    }
    None
}

pub fn valid_date(value: &str) -> bool {
    let parts: Vec<&str> = value.split('-').collect();
    if parts.len() != 3 || parts[0].len() != 4 || parts[1].len() != 2 || parts[2].len() != 2 {
        return false;
    }
    let (Ok(year), Ok(month), Ok(day)) = (
        parts[0].parse::<i32>(),
        parts[1].parse::<u8>(),
        parts[2].parse::<u8>(),
    ) else {
        return false;
    };
    let Ok(month) = time::Month::try_from(month) else {
        return false;
    };
    time::Date::from_calendar_date(year, month, day).is_ok()
}
