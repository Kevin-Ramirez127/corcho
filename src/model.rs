use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

pub const SCHEMA_VERSION: u32 = 1;

pub const CARD_KINDS: &[&str] = &[
    "note",
    "website",
    "bookmark",
    "api",
    "ai",
    "script",
    "fragment",
    "gridlink",
    "checklist",
    "kanban",
    "whiteboard",
    "pomodoro",
    "mpris",
];

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Card {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    #[serde(default)]
    pub color: String,
    #[serde(default)]
    pub icon: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub locked: bool,
    #[serde(flatten, default)]
    pub payload: Map<String, Value>,
}

impl Card {
    pub fn new(kind: &str, x: f64, y: f64) -> Self {
        let (w, h, color, icon, title) = default_card_style(kind);
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            kind: kind.to_string(),
            x,
            y,
            width: w,
            height: h,
            color: color.to_string(),
            icon: icon.to_string(),
            title: title.to_string(),
            text: String::new(),
            locked: false,
            payload: Map::new(),
        }
    }

    pub fn get(&self, key: &str) -> Option<&Value> {
        self.payload.get(key)
    }

    pub fn set(&mut self, key: &str, value: Value) {
        self.payload.insert(key.to_string(), value);
    }

    pub fn str_field(&self, key: &str, fallback: &str) -> String {
        self.payload
            .get(key)
            .and_then(|v| v.as_str())
            .unwrap_or(fallback)
            .to_string()
    }

    pub fn search_text(&self) -> String {
        let mut s = format!("{} {} {}", self.title, self.text, self.kind);
        for key in ["url", "prompt", "name", "artist", "album"] {
            if let Some(v) = self.payload.get(key).and_then(|v| v.as_str()) {
                s.push(' ');
                s.push_str(v);
            }
        }
        s
    }
}

pub fn default_card_style(kind: &str) -> (f64, f64, &'static str, &'static str, &'static str) {
    match kind {
        "note" => (384.0, 320.0, "#3d3f52", "file-text", ""),
        "website" => (512.0, 384.0, "#2f3b45", "globe", "Website"),
        "bookmark" => (320.0, 128.0, "#2f3b45", "bookmark", "Bookmark"),
        "api" => (480.0, 320.0, "#2f3b45", "database", "API Data"),
        "ai" => (416.0, 288.0, "#3a3348", "cpu", "AI"),
        "script" => (416.0, 256.0, "#333a33", "terminal", "Script"),
        "fragment" => (320.0, 320.0, "#33333a", "gem", ""),
        "gridlink" => (288.0, 128.0, "#323a3d", "arrow-right-circle", "Grid Link"),
        "checklist" => (352.0, 320.0, "#353a33", "list-checks", "Checklist"),
        "kanban" => (416.0, 320.0, "#33384a", "kanban", "Kanban"),
        "whiteboard" => (416.0, 320.0, "#333333", "pencil", "Whiteboard"),
        "pomodoro" => (320.0, 256.0, "#3d3436", "timer", "Pomodoro"),
        "mpris" => (384.0, 192.0, "#333842", "music", "Now Playing"),
        _ => (320.0, 240.0, "#3d3f52", "square", ""),
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Grid {
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default, rename = "folderId")]
    pub folder_id: Option<String>,
    #[serde(default)]
    pub cards: Vec<Card>,
    #[serde(default)]
    pub pan_x: f64,
    #[serde(default)]
    pub pan_y: f64,
    #[serde(default = "default_zoom")]
    pub zoom: f64,
}

pub fn default_zoom() -> f64 {
    1.0
}

impl Default for Grid {
    fn default() -> Self {
        Self {
            id: String::new(),
            name: String::new(),
            folder_id: None,
            cards: Vec::new(),
            pan_x: 0.0,
            pan_y: 0.0,
            zoom: 1.0,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, Default)]
pub struct Folder {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub collapsed: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CustomTheme {
    pub background: String,
    pub surface: String,
    pub accent: String,
    pub text: String,
}

impl Default for CustomTheme {
    fn default() -> Self {
        Self {
            background: "#121214".into(),
            surface: "#1b1b1f".into(),
            accent: "#c9a86a".into(),
            text: "#e8e8ea".into(),
        }
    }
}

fn t() -> bool {
    true
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub theme: String,
    pub font: String,
    pub grid_opacity: f64,
    pub minimap_display: String,
    pub minimap_size: String,
    pub trackpad_pan: bool,
    pub grid_magnetic: bool,
    pub spawn_animations: bool,
    pub card_parallax: bool,
    pub grid_ripple: bool,
    pub hardware_acceleration: bool,
    pub master_volume: i32,
    pub link_behavior: String,
    pub show_card_tooltips: bool,
    pub ad_blocker: bool,
    pub undo_steps: usize,
    pub powerbar_shortcut: String,
    pub launch_at_startup: bool,
    pub show_changelog: bool,
    pub update_mode: String,
    pub update_channel: String,
    #[serde(rename = "aiProvider")]
    pub ai_provider: String,
    #[serde(rename = "aiApiKeys")]
    pub ai_api_keys: HashMap<String, String>,
    #[serde(rename = "aiModel")]
    pub ai_model: HashMap<String, String>,
    pub ai_local_server_url: String,
    pub ai_stream: bool,
    pub ai_web_search: bool,
    pub ai_refresh_interval: String,
    pub cloud_sync_enabled: bool,
    pub cloud_provider: String,
    pub cloud_folder: Option<String>,
    pub cloud_file_sync: bool,
    pub cloud_indicator: bool,
    pub gdrive_connected: bool,
    pub gdrive_client_id: Option<String>,
    pub gdrive_client_secret: Option<String>,
    pub gdrive_refresh_token: Option<String>,
    pub gdrive_email: Option<String>,
    pub onboarding_completed: bool,
    pub card_tutorial_completed: bool,
    pub context_tutorial_completed: bool,
    pub fragment_tutorial_completed: bool,
    pub powerbar_tutorial_completed: bool,
    #[serde(rename = "unlockedThemes")]
    pub unlocked_themes: Vec<String>,
    #[serde(rename = "unlockedFragments")]
    pub unlocked_fragments: Vec<String>,
    #[serde(rename = "customTheme")]
    pub custom_theme: Option<CustomTheme>,
    pub last_seen_version: Option<String>,
    pub debug_mode: bool,
    pub reduced_motion: bool,
    pub data_dir: Option<String>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            theme: "corcho".into(),
            font: "inter".into(),
            grid_opacity: 0.6,
            minimap_display: "always".into(),
            minimap_size: "medium".into(),
            trackpad_pan: t(),
            grid_magnetic: t(),
            spawn_animations: t(),
            card_parallax: t(),
            grid_ripple: t(),
            hardware_acceleration: t(),
            master_volume: 50,
            link_behavior: "integrated".into(),
            show_card_tooltips: t(),
            ad_blocker: false,
            undo_steps: 20,
            powerbar_shortcut: "CmdOrCtrl+K".into(),
            launch_at_startup: false,
            show_changelog: t(),
            update_mode: "check".into(),
            update_channel: "stable".into(),
            ai_provider: "claude".into(),
            ai_api_keys: HashMap::new(),
            ai_model: HashMap::new(),
            ai_local_server_url: String::new(),
            ai_stream: t(),
            ai_web_search: t(),
            ai_refresh_interval: "launch".into(),
            cloud_sync_enabled: false,
            cloud_provider: "none".into(),
            cloud_folder: None,
            cloud_file_sync: false,
            cloud_indicator: false,
            gdrive_connected: false,
            gdrive_client_id: None,
            gdrive_client_secret: None,
            gdrive_refresh_token: None,
            gdrive_email: None,
            onboarding_completed: false,
            card_tutorial_completed: false,
            context_tutorial_completed: false,
            fragment_tutorial_completed: false,
            powerbar_tutorial_completed: false,
            unlocked_themes: Vec::new(),
            unlocked_fragments: Vec::new(),
            custom_theme: None,
            last_seen_version: None,
            debug_mode: false,
            reduced_motion: false,
            data_dir: None,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Workspace {
    pub version: u32,
    pub grids: Vec<Grid>,
    pub folders: Vec<Folder>,
    pub settings: Settings,
    pub active_grid_id: Option<String>,
}

impl Default for Workspace {
    fn default() -> Self {
        let grid = Grid {
            id: uuid::Uuid::new_v4().to_string(),
            name: "Grid A".into(),
            ..Default::default()
        };
        Self {
            version: SCHEMA_VERSION,
            active_grid_id: Some(grid.id.clone()),
            grids: vec![grid],
            folders: Vec::new(),
            settings: Settings::default(),
        }
    }
}

impl Workspace {
    pub fn active_grid(&self) -> Option<&Grid> {
        let id = self.active_grid_id.as_ref()?;
        self.grids.iter().find(|g| &g.id == id)
    }

    pub fn active_grid_mut(&mut self) -> Option<&mut Grid> {
        let id = self.active_grid_id.clone()?;
        self.grids.iter_mut().find(|g| g.id == id)
    }

    pub fn grid(&self, id: &str) -> Option<&Grid> {
        self.grids.iter().find(|g| g.id == id)
    }

    pub fn grid_mut(&mut self, id: &str) -> Option<&mut Grid> {
        self.grids.iter_mut().find(|g| g.id == id)
    }

    pub fn card(&self, id: &str) -> Option<(&Grid, &Card)> {
        for g in &self.grids {
            if let Some(c) = g.cards.iter().find(|c| c.id == id) {
                return Some((g, c));
            }
        }
        None
    }

    pub fn card_mut(&mut self, id: &str) -> Option<&mut Card> {
        for g in &mut self.grids {
            if let Some(c) = g.cards.iter_mut().find(|c| c.id == id) {
                return Some(c);
            }
        }
        None
    }

    pub fn remove_card(&mut self, id: &str) -> Option<Card> {
        for g in &mut self.grids {
            if let Some(pos) = g.cards.iter().position(|c| c.id == id) {
                return Some(g.cards.remove(pos));
            }
        }
        None
    }

    pub fn add_grid(&mut self, name: &str) -> Grid {
        let g = Grid {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.to_string(),
            ..Default::default()
        };
        self.grids.push(g.clone());
        g
    }

    pub fn add_folder(&mut self, name: &str) -> Folder {
        let f = Folder {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.to_string(),
            collapsed: false,
        };
        self.folders.push(f.clone());
        f
    }

    pub fn total_cards(&self) -> usize {
        self.grids.iter().map(|g| g.cards.len()).sum()
    }
}

pub fn models_by_provider() -> serde_json::Value {
    serde_json::json!({
        "claude": [
            {"id":"claude-opus-4-7","name":"Claude Opus 4.7"},
            {"id":"claude-opus-4-6","name":"Claude Opus 4.6"},
            {"id":"claude-sonnet-4-6","name":"Claude Sonnet 4.6"},
            {"id":"claude-opus-4-5-20251101","name":"Claude Opus 4.5"},
            {"id":"claude-sonnet-4-5-20250929","name":"Claude Sonnet 4.5"},
            {"id":"claude-haiku-4-5-20251001","name":"Claude Haiku 4.5"}
        ],
        "openai": [
            {"id":"gpt-5.4-pro","name":"GPT-5.4 Pro"},
            {"id":"gpt-5.4","name":"GPT-5.4"},
            {"id":"gpt-5.4-mini","name":"GPT-5.4 Mini"},
            {"id":"gpt-5.4-nano","name":"GPT-5.4 Nano"},
            {"id":"gpt-5.3-chat-latest","name":"GPT-5.3"},
            {"id":"gpt-5.2","name":"GPT-5.2"},
            {"id":"gpt-5.1","name":"GPT-5.1"},
            {"id":"gpt-5","name":"GPT-5"},
            {"id":"gpt-5-mini","name":"GPT-5 Mini"},
            {"id":"gpt-4o","name":"GPT-4o"}
        ],
        "google": [
            {"id":"gemini-3-pro-preview","name":"Gemini 3 Pro"},
            {"id":"gemini-3-flash-preview","name":"Gemini 3 Flash"},
            {"id":"gemini-2.5-pro","name":"Gemini 2.5 Pro"},
            {"id":"gemini-2.5-flash","name":"Gemini 2.5 Flash"},
            {"id":"gemini-2.5-flash-lite","name":"Gemini 2.5 Flash Lite"}
        ],
        "grok": [
            {"id":"grok-4-1-fast-reasoning","name":"Grok 4.1 Fast Reasoning"},
            {"id":"grok-4-1-fast-non-reasoning","name":"Grok 4.1 Fast"},
            {"id":"grok-4-fast-reasoning","name":"Grok 4 Fast Reasoning"},
            {"id":"grok-4-fast-non-reasoning","name":"Grok 4 Fast"},
            {"id":"grok-code-fast-1","name":"Grok Code Fast"},
            {"id":"grok-4-0709","name":"Grok 4"},
            {"id":"grok-3","name":"Grok 3"},
            {"id":"grok-3-mini","name":"Grok 3 Mini"}
        ],
        "mistral": [
            {"id":"mistral-large-latest","name":"Mistral Large"},
            {"id":"mistral-small-latest","name":"Mistral Small"}
        ],
        "local": []
    })
}

pub fn themes() -> serde_json::Value {
    serde_json::json!([
        {"id":"corcho","name":"Corcho","bg":"#121417","surface":"#1b1e23","accent":"#d98e5c","text":"#ece7de","builtin":true},
        {"id":"orion","name":"Orion","bg":"#16171f","surface":"#1e1f2b","accent":"#7aa2f7","text":"#d7d9e6","builtin":true},
        {"id":"cryo","name":"Cryo","bg":"#f5f7fa","surface":"#ffffff","accent":"#3b6ea5","text":"#20242c","builtin":true,"light":true},
        {"id":"high-contrast","name":"High Contrast","bg":"#000000","surface":"#0a0a0a","accent":"#00ff00","text":"#ffffff","builtin":true},
        {"id":"aurora","name":"Aurora","bg":"#232830","surface":"#2c333d","accent":"#88c0d0","text":"#e3e8ee","builtin":true},
        {"id":"afterglow","name":"Afterglow","bg":"#1a1423","surface":"#241b31","accent":"#e08b7a","text":"#ece2e6","builtin":true},
        {"id":"stardust","name":"Stardust","bg":"#0a1628","surface":"#122238","accent":"#0891b2","text":"#dbe7f0","builtin":true},
        {"id":"helios","name":"Helios","bg":"#0a0a0a","surface":"#141414","accent":"#bfa450","text":"#ece7d8","builtin":true},
        {"id":"nova-x","name":"Graphite","bg":"#0f0f0f","surface":"#191919","accent":"#f0f0f0","text":"#ededed","builtin":true},
        {"id":"obsidian","name":"Obsidian","bg":"#0a0a0a","surface":"#121212","accent":"#a78bfa","text":"#ece9f6","builtin":true},
        {"id":"monokai","name":"Monokai","bg":"#22221d","surface":"#2b2b25","accent":"#f92672","text":"#ecebdc","builtin":true},
        {"id":"alpine","name":"Alpine","bg":"#f8fafc","surface":"#ffffff","accent":"#3b82f6","text":"#1e293b","builtin":true,"light":true},
        {"id":"fog","name":"Fog","bg":"#f1f5f9","surface":"#ffffff","accent":"#6b7280","text":"#27303b","builtin":true,"light":true},
        {"id":"blueprint","name":"Blueprint","bg":"#eff6ff","surface":"#ffffff","accent":"#1d4ed8","text":"#1e2a45","builtin":true,"light":true},
        {"id":"solarized-dark","name":"Solarized Dark","bg":"#002b36","surface":"#073642","accent":"#2aa198","text":"#d6e2e3","builtin":true},
        {"id":"gruvbox","name":"Gruvbox","bg":"#282828","surface":"#35302a","accent":"#fe8019","text":"#ebdbb2","builtin":true},
        {"id":"custom","name":"Custom","bg":"#121214","surface":"#1b1b1f","accent":"#c9a86a","text":"#e8e8ea","builtin":false},
        {"id":"pulsar","name":"Pulsar","bg":"#0a0910","surface":"#141320","accent":"#b24aff","text":"#eae4f5","builtin":false},
        {"id":"plasma","name":"Plasma","bg":"#0b0608","surface":"#180d12","accent":"#ff2d2d","text":"#f4e3e3","builtin":false}
    ])
}

pub fn fonts() -> serde_json::Value {
    serde_json::json!([
        {"id":"inter","name":"Inter","family":"Inter"},
        {"id":"dm-sans","name":"DM Sans","family":"DM Sans"},
        {"id":"manrope","name":"Manrope","family":"Manrope"},
        {"id":"plus-jakarta-sans","name":"Plus Jakarta Sans","family":"Plus Jakarta Sans"},
        {"id":"ibm-plex-sans","name":"IBM Plex Sans","family":"IBM Plex Sans"},
        {"id":"roboto","name":"Roboto","family":"Roboto"},
        {"id":"system","name":"System UI","family":""},
        {"id":"jetbrains-mono","name":"JetBrains Mono","family":"JetBrains Mono"},
        {"id":"fira-code","name":"Fira Code","family":"Fira Code"},
        {"id":"source-code-pro","name":"Source Code Pro","family":"Source Code Pro"},
        {"id":"ibm-plex-mono","name":"IBM Plex Mono","family":"IBM Plex Mono"},
        {"id":"space-mono","name":"Space Mono","family":"Space Mono"},
        {"id":"ocr-a","name":"OCR-A","family":"OCR A Std"},
        {"id":"open-dyslexic","name":"OpenDyslexic","family":"OpenDyslexic"}
    ])
}
