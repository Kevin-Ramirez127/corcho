use std::path::Path;

use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct LicenseState {
    pub active: bool,
    pub key: String,
    pub plan: String,
    pub email: Option<String>,
    pub name: Option<String>,
    pub expires_at: Option<String>,
    pub refunded: bool,
    pub last_checked: Option<String>,
    pub error: Option<String>,
}

fn path(data_dir: &Path) -> std::path::PathBuf {
    data_dir.join("license.json")
}

pub fn load(data_dir: &Path) -> LicenseState {
    std::fs::read_to_string(path(data_dir))
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

pub fn save(data_dir: &Path, state: &LicenseState) -> Result<()> {
    std::fs::create_dir_all(data_dir)?;
    std::fs::write(path(data_dir), serde_json::to_string_pretty(state)?)?;
    Ok(())
}

pub fn clear(data_dir: &Path) {
    let _ = std::fs::remove_file(path(data_dir));
}

/// Verify a license key with Gumroad. Set CORCHO_GUMROAD_PRODUCT_ID to
/// the product id from the store.
pub async fn verify(key: &str) -> Result<LicenseState> {
    let product_id = std::env::var("CORCHO_GUMROAD_PRODUCT_ID")
        .unwrap_or_else(|_| "corcho".to_string());
    let client = reqwest::Client::builder().user_agent("Corcho/0.1").build()?;
    let form = [
        ("product_id", product_id.as_str()),
        ("license_key", key),
        ("increment_uses_count", "false"),
    ];
    let r = client
        .post("https://api.gumroad.com/v2/licenses/verify")
        .form(&form)
        .send()
        .await?;
    let status = r.status();
    let body: Value = r.json().await.unwrap_or_else(|_| Value::Null);
    if !status.is_success() || body.get("success").and_then(|v| v.as_bool()) != Some(true) {
        return Err(anyhow!(
            "{}",
            body.get("message")
                .and_then(|v| v.as_str())
                .unwrap_or("Failed to activate license")
        ));
    }
    let purchase = body.get("purchase").cloned().unwrap_or(Value::Null);
    let refunded = purchase.get("refunded").and_then(|v| v.as_bool()).unwrap_or(false);
    let state = LicenseState {
        active: !refunded,
        key: key.to_string(),
        plan: purchase
            .get("variants")
            .and_then(|v| v.as_str())
            .unwrap_or("Corcho")
            .to_string(),
        email: purchase.get("email").and_then(|v| v.as_str()).map(str::to_string),
        name: purchase.get("full_name").and_then(|v| v.as_str()).map(str::to_string),
        expires_at: purchase
            .get("subscription_cancelled_at")
            .and_then(|v| v.as_str())
            .map(str::to_string),
        refunded,
        last_checked: Some(crate::core::now_iso()),
        error: None,
    };
    Ok(state)
}
