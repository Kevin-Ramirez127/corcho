use std::path::{Path, PathBuf};

use anyhow::{anyhow, Result};
use base64::Engine;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::model::Workspace;

pub const REMOTE_FILE: &str = "corcho-workspace.json";

fn hash(bytes: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(bytes);
    format!("{:x}", h.finalize())
}

fn local_path(data_dir: &Path) -> PathBuf {
    data_dir.join("workspace.json")
}

fn conflict_backup(data_dir: &Path, bytes: &[u8]) -> Result<()> {
    let dir = data_dir.join("backups");
    std::fs::create_dir_all(&dir)?;
    let name = format!(
        "conflict-{}.json",
        time::OffsetDateTime::now_utc().unix_timestamp()
    );
    std::fs::write(dir.join(name), bytes)?;
    Ok(())
}

/// Two-way folder sync. Returns (status, optional remote workspace to adopt).
pub fn sync_folder(
    data_dir: &Path,
    folder: &Path,
) -> Result<(String, Option<Workspace>)> {
    std::fs::create_dir_all(folder)?;
    let remote = folder.join(REMOTE_FILE);
    let local = local_path(data_dir);

    if !local.exists() {
        if remote.exists() {
            let bytes = std::fs::read(&remote)?;
            let ws = serde_json::from_slice::<Workspace>(&bytes)?;
            std::fs::create_dir_all(data_dir)?;
            std::fs::write(&local, &bytes)?;
            return Ok(("pulled".into(), Some(ws)));
        }
        return Ok(("empty".into(), None));
    }

    let local_bytes = std::fs::read(&local)?;
    let local_hash = hash(&local_bytes);

    if !remote.exists() {
        std::fs::write(&remote, &local_bytes)?;
        return Ok(("pushed".into(), None));
    }

    let remote_bytes = std::fs::read(&remote)?;
    if hash(&remote_bytes) == local_hash {
        return Ok(("up-to-date".into(), None));
    }

    conflict_backup(data_dir, &remote_bytes)?;

    let local_mtime = std::fs::metadata(&local)?.modified().ok();
    let remote_mtime = std::fs::metadata(&remote)?.modified().ok();
    let remote_newer = match (local_mtime, remote_mtime) {
        (Some(l), Some(r)) => r > l,
        _ => false,
    };

    if remote_newer {
        let ws: Workspace = serde_json::from_slice(&remote_bytes)?;
        std::fs::write(&local, &remote_bytes)?;
        Ok(("pulled".into(), Some(ws)))
    } else {
        std::fs::write(&remote, &local_bytes)?;
        Ok(("pushed".into(), None))
    }
}

pub fn pkce_pair() -> (String, String) {
    let random = format!(
        "{}{}",
        uuid::Uuid::new_v4(),
        uuid::Uuid::new_v4()
    );
    let verifier = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(random.as_bytes());
    let challenge = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .encode(Sha256::digest(verifier.as_bytes()));
    (verifier, challenge)
}

pub fn auth_url(client_id: &str, redirect_uri: &str, challenge: &str) -> String {
    let scope = "https://www.googleapis.com/auth/drive.appdata https://www.googleapis.com/auth/drive.file";
    format!(
        "https://accounts.google.com/o/oauth2/v2/auth?client_id={}&redirect_uri={}&response_type=code&scope={}&code_challenge={}&code_challenge_method=S256&access_type=offline&prompt=consent",
        urlencode(client_id),
        urlencode(redirect_uri),
        urlencode(scope),
        urlencode(challenge)
    )
}

pub async fn exchange_code(
    client_id: &str,
    client_secret: Option<&str>,
    code: &str,
    verifier: &str,
    redirect_uri: &str,
) -> Result<Value> {
    let client = reqwest::Client::new();
    let mut form = vec![
        ("client_id", client_id),
        ("code", code),
        ("code_verifier", verifier),
        ("grant_type", "authorization_code"),
        ("redirect_uri", redirect_uri),
    ];
    if let Some(secret) = client_secret {
        form.push(("client_secret", secret));
    }
    let r: Value = client
        .post("https://oauth2.googleapis.com/token")
        .form(&form)
        .send()
        .await?
        .json()
        .await?;
    if r.get("error").is_some() {
        return Err(anyhow!("{}", r.get("error_description").and_then(|v| v.as_str()).unwrap_or("OAuth failed")));
    }
    Ok(r)
}

pub async fn refresh_token(
    client_id: &str,
    client_secret: Option<&str>,
    refresh: &str,
) -> Result<String> {
    let client = reqwest::Client::new();
    let mut form = vec![
        ("client_id", client_id),
        ("refresh_token", refresh),
        ("grant_type", "refresh_token"),
    ];
    if let Some(secret) = client_secret {
        form.push(("client_secret", secret));
    }
    let r: Value = client
        .post("https://oauth2.googleapis.com/token")
        .form(&form)
        .send()
        .await?
        .json()
        .await?;
    r.get("access_token")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .ok_or_else(|| anyhow!("token refresh failed"))
}

pub async fn user_email(access_token: &str) -> Option<String> {
    let client = reqwest::Client::new();
    let v: Value = client
        .get("https://www.googleapis.com/oauth2/v2/userinfo")
        .bearer_auth(access_token)
        .send()
        .await
        .ok()?
        .json()
        .await
        .ok()?;
    v.get("email").and_then(|e| e.as_str()).map(str::to_string)
}

async fn find_file(client: &reqwest::Client, token: &str) -> Result<Option<String>> {
    let v: Value = client
        .get("https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&fields=files(id,name,modifiedTime)&pageSize=100")
        .bearer_auth(token)
        .send()
        .await?
        .json()
        .await?;
    Ok(v.get("files")
        .and_then(|f| f.as_array())
        .and_then(|files| {
            files
                .iter()
                .find(|f| f.get("name").and_then(|n| n.as_str()) == Some(REMOTE_FILE))
                .and_then(|f| f.get("id").and_then(|i| i.as_str()))
                .map(str::to_string)
        }))
}

pub async fn drive_read(token: &str) -> Result<Option<Vec<u8>>> {
    let client = reqwest::Client::new();
    let Some(id) = find_file(&client, token).await? else {
        return Ok(None);
    };
    let bytes = client
        .get(format!(
            "https://www.googleapis.com/drive/v3/files/{id}?alt=media"
        ))
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()?
        .bytes()
        .await?;
    Ok(Some(bytes.to_vec()))
}

pub async fn drive_write(token: &str, bytes: &[u8]) -> Result<()> {
    let client = reqwest::Client::new();
    if let Some(id) = find_file(&client, token).await? {
        client
            .patch(format!(
                "https://www.googleapis.com/upload/drive/v3/files/{id}?uploadType=media"
            ))
            .bearer_auth(token)
            .header("content-type", "application/json")
            .body(bytes.to_vec())
            .send()
            .await?
            .error_for_status()?;
    } else {
        let boundary = format!("corcho{}", uuid::Uuid::new_v4().simple());
        let meta = json!({
            "name": REMOTE_FILE,
            "parents": ["appDataFolder"]
        });
        let mut body = Vec::new();
        body.extend_from_slice(format!("--{boundary}\r\nContent-Type: application/json\r\n\r\n").as_bytes());
        body.extend_from_slice(meta.to_string().as_bytes());
        body.extend_from_slice(format!("\r\n--{boundary}\r\nContent-Type: application/json\r\n\r\n").as_bytes());
        body.extend_from_slice(bytes);
        body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
        client
            .post("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")
            .bearer_auth(token)
            .header("content-type", format!("multipart/related; boundary={boundary}"))
            .body(body)
            .send()
            .await?
            .error_for_status()?;
    }
    Ok(())
}

fn urlencode(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes()).collect()
}
