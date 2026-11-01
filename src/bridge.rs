use core::pin::Pin;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use base64::Engine;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;

use crate::ai::{self, AIRequest};
use crate::core::Core;
use crate::integrations;
use crate::model;
use crate::sync;
use crate::updates;

fn runtime() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .worker_threads(4)
            .build()
            .expect("tokio runtime")
    })
}

fn s(v: impl Into<String>) -> QString {
    QString::from(v.into())
}

fn p(v: &QString) -> String {
    v.to_string()
}

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, grids_json, cxx_name = "gridsJson")]
        #[qproperty(QString, cards_json, cxx_name = "cardsJson")]
        #[qproperty(QString, folders_json, cxx_name = "foldersJson")]
        #[qproperty(QString, settings_json, cxx_name = "settingsJson")]
        #[qproperty(QString, active_grid_id, cxx_name = "activeGridId")]
        #[qproperty(f64, pan_x, cxx_name = "panX")]
        #[qproperty(f64, pan_y, cxx_name = "panY")]
        #[qproperty(f64, zoom, cxx_name = "zoom")]
        #[qproperty(QString, status_text, cxx_name = "statusText")]
        #[qproperty(bool, syncing, cxx_name = "syncing")]
        #[qproperty(bool, ai_busy, cxx_name = "aiBusy")]
        #[qproperty(QString, update_json, cxx_name = "updateJson")]
        #[qproperty(QString, git_json, cxx_name = "gitJson")]
        #[qproperty(QString, search_json, cxx_name = "searchJson")]
        #[qproperty(QString, themes_json, cxx_name = "themesJson")]
        #[qproperty(QString, fonts_json, cxx_name = "fontsJson")]
        #[qproperty(QString, models_json, cxx_name = "modelsJson")]
        #[qproperty(QString, version, cxx_name = "version")]
        type AppController = super::AppControllerRust;

        #[qsignal]
        #[cxx_name = "toast"]
        fn toast(self: Pin<&mut Self>, message: QString);

        #[qsignal]
        #[cxx_name = "aiChunk"]
        fn ai_chunk(self: Pin<&mut Self>, id: QString, chunk: QString);

        #[qsignal]
        #[cxx_name = "aiDone"]
        fn ai_done(self: Pin<&mut Self>, id: QString, full: QString);

        #[qsignal]
        #[cxx_name = "aiError"]
        fn ai_error(self: Pin<&mut Self>, id: QString, message: QString);

        #[qsignal]
        #[cxx_name = "notice"]
        fn notice(self: Pin<&mut Self>, kind: QString, message: QString);

        #[qinvokable]
        fn boot(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "handleDeepLink"]
        fn handle_deep_link(self: Pin<&mut Self>, url: &QString);

        #[qinvokable]
        #[cxx_name = "refresh"]
        fn refresh(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "saveNow"]
        fn save_now(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "createCard"]
        fn create_card(self: Pin<&mut Self>, kind: &QString, x: f64, y: f64) -> QString;

        #[qinvokable]
        #[cxx_name = "updateCard"]
        fn update_card(self: Pin<&mut Self>, json: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "deleteCard"]
        fn delete_card(self: Pin<&mut Self>, id: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "duplicateCard"]
        fn duplicate_card(self: Pin<&mut Self>, id: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "sendCardToGrid"]
        fn send_card_to_grid(self: Pin<&mut Self>, card_id: &QString, grid_id: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "createGrid"]
        fn create_grid(self: Pin<&mut Self>, name: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "renameGrid"]
        fn rename_grid(self: Pin<&mut Self>, id: &QString, name: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "deleteGrid"]
        fn delete_grid(self: Pin<&mut Self>, id: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "switchGrid"]
        fn switch_grid(self: Pin<&mut Self>, id: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "createFolder"]
        fn create_folder(self: Pin<&mut Self>, name: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "renameFolder"]
        fn rename_folder(self: Pin<&mut Self>, id: &QString, name: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "deleteFolder"]
        fn delete_folder(self: Pin<&mut Self>, id: &QString, keep_content: bool) -> bool;

        #[qinvokable]
        #[cxx_name = "toggleFolder"]
        fn toggle_folder(self: Pin<&mut Self>, id: &QString);

        #[qinvokable]
        #[cxx_name = "moveGridToFolder"]
        fn move_grid_to_folder(
            self: Pin<&mut Self>,
            grid_id: &QString,
            folder_id: &QString,
        ) -> bool;

        #[qinvokable]
        #[cxx_name = "reorderGrid"]
        fn reorder_grid(self: Pin<&mut Self>, id: &QString, before: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "setSetting"]
        fn set_setting(self: Pin<&mut Self>, key: &QString, value_json: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "setView"]
        fn set_view(self: Pin<&mut Self>, pan_x: f64, pan_y: f64, zoom: f64);

        #[qinvokable]
        fn undo(self: Pin<&mut Self>) -> bool;

        #[qinvokable]
        fn redo(self: Pin<&mut Self>) -> bool;

        #[qinvokable]
        #[cxx_name = "search"]
        fn search_now(self: &Self, query: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "command"]
        fn command(self: Pin<&mut Self>, id: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "runScript"]
        fn run_script(self: &Self, script: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "mprisPlayers"]
        fn mpris_players(self: &Self) -> QString;

        #[qinvokable]
        #[cxx_name = "mprisAction"]
        fn mpris_action(self: &Self, player: &QString, action: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "aiSend"]
        fn ai_send(
            self: Pin<&mut Self>,
            provider: &QString,
            model_name: &QString,
            prompt: &QString,
            context: &QString,
        ) -> QString;

        #[qinvokable]
        #[cxx_name = "aiValidate"]
        fn ai_validate(self: &Self, provider: &QString, key: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "aiFetchModels"]
        fn ai_fetch_models(self: &Self, server_url: &QString, key: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "syncNow"]
        fn sync_now(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "gitSyncNow"]
        fn git_sync_now(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "gdriveConnect"]
        fn gdrive_connect(self: Pin<&mut Self>) -> QString;

        #[qinvokable]
        #[cxx_name = "gdriveDisconnect"]
        fn gdrive_disconnect(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "exportBackup"]
        fn export_backup(self: Pin<&mut Self>, path: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "importBackup"]
        fn import_backup(self: Pin<&mut Self>, path: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "importLegacy"]
        fn import_legacy(self: Pin<&mut Self>, path: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "setDataDir"]
        fn set_data_dir(self: Pin<&mut Self>, path: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "checkUpdates"]
        fn check_updates(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "downloadUpdate"]
        fn download_update(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "installUpdate"]
        fn install_update(self: &Self) -> bool;

        #[qinvokable]
        #[cxx_name = "readAttachment"]
        fn read_attachment(self: &Self, name: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "writeAttachment"]
        fn write_attachment(self: &Self, name: &QString, base64_data: &QString) -> QString;

        #[qinvokable]
        #[cxx_name = "listAttachments"]
        fn list_attachments(self: &Self) -> QString;

        #[qinvokable]
        #[cxx_name = "openExternal"]
        fn open_external(self: &Self, url: &QString);

        #[qinvokable]
        #[cxx_name = "setLaunchAtStartup"]
        fn set_launch_at_startup(self: Pin<&mut Self>, enabled: bool) -> bool;

        #[qinvokable]
        #[cxx_name = "resetTutorials"]
        fn reset_tutorials(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "spectrumStart"]
        fn spectrum_start(self: &Self, volume: f64, tone_freq: f64, tone_mix: f64);

        #[qinvokable]
        #[cxx_name = "spectrumStop"]
        fn spectrum_stop(self: &Self);

        #[qinvokable]
        #[cxx_name = "adblockCheck"]
        fn adblock_check(self: &Self, url: &QString) -> bool;

        #[qinvokable]
        #[cxx_name = "adblockHosts"]
        fn adblock_hosts(self: &Self) -> QString;

        #[qinvokable]
        #[cxx_name = "changelog"]
        fn changelog(self: &Self) -> QString;

        #[qinvokable]
        fn quit(self: &Self);
    }

    impl cxx_qt::Threading for AppController {}
}

pub struct AppControllerRust {
    core: Arc<Mutex<Core>>,
    grids_json: QString,
    cards_json: QString,
    folders_json: QString,
    settings_json: QString,
    active_grid_id: QString,
    pan_x: f64,
    pan_y: f64,
    zoom: f64,
    status_text: QString,
    syncing: bool,
    ai_busy: bool,
    update_json: QString,
    git_json: QString,
    search_json: QString,
    themes_json: QString,
    fonts_json: QString,
    models_json: QString,
    version: QString,
}

impl Default for AppControllerRust {
    fn default() -> Self {
        let core = Core::boot().unwrap_or_else(|e| {
            tracing::error!("boot failed: {e}");
            Core::fallback()
        });
        let mut this = Self {
            core: Arc::new(Mutex::new(core)),
            grids_json: QString::default(),
            cards_json: QString::default(),
            folders_json: QString::default(),
            settings_json: QString::default(),
            active_grid_id: QString::default(),
            pan_x: 0.0,
            pan_y: 0.0,
            zoom: 1.0,
            status_text: QString::default(),
            syncing: false,
            ai_busy: false,
            update_json: QString::default(),
            git_json: QString::from("{}"),
            search_json: QString::from("[]"),
            themes_json: model::themes().to_string().into(),
            fonts_json: model::fonts().to_string().into(),
            models_json: model::models_by_provider().to_string().into(),
            version: QString::from(env!("CARGO_PKG_VERSION")),
        };
        this.settings_json = QString::from("{}");
        this
    }
}

impl qobject::AppController {
    fn refresh_all(mut self: Pin<&mut Self>) {
        let (grids, cards, folders, settings, active, pan, pany, zoom, upd, git) = {
            let core_arc = self.as_ref().rust().core.clone();
            let core = core_arc.lock().unwrap();
            (
                core.grids_json(),
                core.cards_json(),
                core.folders_json(),
                core.settings_json(),
                core.active_grid_id(),
                core.active_grid_view().0,
                core.active_grid_view().1,
                core.active_grid_view().2,
                serde_json::to_string(&core.update).unwrap_or_else(|_| "{}".into()),
                core.git.status_json(),
            )
        };
        self.as_mut().set_grids_json(s(grids));
        self.as_mut().set_cards_json(s(cards));
        self.as_mut().set_folders_json(s(folders));
        self.as_mut().set_settings_json(s(settings));
        self.as_mut().set_active_grid_id(s(active));
        self.as_mut().set_pan_x(pan);
        self.as_mut().set_pan_y(pany);
        self.as_mut().set_zoom(zoom);
        self.as_mut().set_update_json(s(upd));
        self.as_mut().set_git_json(s(git));
    }

    pub fn boot(mut self: Pin<&mut Self>) {
        crate::deeplink::register(self.as_ref().qt_thread());
        self.as_mut().refresh_all();
        self.as_mut().set_status_text(s("Ready"));
    }

    pub fn handle_deep_link(mut self: Pin<&mut Self>, url: &QString) {
        let raw = p(url);
        let target = raw.strip_prefix("corcho://").unwrap_or(&raw);
        let target = target.trim_end_matches('/');
        let mut parts = target.splitn(2, '/');
        let first = parts.next().unwrap_or("");
        let second = parts.next();
        let core_arc = self.as_ref().rust().core.clone();
        {
            let mut core = core_arc.lock().unwrap();
            match (first, second) {
                ("card", Some(id)) => {
                    if let Some((grid, _)) = core.ws.card(id) {
                        let grid_id = grid.id.clone();
                        core.switch_grid(&grid_id);
                    }
                }
                ("grid", Some(id)) => {
                    core.switch_grid(id);
                }
                _ if !first.is_empty() => {
                    core.switch_grid(first);
                }
                _ => {}
            }
        }
        self.as_mut().refresh_all();
        self.as_mut().toast(s(format!("Opened {raw}")));
    }

    pub fn refresh(mut self: Pin<&mut Self>) {
        self.as_mut().refresh_all();
    }

    fn refresh_cards(mut self: Pin<&mut Self>) {
        let cards = {
            let core_arc = self.as_ref().rust().core.clone();
            let core = core_arc.lock().unwrap();
            core.cards_json()
        };
        self.as_mut().set_cards_json(s(cards));
    }

    pub fn save_now(self: Pin<&mut Self>) {
        let core_arc = self.as_ref().rust().core.clone();
        let mut core = core_arc.lock().unwrap();
        core.save_quiet();
    }

    pub fn create_card(mut self: Pin<&mut Self>, kind: &QString, x: f64, y: f64) -> QString {
        let card = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.create_card(&p(kind), x, y)
        };
        self.as_mut().refresh_all();
        card.map(|c| s(serde_json::to_string(&c).unwrap_or_default()))
            .unwrap_or_default()
    }

    pub fn update_card(mut self: Pin<&mut Self>, json: &QString) -> bool {
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.update_card_json(&p(json))
        };
        self.as_mut().refresh_cards();
        ok
    }

    pub fn delete_card(mut self: Pin<&mut Self>, id: &QString) -> bool {
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.delete_card(&p(id))
        };
        self.as_mut().refresh_all();
        ok
    }

    pub fn duplicate_card(mut self: Pin<&mut Self>, id: &QString) -> QString {
        let card = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.duplicate_card(&p(id))
        };
        self.as_mut().refresh_all();
        card.map(|c| s(serde_json::to_string(&c).unwrap_or_default()))
            .unwrap_or_default()
    }

    pub fn send_card_to_grid(
        mut self: Pin<&mut Self>,
        card_id: &QString,
        grid_id: &QString,
    ) -> bool {
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.send_card_to_grid(&p(card_id), &p(grid_id))
        };
        self.as_mut().refresh_all();
        ok
    }

    pub fn create_grid(mut self: Pin<&mut Self>, name: &QString) -> QString {
        let g = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.create_grid(&p(name))
        };
        self.as_mut().refresh_all();
        s(serde_json::to_string(&g).unwrap_or_default())
    }

    pub fn rename_grid(mut self: Pin<&mut Self>, id: &QString, name: &QString) -> bool {
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.rename_grid(&p(id), &p(name))
        };
        self.as_mut().refresh_all();
        ok
    }

    pub fn delete_grid(mut self: Pin<&mut Self>, id: &QString) -> bool {
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.delete_grid(&p(id))
        };
        self.as_mut().refresh_all();
        ok
    }

    pub fn switch_grid(mut self: Pin<&mut Self>, id: &QString) -> bool {
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.switch_grid(&p(id))
        };
        self.as_mut().refresh_all();
        ok
    }

    pub fn create_folder(mut self: Pin<&mut Self>, name: &QString) -> QString {
        let f = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.create_folder(&p(name))
        };
        self.as_mut().refresh_all();
        s(serde_json::to_string(&f).unwrap_or_default())
    }

    pub fn rename_folder(mut self: Pin<&mut Self>, id: &QString, name: &QString) -> bool {
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.rename_folder(&p(id), &p(name))
        };
        self.as_mut().refresh_all();
        ok
    }

    pub fn delete_folder(mut self: Pin<&mut Self>, id: &QString, keep_content: bool) -> bool {
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.delete_folder(&p(id), keep_content)
        };
        self.as_mut().refresh_all();
        ok
    }

    pub fn toggle_folder(mut self: Pin<&mut Self>, id: &QString) {
        {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.toggle_folder(&p(id));
        }
        self.as_mut().refresh_all();
    }

    pub fn move_grid_to_folder(
        mut self: Pin<&mut Self>,
        grid_id: &QString,
        folder_id: &QString,
    ) -> bool {
        let fid = p(folder_id);
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.move_grid_to_folder(
                &p(grid_id),
                if fid.is_empty() {
                    None
                } else {
                    Some(fid.as_str())
                },
            )
        };
        self.as_mut().refresh_all();
        ok
    }

    pub fn reorder_grid(mut self: Pin<&mut Self>, id: &QString, before: &QString) -> bool {
        let b = p(before);
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.reorder_grid(&p(id), if b.is_empty() { None } else { Some(b.as_str()) })
        };
        self.as_mut().refresh_all();
        ok
    }

    pub fn set_setting(mut self: Pin<&mut Self>, key: &QString, value_json: &QString) -> bool {
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.set_setting_json(&p(key), &p(value_json))
        };
        self.as_mut().refresh_all();
        ok
    }

    pub fn set_view(self: Pin<&mut Self>, pan_x: f64, pan_y: f64, zoom: f64) {
        self.as_ref()
            .rust()
            .core
            .clone()
            .lock()
            .unwrap()
            .set_view(pan_x, pan_y, zoom);
    }

    pub fn undo(mut self: Pin<&mut Self>) -> bool {
        let ok = self.as_ref().rust().core.clone().lock().unwrap().undo();
        self.as_mut().refresh_all();
        ok
    }

    pub fn redo(mut self: Pin<&mut Self>) -> bool {
        let ok = self.as_ref().rust().core.clone().lock().unwrap().redo();
        self.as_mut().refresh_all();
        ok
    }

    pub fn search_now(&self, query: &QString) -> QString {
        let core = self.core.lock().unwrap();
        s(core.search_json(&p(query)))
    }

    pub fn command(mut self: Pin<&mut Self>, id: &QString) -> QString {
        let v = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.command(&p(id))
        };
        self.as_mut().refresh_all();
        s(v.to_string())
    }

    pub fn run_script(&self, script: &QString) -> QString {
        match integrations::run_script(&p(script), Duration::from_secs(30)) {
            Ok(v) => s(v.to_string()),
            Err(e) => s(serde_json::json!({"ok": false, "error": e.to_string()}).to_string()),
        }
    }

    pub fn mpris_players(&self) -> QString {
        s(integrations::mpris_players().to_string())
    }

    pub fn mpris_action(&self, player: &QString, action: &QString) -> QString {
        s(integrations::mpris_action(&p(player), &p(action)).to_string())
    }

    pub fn ai_send(
        mut self: Pin<&mut Self>,
        provider: &QString,
        model_name: &QString,
        prompt: &QString,
        context: &QString,
    ) -> QString {
        let (api_key, server_url, web, stream) = {
            let core_arc = self.as_ref().rust().core.clone();
            let core = core_arc.lock().unwrap();
            let prov = p(provider);
            (
                core.ws
                    .settings
                    .ai_api_keys
                    .get(&prov)
                    .cloned()
                    .unwrap_or_default(),
                core.ws.settings.ai_local_server_url.clone(),
                core.ws.settings.ai_web_search,
                core.ws.settings.ai_stream,
            )
        };
        let id = uuid::Uuid::new_v4().to_string();
        let ctx = p(context);
        let prompt = if ctx.trim().is_empty() {
            p(prompt)
        } else {
            format!("{}\n\nContext:\n{}", p(prompt), ctx)
        };
        let req = AIRequest {
            provider: p(provider),
            model: if p(model_name).is_empty() {
                ai::default_model(&p(provider)).to_string()
            } else {
                p(model_name)
            },
            api_key,
            prompt,
            system_prompt: ai::system_prompt(),
            web_search: web,
            server_url,
        };
        let qt = self.as_mut().qt_thread();
        self.as_mut().set_ai_busy(true);
        let id_for_stream = id.clone();
        let id_for_done = id.clone();
        let qt_stream = qt.clone();
        runtime().spawn(async move {
            let cb = move |chunk: &str| {
                let text = chunk.to_string();
                let id = id_for_stream.clone();
                let _ = qt_stream.queue(move |mut q| {
                    q.as_mut().ai_chunk(s(id.clone()), s(text.clone()));
                });
            };
            let _ = stream;
            match ai::complete(req, cb).await {
                Ok(full) => {
                    let id = id_for_done;
                    let _ = qt.queue(move |mut q| {
                        q.as_mut().ai_done(s(id), s(full));
                        q.as_mut().set_ai_busy(false);
                    });
                }
                Err(e) => {
                    let id = id_for_done;
                    let msg = e.to_string();
                    let _ = qt.queue(move |mut q| {
                        q.as_mut().ai_error(s(id), s(msg));
                        q.as_mut().set_ai_busy(false);
                    });
                }
            }
        });
        s(id)
    }

    pub fn ai_validate(&self, provider: &QString, key: &QString) -> QString {
        let prov = p(provider);
        let key = p(key);
        let server = self
            .core
            .lock()
            .unwrap()
            .ws
            .settings
            .ai_local_server_url
            .clone();
        let (tx, rx) = std::sync::mpsc::channel();
        runtime().spawn(async move {
            let res = ai::validate_key(&prov, &key, &server).await;
            let _ = tx.send(res.is_ok());
        });
        let ok = rx.recv_timeout(Duration::from_secs(20)).unwrap_or(false);
        s(serde_json::json!({"success": ok}).to_string())
    }

    pub fn ai_fetch_models(&self, server_url: &QString, key: &QString) -> QString {
        let url = p(server_url);
        let key = p(key);
        let (tx, rx) = std::sync::mpsc::channel();
        runtime().spawn(async move {
            let res = ai::fetch_models(&url, &key).await;
            let _ = tx.send(res);
        });
        match rx.recv_timeout(Duration::from_secs(20)) {
            Ok(Ok(models)) => s(serde_json::json!({"success": true, "models": models}).to_string()),
            Ok(Err(e)) => {
                s(serde_json::json!({"success": false, "error": e.to_string()}).to_string())
            }
            Err(_) => s(serde_json::json!({"success": false, "error": "timeout"}).to_string()),
        }
    }

    pub fn sync_now(mut self: Pin<&mut Self>) {
        let (provider, folder, refresh, client_id, secret, data_dir, local_json) = {
            let core_arc = self.as_ref().rust().core.clone();
            let core = core_arc.lock().unwrap();
            (
                core.ws.settings.cloud_provider.clone(),
                core.ws.settings.cloud_folder.clone(),
                core.ws.settings.gdrive_refresh_token.clone(),
                core.ws.settings.gdrive_client_id.clone(),
                core.ws.settings.gdrive_client_secret.clone(),
                core.data_dir.clone(),
                core.ws.clone(),
            )
        };
        if !local_json.settings.cloud_sync_enabled {
            self.as_mut().toast(s("Cloud Sync is off"));
            return;
        }
        let qt = self.as_mut().qt_thread();
        self.as_mut().set_syncing(true);
        runtime().spawn(async move {
            let result = async {
                if provider == "gdrive" {
                    let Some(refresh) = refresh else {
                        return Err(anyhow::anyhow!("Google Drive is not connected"));
                    };
                    let Some(client_id) = client_id else {
                        return Err(anyhow::anyhow!("Google Drive client id missing"));
                    };
                    let token =
                        sync::refresh_token(&client_id, secret.as_deref(), &refresh).await?;
                    let remote = sync::drive_read(&token).await?;
                    let local = std::fs::read(data_dir.join("workspace.json")).unwrap_or_default();
                    if let Some(remote) = remote {
                        if remote != local {
                            let _ = std::fs::create_dir_all(data_dir.join("backups"));
                            let name = format!(
                                "conflict-{}.json",
                                time::OffsetDateTime::now_utc().unix_timestamp()
                            );
                            let _ = std::fs::write(data_dir.join("backups").join(name), &remote);
                            let ws: crate::model::Workspace = serde_json::from_slice(&remote)?;
                            std::fs::write(data_dir.join("workspace.json"), &remote)?;
                            return Ok::<_, anyhow::Error>((Some(ws), "pulled".to_string()));
                        }
                    } else {
                        sync::drive_write(&token, &local).await?;
                        return Ok((None, "pushed".to_string()));
                    }
                    Ok((None, "up-to-date".to_string()))
                } else if let Some(folder) = folder {
                    let (status, ws) = sync::sync_folder(&data_dir, std::path::Path::new(&folder))?;
                    Ok((ws, status))
                } else {
                    Err(anyhow::anyhow!("No sync folder selected"))
                }
            }
            .await;
            match result {
                Ok((ws, status)) => {
                    let _ = qt.queue(move |mut q| {
                        if let Some(ws) = ws {
                            if let Ok(mut core) = q.as_ref().rust().core.clone().lock() {
                                core.ws = ws;
                                let ws_snapshot = core.ws.clone();
                                core.history.reset(&ws_snapshot);
                            }
                        }
                        q.as_mut().set_syncing(false);
                        q.as_mut().refresh_all();
                        q.as_mut().notice(s("sync"), s(status));
                    });
                }
                Err(e) => {
                    let msg = e.to_string();
                    let _ = qt.queue(move |mut q| {
                        q.as_mut().set_syncing(false);
                        q.as_mut().notice(s("sync-error"), s(msg));
                    });
                }
            }
        });
    }

    pub fn git_sync_now(mut self: Pin<&mut Self>) {
        let (git, dir, config) = {
            let core_arc = self.as_ref().rust().core.clone();
            let core = core_arc.lock().unwrap();
            (core.git.clone(), core.data_dir.clone(), core.git_config())
        };
        let qt = self.as_mut().qt_thread();
        std::thread::spawn(move || {
            let result = git.sync_now(&dir, &config);
            let _ = qt.queue(move |mut q| match result {
                Ok(status) => {
                    let core_arc = q.as_ref().rust().core.clone();
                    if let Ok(mut core) = core_arc.lock() {
                        let _ = core.reload_from_disk();
                    }
                    q.as_mut().refresh_all();
                    q.as_mut().notice(s("git"), s(status));
                }
                Err(err) => {
                    q.as_mut().notice(s("git-error"), s(err.to_string()));
                }
            });
        });
    }

    pub fn gdrive_connect(mut self: Pin<&mut Self>) -> QString {
        let (client_id, secret) = {
            let core_arc = self.as_ref().rust().core.clone();
            let core = core_arc.lock().unwrap();
            (
                core.ws.settings.gdrive_client_id.clone(),
                core.ws.settings.gdrive_client_secret.clone(),
            )
        };
        let Some(client_id) = client_id else {
            self.as_mut()
                .toast(s("Add a Google OAuth client id in Settings first"));
            return s("{\"success\":false}");
        };
        let (verifier, challenge) = sync::pkce_pair();
        let redirect = "http://127.0.0.1:47823/";
        let url = sync::auth_url(&client_id, redirect, &challenge);
        let _ = open::that(&url);
        let qt = self.as_mut().qt_thread();
        let data_dir = self
            .as_ref()
            .rust()
            .core
            .clone()
            .lock()
            .unwrap()
            .data_dir
            .clone();
        runtime().spawn(async move {
            let code = wait_for_oauth_code(47823).await;
            let result = async {
                let code = code?;
                let tokens =
                    sync::exchange_code(&client_id, secret.as_deref(), &code, &verifier, redirect)
                        .await?;
                let refresh = tokens
                    .get("refresh_token")
                    .and_then(|v| v.as_str())
                    .map(str::to_string)
                    .ok_or_else(|| anyhow::anyhow!("no refresh token returned"))?;
                let access = tokens
                    .get("access_token")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                let email = sync::user_email(access).await;
                Ok::<_, anyhow::Error>((refresh, email))
            }
            .await;
            match result {
                Ok((refresh, email)) => {
                    let _ = qt.queue(move |mut q| {
                        if let Ok(mut core) = q.as_ref().rust().core.clone().lock() {
                            core.ws.settings.gdrive_connected = true;
                            core.ws.settings.gdrive_refresh_token = Some(refresh.clone());
                            core.ws.settings.gdrive_email = email.clone();
                            core.ws.settings.cloud_provider = "gdrive".into();
                            core.ws.settings.cloud_sync_enabled = true;
                            core.save_quiet();
                        }
                        q.as_mut().refresh_all();
                        q.as_mut().notice(s("gdrive"), s("Google Drive connected"));
                    });
                }
                Err(e) => {
                    let _ = data_dir;
                    let msg = e.to_string();
                    let _ = qt.queue(move |mut q| q.as_mut().notice(s("gdrive-error"), s(msg)));
                }
            }
        });
        s("{\"success\":true,\"pending\":true}")
    }

    pub fn gdrive_disconnect(mut self: Pin<&mut Self>) {
        {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.ws.settings.gdrive_connected = false;
            core.ws.settings.gdrive_refresh_token = None;
            core.ws.settings.gdrive_email = None;
            core.ws.settings.cloud_provider = "none".into();
            core.save_quiet();
        }
        self.as_mut().refresh_all();
    }

    pub fn export_backup(self: Pin<&mut Self>, path: &QString) -> bool {
        let core_arc = self.as_ref().rust().core.clone();
        let mut core = core_arc.lock().unwrap();
        core.export_backup(&p(path)).is_ok()
    }

    pub fn import_backup(mut self: Pin<&mut Self>, path: &QString) -> bool {
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.import_backup(&p(path)).is_ok()
        };
        self.as_mut().refresh_all();
        ok
    }

    pub fn import_legacy(mut self: Pin<&mut Self>, path: &QString) -> bool {
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.import_legacy(&p(path)).is_ok()
        };
        self.as_mut().refresh_all();
        ok
    }

    pub fn set_data_dir(mut self: Pin<&mut Self>, path: &QString) -> bool {
        let ok = {
            let core_arc = self.as_ref().rust().core.clone();
            let mut core = core_arc.lock().unwrap();
            core.set_data_dir(&p(path)).is_ok()
        };
        self.as_mut().refresh_all();
        ok
    }

    pub fn check_updates(mut self: Pin<&mut Self>) {
        let channel = self
            .as_ref()
            .rust()
            .core
            .lock()
            .unwrap()
            .ws
            .settings
            .update_channel
            .clone();
        let qt = self.as_mut().qt_thread();
        runtime().spawn(async move {
            match updates::check(&channel).await {
                Ok(state) => {
                    let _ = qt.queue(move |mut q| {
                        if let Ok(mut core) = q.as_ref().rust().core.clone().lock() {
                            core.update = state.clone();
                            core.save_quiet();
                        }
                        q.as_mut()
                            .set_update_json(s(serde_json::to_string(&state).unwrap_or_default()));
                    });
                }
                Err(e) => {
                    let msg = e.to_string();
                    let _ = qt.queue(move |mut q| q.as_mut().notice(s("update-error"), s(msg)));
                }
            }
        });
    }

    pub fn download_update(mut self: Pin<&mut Self>) {
        let (url, data_dir) = {
            let core_arc = self.as_ref().rust().core.clone();
            let core = core_arc.lock().unwrap();
            (core.update.url.clone(), core.data_dir.clone())
        };
        let Some(url) = url else {
            self.as_mut().toast(s("No update available"));
            return;
        };
        let qt = self.as_mut().qt_thread();
        runtime().spawn(async move {
            let dest = data_dir.join("updates").join("Corcho.AppImage");
            let qt_progress = qt.clone();
            let res = updates::download(&url, &dest, move |pct| {
                let _ = qt_progress.queue(move |mut q| {
                    let mut value: serde_json::Value =
                        serde_json::from_str(&q.update_json().to_string())
                            .unwrap_or_else(|_| serde_json::json!({}));
                    value["progress"] = serde_json::json!(pct);
                    value["status"] = serde_json::json!("downloading");
                    q.as_mut().set_update_json(s(value.to_string()));
                });
            })
            .await;
            match res {
                Ok(()) => {
                    let _ = qt.queue(move |mut q| {
                        q.as_mut().notice(
                            s("update"),
                            s(format!("Update downloaded to {}", dest.display())),
                        );
                    });
                }
                Err(e) => {
                    let msg = e.to_string();
                    let _ = qt.queue(move |mut q| q.as_mut().notice(s("update-error"), s(msg)));
                }
            }
        });
    }

    pub fn install_update(&self) -> bool {
        let dir = self.core.lock().unwrap().data_dir.clone();
        let path = dir.join("updates").join("Corcho.AppImage");
        updates::install(&path).is_ok()
    }

    pub fn read_attachment(&self, name: &QString) -> QString {
        let data_dir = self.core.lock().unwrap().data_dir.clone();
        match crate::storage::read_attachment(&data_dir, &p(name)) {
            Ok(bytes) => s(base64::engine::general_purpose::STANDARD.encode(bytes)),
            Err(_) => QString::default(),
        }
    }

    pub fn write_attachment(&self, name: &QString, base64_data: &QString) -> QString {
        let data_dir = self.core.lock().unwrap().data_dir.clone();
        let Ok(bytes) = base64::engine::general_purpose::STANDARD.decode(p(base64_data)) else {
            return QString::default();
        };
        match crate::storage::write_attachment(&data_dir, &p(name), &bytes) {
            Ok(path) => s(path.to_string_lossy().to_string()),
            Err(_) => QString::default(),
        }
    }

    pub fn list_attachments(&self) -> QString {
        let data_dir = self.core.lock().unwrap().data_dir.clone();
        s(
            serde_json::to_string(&crate::storage::list_attachments(&data_dir))
                .unwrap_or_else(|_| "[]".into()),
        )
    }

    pub fn open_external(&self, url: &QString) {
        let _ = open::that(p(url));
    }

    pub fn set_launch_at_startup(mut self: Pin<&mut Self>, enabled: bool) -> bool {
        let ok = write_autostart(enabled);
        if ok {
            if let Ok(mut core) = self.as_ref().rust().core.clone().lock() {
                core.ws.settings.launch_at_startup = enabled;
                core.save_quiet();
            }
            self.as_mut().refresh_all();
        }
        ok
    }

    pub fn reset_tutorials(mut self: Pin<&mut Self>) {
        self.as_ref()
            .rust()
            .core
            .clone()
            .lock()
            .unwrap()
            .reset_tutorials();
        self.as_mut().refresh_all();
    }

    pub fn spectrum_start(&self, volume: f64, tone_freq: f64, tone_mix: f64) {
        if let Err(e) = crate::audio::start(volume as f32, tone_freq as f32, tone_mix as f32) {
            tracing::warn!("spectrum audio: {e}");
        }
    }

    pub fn spectrum_stop(&self) {
        crate::audio::stop();
    }

    pub fn adblock_check(&self, url: &QString) -> bool {
        self.core.lock().unwrap().adblock.blocked(&p(url))
    }

    pub fn adblock_hosts(&self) -> QString {
        s(self.core.lock().unwrap().adblock.hosts_json())
    }

    pub fn changelog(&self) -> QString {
        s(CHANGELOG)
    }

    pub fn quit(&self) {
        // QML mapsto Qt.quit(); kept as an invokable for menu wiring.
    }
}

const CHANGELOG: &str = "Corcho 0.1.0\n\n- Rewritten as a native Rust + Qt6 application.\n- Infinite grid canvas with thirteen card types.\n- Eight fragment modes, including Spectrum audio.\n- Five AI providers plus a local server.\n- Folder and Google Drive sync, encrypted backups.\n- Stable, beta and experimental update channels.";

fn write_autostart(enabled: bool) -> bool {
    let Some(home) = std::env::var_os("HOME") else {
        return false;
    };
    let dir = PathBuf::from(home).join(".config/autostart");
    let path = dir.join("corcho.desktop");
    if enabled {
        if std::fs::create_dir_all(&dir).is_err() {
            return false;
        }
        let exe = std::env::current_exe()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_else(|_| "corcho".into());
        let body = format!(
            "[Desktop Entry]\nType=Application\nName=Corcho\nExec={exe}\nX-GNOME-Autostart-enabled=true\n"
        );
        std::fs::write(path, body).is_ok()
    } else {
        let _ = std::fs::remove_file(path);
        true
    }
}

async fn wait_for_oauth_code(port: u16) -> anyhow::Result<String> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", port)).await?;
    let (mut socket, _) = listener.accept().await?;
    let mut buf = [0u8; 4096];
    let n = socket.read(&mut buf).await?;
    let request = String::from_utf8_lossy(&buf[..n]).to_string();
    let code = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .and_then(|path| url::Url::parse(&format!("http://127.0.0.1{path}")).ok())
        .and_then(|url| {
            url.query_pairs()
                .find(|(k, _)| k == "code")
                .map(|(_, v)| v.to_string())
        })
        .ok_or_else(|| anyhow::anyhow!("OAuth cancelled"))?;
    let body = "<html><body style=\"font-family:sans-serif;background:#121214;color:#e8e8ea\"><h2>Corcho connected</h2><p>You can close this window.</p></body></html>";
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    let _ = socket.write_all(response.as_bytes()).await;
    Ok(code)
}
