use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};

use crate::model::Workspace;
use crate::storage;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct GitConfig {
    pub enabled: bool,
    pub remote: String,
    pub branch: String,
    pub auto_push: bool,
    pub auto_pull: bool,
    pub include_attachments: bool,
    pub auth_gh: bool,
}

impl Default for GitConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            remote: String::new(),
            branch: "main".into(),
            auto_push: true,
            auto_pull: true,
            include_attachments: false,
            auth_gh: false,
        }
    }
}

#[derive(Default)]
struct State {
    dirty: bool,
    last_change: Option<Instant>,
    busy: bool,
    last_sync: Option<String>,
    last_error: Option<String>,
}

#[derive(Clone)]
pub struct GitSync {
    state: Arc<Mutex<State>>,
    config: Arc<Mutex<GitConfig>>,
}

impl Default for GitSync {
    fn default() -> Self {
        Self::new(GitConfig::default())
    }
}

impl GitSync {
    pub fn new(config: GitConfig) -> Self {
        Self {
            state: Arc::new(Mutex::new(State::default())),
            config: Arc::new(Mutex::new(config)),
        }
    }

    pub fn config(&self) -> GitConfig {
        self.config.lock().map(|c| c.clone()).unwrap_or_default()
    }

    pub fn configure(&self, config: GitConfig) {
        if let Ok(mut slot) = self.config.lock() {
            *slot = config;
        }
    }

    pub fn mark_dirty(&self) {
        if !self.config().enabled {
            return;
        }
        if let Ok(mut state) = self.state.lock() {
            state.dirty = true;
            state.last_change = Some(Instant::now());
        }
    }

    pub fn status_json(&self) -> String {
        let config = self.config();
        let state = self.state.lock().ok();
        serde_json::json!({
            "enabled": config.enabled,
            "remote": config.remote,
            "branch": config.branch,
            "autoPush": config.auto_push,
            "autoPull": config.auto_pull,
            "authGh": config.auth_gh,
            "dirty": state.as_ref().map(|s| s.dirty).unwrap_or(false),
            "busy": state.as_ref().map(|s| s.busy).unwrap_or(false),
            "lastSync": state.as_ref().and_then(|s| s.last_sync.clone()),
            "lastError": state.as_ref().and_then(|s| s.last_error.clone()),
        })
        .to_string()
    }

    fn set_status(&self, sync: Option<String>, error: Option<String>) {
        if let Ok(mut state) = self.state.lock() {
            if let Some(sync) = sync {
                state.last_sync = Some(sync);
                state.last_error = None;
            }
            if let Some(error) = error {
                state.last_error = Some(error);
            }
        }
    }

    pub fn start_worker(&self, data_dir: PathBuf) {
        let me = self.clone();
        std::thread::spawn(move || loop {
            std::thread::sleep(Duration::from_secs(1));
            let config = me.config();
            if !config.enabled || !config.auto_push || config.remote.is_empty() {
                continue;
            }
            let should_push = {
                let Ok(mut state) = me.state.lock() else {
                    continue;
                };
                let ready = state.dirty
                    && !state.busy
                    && state
                        .last_change
                        .map(|t| t.elapsed() >= Duration::from_secs(2))
                        .unwrap_or(false);
                if ready {
                    state.busy = true;
                    state.dirty = false;
                }
                ready
            };
            if !should_push {
                continue;
            }
            let result = me.commit_and_push(&data_dir, &config);
            if let Ok(mut state) = me.state.lock() {
                state.busy = false;
                match result {
                    Ok(status) => {
                        state.last_error = None;
                        state.last_sync = Some(status);
                    }
                    Err(err) => state.last_error = Some(err.to_string()),
                }
            }
        });
    }

    pub fn ensure_repo(&self, data_dir: &Path, config: &GitConfig) -> Result<()> {
        std::fs::create_dir_all(data_dir)?;
        if !data_dir.join(".git").exists() {
            git(data_dir, &["init", "-b", &config.branch])?;
        }
        let _ = git(data_dir, &["config", "user.name", "Corcho"]);
        let _ = git(data_dir, &["config", "user.email", "corcho@localhost"]);

        let https_remote = config.remote.starts_with("https://");
        let rewrite_key = format!("url.{}.insteadOf", config.remote);
        if config.auth_gh {
            let _ = git(data_dir, &["config", "credential.helper", ""]);
            git(
                data_dir,
                &["config", "credential.helper", "!gh auth git-credential"],
            )?;
            if https_remote {
                let _ = git(data_dir, &["config", &rewrite_key, &config.remote]);
            }
        } else {
            let _ = git(data_dir, &["config", "--unset-all", "credential.helper"]);
            if https_remote {
                let _ = git(data_dir, &["config", "--unset-all", &rewrite_key]);
            }
        }

        let ignore = if config.include_attachments {
            "updates/\nbackups/\nlogs/\nmcp.token\n*.sock\n*.tmp\n*.bak\n"
        } else {
            "updates/\nbackups/\nlogs/\nattachments/\nmcp.token\n*.sock\n*.tmp\n*.bak\n"
        };
        std::fs::write(data_dir.join(".gitignore"), ignore)?;

        if !config.remote.is_empty() {
            let has_remote = git(data_dir, &["remote", "get-url", "origin"]).is_ok();
            if has_remote {
                let _ = git(data_dir, &["remote", "set-url", "origin", &config.remote]);
            } else {
                git(data_dir, &["remote", "add", "origin", &config.remote])?;
            }
        }
        Ok(())
    }

    /// Pull at launch. Returns true when the local workspace changed.
    pub fn pull_at_start(&self, data_dir: &Path, config: &GitConfig) -> Result<bool> {
        if config.remote.is_empty() {
            return Ok(false);
        }
        self.ensure_repo(data_dir, config)?;
        match git(data_dir, &["fetch", "origin", &config.branch]) {
            Ok(_) => {}
            Err(err) => {
                if err.to_string().contains("couldn't find remote ref") {
                    return Ok(false);
                }
                return Err(err);
            }
        }

        let remote_ref = format!("origin/{}", config.branch);
        if git(data_dir, &["rev-parse", "--verify", &remote_ref]).is_err() {
            return Ok(false);
        }

        if git(data_dir, &["rev-parse", "--verify", "HEAD"]).is_err() {
            return import_into_remote(data_dir, config, &remote_ref);
        }

        if same_commit(data_dir, "HEAD", &remote_ref) {
            return Ok(false);
        }
        if is_ancestor(data_dir, "HEAD", &remote_ref) {
            git(data_dir, &["merge", "--ff-only", &remote_ref])?;
            return Ok(true);
        }
        if is_ancestor(data_dir, &remote_ref, "HEAD") {
            return Ok(false);
        }
        self.merge_and_commit(data_dir, config)?;
        Ok(true)
    }

    pub fn sync_now(&self, data_dir: &Path, config: &GitConfig) -> Result<String> {
        if !config.enabled || config.remote.is_empty() {
            return Err(anyhow!("git sync is not configured"));
        }
        self.ensure_repo(data_dir, config)?;
        self.commit_local(data_dir)?;

        if git(data_dir, &["fetch", "origin", &config.branch]).is_ok() {
            let remote_ref = format!("origin/{}", config.branch);
            if git(data_dir, &["rev-parse", "--verify", &remote_ref]).is_ok() {
                if is_ancestor(data_dir, "HEAD", &remote_ref) {
                    git(data_dir, &["merge", "--ff-only", &remote_ref])?;
                    return Ok("pulled".into());
                }
                if !is_ancestor(data_dir, &remote_ref, "HEAD") {
                    self.merge_and_commit(data_dir, config)?;
                    return Ok("merged".into());
                }
            }
        }

        git(data_dir, &["push", "origin", &config.branch])?;
        Ok("pushed".into())
    }

    fn commit_and_push(&self, data_dir: &Path, config: &GitConfig) -> Result<String> {
        self.ensure_repo(data_dir, config)?;
        self.commit_local(data_dir)?;
        self.sync_now(data_dir, config)
    }

    fn commit_local(&self, data_dir: &Path) -> Result<()> {
        git(data_dir, &["add", "-A"])?;
        if git(data_dir, &["diff", "--cached", "--quiet"]).is_ok() {
            return Ok(());
        }
        let stamp = time::OffsetDateTime::now_utc()
            .format(&time::format_description::well_known::Rfc3339)
            .unwrap_or_else(|_| "now".into());
        git(
            data_dir,
            &["commit", "-m", &format!("corcho: autosave {stamp}")],
        )?;
        Ok(())
    }

    fn merge_and_commit(&self, data_dir: &Path, config: &GitConfig) -> Result<()> {
        let remote_ref = format!("origin/{}", config.branch);
        let remote_raw = git(data_dir, &["show", &format!("{remote_ref}:workspace.json")])?;
        let remote_text = String::from_utf8_lossy(&remote_raw.stdout).to_string();
        let local_text = std::fs::read_to_string(data_dir.join("workspace.json"))?;

        let local: Workspace = serde_json::from_str(&local_text)?;
        let remote: Workspace = serde_json::from_str(&remote_text)?;

        save_conflict_copies(data_dir, &local_text, &remote_text)?;
        let merged = merge_workspaces(&local, &remote);

        // Explicit two-parent merge commit so the push is a fast-forward.
        storage::save_workspace(data_dir, &merged)?;
        git(data_dir, &["add", "-A"])?;
        let tree = stdout(git(data_dir, &["write-tree"])?);
        let p1 = stdout(git(data_dir, &["rev-parse", "HEAD"])?);
        let p2 = stdout(git(data_dir, &["rev-parse", &remote_ref])?);
        let commit = stdout(git(
            data_dir,
            &[
                "commit-tree",
                &tree,
                "-p",
                &p1,
                "-p",
                &p2,
                "-m",
                &format!("corcho: merge remote {remote_ref}"),
            ],
        )?);
        git(
            data_dir,
            &[
                "update-ref",
                &format!("refs/heads/{}", config.branch),
                &commit,
            ],
        )?;
        git(data_dir, &["push", "origin", &config.branch])?;
        self.set_status(Some("merged".into()), None);
        Ok(())
    }
}

fn import_into_remote(data_dir: &Path, config: &GitConfig, remote_ref: &str) -> Result<bool> {
    let local_path = data_dir.join("workspace.json");
    let local = std::fs::read_to_string(&local_path)
        .ok()
        .and_then(|text| serde_json::from_str::<Workspace>(&text).ok());

    git(
        data_dir,
        &["checkout", "-f", "-B", &config.branch, remote_ref],
    )?;

    if let Some(local) = local {
        let remote_text = std::fs::read_to_string(&local_path)?;
        if let Ok(remote) = serde_json::from_str::<Workspace>(&remote_text) {
            save_conflict_copies(data_dir, &serde_json::to_string(&local)?, &remote_text)?;
            let merged = merge_workspaces(&local, &remote);
            storage::save_workspace(data_dir, &merged)?;
            git(data_dir, &["add", "-A"])?;
            let stamp = time::OffsetDateTime::now_utc().unix_timestamp();
            git(
                data_dir,
                &[
                    "commit",
                    "--allow-empty",
                    "-m",
                    &format!("corcho: import local workspace {stamp}"),
                ],
            )?;
            let _ = git(data_dir, &["push", "origin", &config.branch]);
        }
    }
    Ok(true)
}

fn save_conflict_copies(data_dir: &Path, local: &str, remote: &str) -> Result<()> {
    let dir = data_dir.join("backups");
    std::fs::create_dir_all(&dir)?;
    let stamp = time::OffsetDateTime::now_utc().unix_timestamp();
    let _ = std::fs::write(dir.join(format!("git-conflict-{stamp}-local.json")), local);
    let _ = std::fs::write(
        dir.join(format!("git-conflict-{stamp}-remote.json")),
        remote,
    );
    Ok(())
}

/// Union merge: never drop a grid, folder or card. Local wins for the same id;
/// both pre-merge workspaces are kept in backups/.
pub fn merge_workspaces(local: &Workspace, remote: &Workspace) -> Workspace {
    let mut merged = local.clone();

    for remote_grid in &remote.grids {
        if let Some(local_grid) = merged.grids.iter_mut().find(|g| g.id == remote_grid.id) {
            for remote_card in &remote_grid.cards {
                if !local_grid.cards.iter().any(|c| c.id == remote_card.id) {
                    local_grid.cards.push(remote_card.clone());
                }
            }
        } else {
            merged.grids.push(remote_grid.clone());
        }
    }

    for remote_folder in &remote.folders {
        if !merged.folders.iter().any(|f| f.id == remote_folder.id) {
            merged.folders.push(remote_folder.clone());
        }
    }

    for remote_calendar in &remote.calendars {
        if !merged
            .calendars
            .iter()
            .any(|calendar| calendar.id == remote_calendar.id)
        {
            merged.calendars.push(remote_calendar.clone());
        }
    }

    for remote_link in &remote.date_links {
        if !merged
            .date_links
            .iter()
            .any(|link| link.id == remote_link.id)
        {
            merged.date_links.push(remote_link.clone());
        }
    }

    if merged
        .active_grid_id
        .as_ref()
        .map(|id| !merged.grids.iter().any(|g| &g.id == id))
        .unwrap_or(true)
    {
        merged.active_grid_id = remote.active_grid_id.clone();
    }
    if merged.grids.is_empty() {
        merged = remote.clone();
    }
    merged.migrate();
    merged
}

fn stdout(output: std::process::Output) -> String {
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

fn git(dir: &Path, args: &[&str]) -> Result<std::process::Output> {
    let output = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .env("GIT_TERMINAL_PROMPT", "0")
        .env("GIT_SSH_COMMAND", "ssh -o BatchMode=yes")
        .output()
        .map_err(|e| anyhow!("git not available: {e}"))?;
    if !output.status.success() {
        return Err(anyhow!(
            "git {}: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(output)
}

fn same_commit(dir: &Path, a: &str, b: &str) -> bool {
    match (git(dir, &["rev-parse", a]), git(dir, &["rev-parse", b])) {
        (Ok(a), Ok(b)) => a.stdout == b.stdout,
        _ => false,
    }
}

fn is_ancestor(dir: &Path, ancestor: &str, descendant: &str) -> bool {
    git(dir, &["merge-base", "--is-ancestor", ancestor, descendant]).is_ok()
}

pub fn config_from(settings: &crate::model::Settings) -> GitConfig {
    GitConfig {
        enabled: settings.git_sync_enabled,
        remote: settings.git_remote.clone(),
        branch: if settings.git_branch.trim().is_empty() {
            "main".into()
        } else {
            settings.git_branch.clone()
        },
        auto_push: settings.git_auto_push,
        auto_pull: settings.git_auto_pull,
        include_attachments: settings.git_include_attachments,
        auth_gh: settings.git_auth == "gh",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Card, Grid, Workspace};

    #[test]
    fn union_merge_keeps_both_sides() {
        let mut local = Workspace::default();
        let mut remote = Workspace::default();
        remote.grids[0].id = local.grids[0].id.clone();
        remote.active_grid_id = local.active_grid_id.clone();

        let mut local_card = Card::new("note", 0.0, 0.0);
        local_card.title = "local".into();
        local.grids[0].cards.push(local_card);

        let mut remote_card = Card::new("note", 20.0, 20.0);
        remote_card.title = "remote".into();
        remote.grids[0].cards.push(remote_card);

        let extra = Grid {
            id: "remote-grid".into(),
            name: "Remote".into(),
            ..Default::default()
        };
        remote.grids.push(extra);

        let merged = merge_workspaces(&local, &remote);
        assert_eq!(merged.grids.len(), 2);
        assert!(merged.grids[0].cards.iter().any(|c| c.title == "local"));
        assert!(merged.grids[0].cards.iter().any(|c| c.title == "remote"));
    }
}

#[cfg(test)]
mod git_tests {
    use super::*;
    use crate::model::{Card, Workspace};
    use std::path::Path;
    use std::process::Command;

    fn bare_remote(path: &Path) {
        let out = Command::new("git")
            .arg("init")
            .arg("--bare")
            .arg(path)
            .output()
            .unwrap();
        assert!(out.status.success(), "{out:?}");
    }

    fn config(remote: &Path) -> GitConfig {
        GitConfig {
            enabled: true,
            remote: remote.to_string_lossy().to_string(),
            branch: "main".into(),
            auto_push: true,
            auto_pull: true,
            include_attachments: false,
            auth_gh: false,
        }
    }

    #[test]
    fn push_then_pull_on_a_fresh_device() {
        let remote_dir = tempfile::tempdir().unwrap();
        let remote = remote_dir.path().join("remote.git");
        bare_remote(&remote);
        let cfg = config(&remote);

        let a = tempfile::tempdir().unwrap();
        let mut wa = Workspace::default();
        wa.grids[0].name = "Alpha".into();
        storage::save_workspace(a.path(), &wa).unwrap();
        let ga = GitSync::new(cfg.clone());
        ga.ensure_repo(a.path(), &cfg).unwrap();
        assert_eq!(ga.sync_now(a.path(), &cfg).unwrap(), "pushed");

        let b = tempfile::tempdir().unwrap();
        let gb = GitSync::new(cfg.clone());
        gb.ensure_repo(b.path(), &cfg).unwrap();
        assert!(gb.pull_at_start(b.path(), &cfg).unwrap());
        let pulled = storage::load_workspace(b.path()).unwrap();
        assert_eq!(pulled.grids[0].name, "Alpha");
    }

    #[test]
    fn divergent_devices_union_merge_without_losing_cards() {
        let remote_dir = tempfile::tempdir().unwrap();
        let remote = remote_dir.path().join("remote.git");
        bare_remote(&remote);
        let cfg = config(&remote);

        let a = tempfile::tempdir().unwrap();
        let mut wa = Workspace::default();
        wa.grids[0].name = "Shared".into();
        storage::save_workspace(a.path(), &wa).unwrap();
        let ga = GitSync::new(cfg.clone());
        ga.ensure_repo(a.path(), &cfg).unwrap();
        ga.sync_now(a.path(), &cfg).unwrap();

        let b = tempfile::tempdir().unwrap();
        let gb = GitSync::new(cfg.clone());
        gb.ensure_repo(b.path(), &cfg).unwrap();
        gb.pull_at_start(b.path(), &cfg).unwrap();
        let mut wb = storage::load_workspace(b.path()).unwrap();

        let mut card_a = Card::new("note", 0.0, 0.0);
        card_a.title = "from A".into();
        let mut wa2 = storage::load_workspace(a.path()).unwrap();
        wa2.grids[0].cards.push(card_a);
        storage::save_workspace(a.path(), &wa2).unwrap();
        ga.sync_now(a.path(), &cfg).unwrap();

        let mut card_b = Card::new("note", 40.0, 40.0);
        card_b.title = "from B".into();
        wb.grids[0].cards.push(card_b);
        storage::save_workspace(b.path(), &wb).unwrap();
        gb.sync_now(b.path(), &cfg).unwrap();

        let merged = storage::load_workspace(b.path()).unwrap();
        let titles: Vec<_> = merged.grids[0]
            .cards
            .iter()
            .map(|c| c.title.clone())
            .collect();
        assert!(titles.iter().any(|t| t == "from A"));
        assert!(titles.iter().any(|t| t == "from B"));

        let fresh = tempfile::tempdir().unwrap();
        let gc = GitSync::new(cfg.clone());
        gc.ensure_repo(fresh.path(), &cfg).unwrap();
        gc.pull_at_start(fresh.path(), &cfg).unwrap();
        let pulled = storage::load_workspace(fresh.path()).unwrap();
        let titles: Vec<_> = pulled.grids[0]
            .cards
            .iter()
            .map(|c| c.title.clone())
            .collect();
        assert!(titles.iter().any(|t| t == "from A"));
        assert!(titles.iter().any(|t| t == "from B"));
    }
}
