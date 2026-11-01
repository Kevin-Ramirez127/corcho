use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use directories::ProjectDirs;

use crate::model::Workspace;

pub fn project_dirs() -> ProjectDirs {
    ProjectDirs::from("io", "corcho", "corcho")
        .expect("no valid home directory")
}

pub fn default_data_dir() -> PathBuf {
    project_dirs().data_dir().to_path_buf()
}

pub fn workspace_path(data_dir: &Path) -> PathBuf {
    data_dir.join("workspace.json")
}

pub fn attachments_dir(data_dir: &Path) -> PathBuf {
    data_dir.join("attachments")
}

pub fn backups_dir(data_dir: &Path) -> PathBuf {
    data_dir.join("backups")
}

pub fn ensure_dirs(data_dir: &Path) -> Result<()> {
    fs::create_dir_all(data_dir)?;
    fs::create_dir_all(attachments_dir(data_dir))?;
    fs::create_dir_all(backups_dir(data_dir))?;
    Ok(())
}

pub fn load_workspace(data_dir: &Path) -> Result<Workspace> {
    let path = workspace_path(data_dir);
    if !path.exists() {
        return Ok(Workspace::default());
    }
    let raw = fs::read_to_string(&path).with_context(|| format!("read {}", path.display()))?;
    let mut ws: Workspace = serde_json::from_str(&raw).unwrap_or_else(|err| {
        tracing::error!("workspace parse failed: {err}; starting with backup-safe empty state");
        Workspace::default()
    });
    for g in &mut ws.grids {
        for (i, c) in g.cards.iter_mut().enumerate() {
            if !c.x.is_finite() || c.x.abs() > 1_000_000.0 {
                c.x = 64.0 + i as f64 * 28.0;
            }
            if !c.y.is_finite() || c.y.abs() > 1_000_000.0 {
                c.y = 64.0 + i as f64 * 28.0;
            }
            if !c.width.is_finite() || c.width < 80.0 || c.width > 10_000.0 {
                c.width = 320.0;
            }
            if !c.height.is_finite() || c.height < 64.0 || c.height > 10_000.0 {
                c.height = 240.0;
            }
        }
        if !g.zoom.is_finite() || g.zoom < 0.2 {
            g.zoom = 1.0;
        }
        if !g.pan_x.is_finite() {
            g.pan_x = 0.0;
        }
        if !g.pan_y.is_finite() {
            g.pan_y = 0.0;
        }
    }
    if ws.active_grid_id.is_none() {
        ws.active_grid_id = ws.grids.first().map(|g| g.id.clone());
    }
    if ws.grids.is_empty() {
        let g = ws.add_grid("Grid A");
        ws.active_grid_id = Some(g.id);
    }
    Ok(ws)
}

pub fn save_workspace(data_dir: &Path, ws: &Workspace) -> Result<()> {
    ensure_dirs(data_dir)?;
    let path = workspace_path(data_dir);
    let tmp = path.with_extension("json.tmp");
    let raw = serde_json::to_string_pretty(ws)?;
    {
        let mut f = fs::File::create(&tmp)?;
        f.write_all(raw.as_bytes())?;
        f.sync_all()?;
    }
    if path.exists() {
        let bak = path.with_extension("json.bak");
        let _ = fs::copy(&path, bak);
    }
    fs::rename(&tmp, &path)?;
    Ok(())
}

pub fn export_zip(data_dir: &Path, dest: &Path) -> Result<()> {
    ensure_dirs(data_dir)?;
    let file = fs::File::create(dest)?;
    let mut zip = zip::ZipWriter::new(file);
    let opts = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);

    let ws_path = workspace_path(data_dir);
    if ws_path.exists() {
        let mut buf = Vec::new();
        fs::File::open(&ws_path)?.read_to_end(&mut buf)?;
        zip.start_file("workspace.json", opts)?;
        zip.write_all(&buf)?;
    }

    let att = attachments_dir(data_dir);
    if att.exists() {
        for entry in fs::read_dir(&att)? {
            let entry = entry?;
            if !entry.file_type()?.is_file() {
                continue;
            }
            let mut buf = Vec::new();
            fs::File::open(entry.path())?.read_to_end(&mut buf)?;
            zip.start_file(format!("attachments/{}", entry.file_name().to_string_lossy()), opts)?;
            zip.write_all(&buf)?;
        }
    }
    zip.finish()?;
    Ok(())
}

pub fn import_zip(data_dir: &Path, src: &Path) -> Result<Workspace> {
    ensure_dirs(data_dir)?;
    let file = fs::File::open(src)?;
    let mut zip = zip::ZipArchive::new(file)?;
    let mut ws_raw = None;
    for i in 0..zip.len() {
        let mut entry = zip.by_index(i)?;
        let name = entry.name().to_string();
        if name == "workspace.json" {
            let mut s = String::new();
            entry.read_to_string(&mut s)?;
            ws_raw = Some(s);
        } else if let Some(rest) = name.strip_prefix("attachments/") {
            if rest.is_empty() || rest.contains('/') {
                continue;
            }
            let mut buf = Vec::new();
            entry.read_to_end(&mut buf)?;
            fs::write(attachments_dir(data_dir).join(rest), buf)?;
        }
    }
    let raw = ws_raw.context("backup contains no workspace.json")?;
    let ws: Workspace = serde_json::from_str(&raw).context("invalid Corcho backup file")?;
    save_workspace(data_dir, &ws)?;
    Ok(ws)
}

/// Import the legacy Electron data folder (grids + settings).
pub fn import_legacy(dir: &Path) -> Result<Workspace> {
    let mut ws = Workspace::default();
    ws.grids.clear();

    let settings_path = dir.join("settings.json");
    if settings_path.exists() {
        if let Ok(raw) = fs::read_to_string(&settings_path) {
            if let Ok(mut s) = serde_json::from_str::<serde_json::Value>(&raw) {
                crate::core::merge_settings_value(&mut ws.settings, &mut s);
            }
        }
    }

    let grids_path = dir.join("grids.json");
    if grids_path.exists() {
        let raw = fs::read_to_string(&grids_path)?;
        let value: serde_json::Value = serde_json::from_str(&raw)?;
        if let Some(arr) = value.as_array() {
            for g in arr {
                if let Ok(grid) = serde_json::from_value::<crate::model::Grid>(g.clone()) {
                    ws.grids.push(grid);
                }
            }
        }
    }

    for entry in fs::read_dir(dir).unwrap_or_else(|_| fs::read_dir(".").unwrap()) {
        let Ok(entry) = entry else { continue };
        let p = entry.path();
        if p.extension().and_then(|e| e.to_str()) == Some("json")
            && p.file_name().and_then(|n| n.to_str()).map(|n| n.starts_with("grid-")).unwrap_or(false)
        {
            if let Ok(raw) = fs::read_to_string(&p) {
                if let Ok(grid) = serde_json::from_str::<crate::model::Grid>(&raw) {
                    ws.grids.push(grid);
                }
            }
        }
    }

    if ws.grids.is_empty() {
        ws = Workspace::default();
    } else {
        ws.active_grid_id = ws.grids.first().map(|g| g.id.clone());
    }
    Ok(ws)
}

pub fn read_attachment(data_dir: &Path, name: &str) -> Result<Vec<u8>> {
    let safe = Path::new(name).file_name().context("invalid attachment name")?;
    Ok(fs::read(attachments_dir(data_dir).join(safe))?)
}

pub fn write_attachment(data_dir: &Path, name: &str, bytes: &[u8]) -> Result<PathBuf> {
    ensure_dirs(data_dir)?;
    let safe = Path::new(name).file_name().context("invalid attachment name")?;
    let dest = attachments_dir(data_dir).join(safe);
    fs::write(&dest, bytes)?;
    Ok(dest)
}

pub fn list_attachments(data_dir: &Path) -> Vec<String> {
    let dir = attachments_dir(data_dir);
    let mut out = Vec::new();
    if let Ok(rd) = fs::read_dir(dir) {
        for e in rd.flatten() {
            if e.file_type().map(|t| t.is_file()).unwrap_or(false) {
                out.push(e.file_name().to_string_lossy().to_string());
            }
        }
    }
    out.sort();
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Card, Workspace};

    #[test]
    fn save_and_load_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let mut ws = Workspace::default();
        ws.grids[0].cards.push(Card::new("note", 40.0, 60.0));
        save_workspace(dir.path(), &ws).unwrap();
        let loaded = load_workspace(dir.path()).unwrap();
        assert_eq!(loaded.grids[0].cards.len(), 1);
        assert_eq!(loaded.grids[0].cards[0].x, 40.0);
    }

    #[test]
    fn suspicious_geometry_is_repaired() {
        let dir = tempfile::tempdir().unwrap();
        let mut ws = Workspace::default();
        let mut card = Card::new("note", 1.0e12, -1.0e12);
        card.width = -4.0;
        ws.grids[0].cards.push(card);
        ws.grids[0].zoom = 0.0;
        save_workspace(dir.path(), &ws).unwrap();
        let loaded = load_workspace(dir.path()).unwrap();
        assert_eq!(loaded.grids[0].zoom, 1.0);
        assert!(loaded.grids[0].cards[0].x.is_finite());
        assert!(loaded.grids[0].cards[0].width >= 80.0);
    }
}
