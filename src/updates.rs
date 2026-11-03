use std::path::Path;

use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct UpdateState {
    pub checked: bool,
    pub channel: String,
    pub current: String,
    pub latest: Option<String>,
    pub notes: Option<String>,
    pub url: Option<String>,
    pub mandatory: bool,
    pub downloading: bool,
    pub progress: f64,
    pub status: String,
    pub error: Option<String>,
}

fn repo() -> String {
    std::env::var("CORCHO_UPDATE_REPO").unwrap_or_else(|_| "emiliano-go/repo".to_string())
}

pub async fn check(channel: &str) -> Result<UpdateState> {
    let client = reqwest::Client::builder()
        .user_agent("Corcho/0.1")
        .build()?;
    let url = format!("https://api.github.com/repos/{}/releases", repo());
    let releases: Vec<Value> = client
        .get(url)
        .header("Accept", "application/vnd.github+json")
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;

    let current = semver::Version::parse(env!("CARGO_PKG_VERSION"))
        .unwrap_or_else(|_| semver::Version::new(0, 1, 0));
    let mut best: Option<(semver::Version, Value)> = None;

    for rel in releases {
        let draft = rel.get("draft").and_then(|v| v.as_bool()).unwrap_or(false);
        if draft {
            continue;
        }
        let pre = rel
            .get("prerelease")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let tag = rel.get("tag_name").and_then(|v| v.as_str()).unwrap_or("");
        let ver_str = tag.trim_start_matches('v');
        let Ok(ver) = semver::Version::parse(ver_str) else {
            continue;
        };
        if !ver.gt(&current) {
            continue;
        }
        let allowed = match channel {
            "experimental" => true,
            "beta" => pre || ver.pre.is_empty(),
            _ => !pre && ver.pre.is_empty(),
        };
        if !allowed {
            continue;
        }
        if best.as_ref().map(|(b, _)| ver > *b).unwrap_or(true) {
            best = Some((ver, rel));
        }
    }

    let mut state = UpdateState {
        checked: true,
        channel: channel.to_string(),
        current: current.to_string(),
        status: "up-to-date".into(),
        ..Default::default()
    };

    if let Some((ver, rel)) = best {
        state.latest = Some(ver.to_string());
        state.notes = rel.get("body").and_then(|v| v.as_str()).map(str::to_string);
        state.mandatory = state
            .notes
            .as_deref()
            .map(|n| n.to_lowercase().contains("mandatory"))
            .unwrap_or(false);
        state.url = rel
            .get("assets")
            .and_then(|a| a.as_array())
            .and_then(|assets| {
                assets.iter().find_map(|a| {
                    let name = a.get("name").and_then(|n| n.as_str()).unwrap_or("");
                    if name.contains("x86_64") && name.ends_with(".AppImage")
                        || name.ends_with("amd64.deb")
                    {
                        a.get("browser_download_url")
                            .and_then(|u| u.as_str())
                            .map(str::to_string)
                    } else {
                        None
                    }
                })
            });
        state.status = "available".into();
    }
    Ok(state)
}

pub async fn download(url: &str, dest: &Path, mut progress: impl FnMut(f64) + Send) -> Result<()> {
    let client = reqwest::Client::builder()
        .user_agent("Corcho/0.1")
        .build()?;
    let r = client.get(url).send().await?.error_for_status()?;
    let total = r.content_length().unwrap_or(0);
    if let Some(name) = dest.file_name() {
        let _ = name;
    }
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let mut file = tokio::fs::File::create(dest).await?;
    let mut done: u64 = 0;
    use tokio::io::AsyncWriteExt;
    let mut stream = r.bytes_stream();
    while let Some(chunk) = futures_util::StreamExt::next(&mut stream).await {
        let bytes = chunk?;
        file.write_all(&bytes).await?;
        done += bytes.len() as u64;
        if total > 0 {
            progress((done as f64 / total as f64) * 100.0);
        }
    }
    file.flush().await?;
    Ok(())
}

pub fn install(path: &Path) -> Result<()> {
    if !path.exists() {
        return Err(anyhow!("downloaded update not found"));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(path)?.permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(path, perms)?;
    }
    open::that_detached(path)?;
    Ok(())
}
