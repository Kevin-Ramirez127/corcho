use std::collections::HashSet;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use anyhow::{anyhow, Result};
use serde_json::{json, Value};

const DEFAULT_BLOCKLIST: &[&str] = &[
    "doubleclick.net",
    "googlesyndication.com",
    "googleadservices.com",
    "adservice.google.com",
    "googletagmanager.com",
    "googletagservices.com",
    "google-analytics.com",
    "analytics.google.com",
    "scorecardresearch.com",
    "quantserve.com",
    "outbrain.com",
    "taboola.com",
    "criteo.com",
    "criteo.net",
    "adsrvr.org",
    "adnxs.com",
    "rubiconproject.com",
    "pubmatic.com",
    "openx.net",
    "casalemedia.com",
    "moatads.com",
    "amazon-adsystem.com",
    "facebook.net",
    "connect.facebook.net",
    "hotjar.com",
    "mixpanel.com",
    "segment.io",
    "segment.com",
    "newrelic.com",
    "nr-data.net",
    "sentry-cdn.com",
    "fullstory.com",
    "clarity.ms",
    "bat.bing.com",
];

pub struct Adblock {
    enabled: bool,
    hosts: HashSet<String>,
}

impl Adblock {
    pub fn new() -> Self {
        let mut hosts = HashSet::new();
        for h in DEFAULT_BLOCKLIST {
            hosts.insert((*h).to_string());
        }
        Self {
            enabled: false,
            hosts,
        }
    }

    pub fn set_enabled(&mut self, enabled: bool) {
        self.enabled = enabled;
    }

    #[allow(dead_code)]
    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    pub fn load_lists(&mut self, data_dir: &Path) {
        let path = data_dir.join("adblock.txt");
        let Ok(raw) = std::fs::read_to_string(path) else {
            return;
        };
        for line in raw.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') || line.starts_with('!') {
                continue;
            }
            let host = line
                .trim_start_matches("||")
                .trim_start_matches("0.0.0.0 ")
                .trim_start_matches("127.0.0.1 ")
                .split(['^', '/', '$'])
                .next()
                .unwrap_or("")
                .trim();
            if !host.is_empty() && host.contains('.') && !host.contains('*') {
                self.hosts.insert(host.to_lowercase());
            }
        }
        tracing::info!("adblock hosts loaded: {}", self.hosts.len());
    }

    pub fn blocked(&self, url: &str) -> bool {
        if !self.enabled {
            return false;
        }
        let Ok(parsed) = url::Url::parse(url) else {
            return false;
        };
        let Some(host) = parsed.host_str() else {
            return false;
        };
        let host = host.to_lowercase();
        self.hosts
            .iter()
            .any(|b| host == *b || host.ends_with(&format!(".{b}")))
    }
}

pub fn run_script(script: &str, timeout: Duration) -> Result<Value> {
    let start = Instant::now();
    let mut child = Command::new("/bin/sh")
        .arg("-c")
        .arg(script)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    loop {
        if let Some(status) = child.try_wait()? {
            let out = child.wait_with_output()?;
            return Ok(json!({
                "ok": status.success(),
                "code": status.code(),
                "stdout": String::from_utf8_lossy(&out.stdout),
                "stderr": String::from_utf8_lossy(&out.stderr),
                "ms": start.elapsed().as_millis(),
            }));
        }
        if start.elapsed() > timeout {
            let _ = child.kill();
            return Ok(json!({"ok": false, "error": "timed out", "stdout": "", "stderr": ""}));
        }
        std::thread::sleep(Duration::from_millis(20));
    }
}

fn playerctl(args: &[&str]) -> Result<String> {
    let out = Command::new("playerctl")
        .args(args)
        .output()
        .map_err(|e| anyhow!("playerctl unavailable: {e}"))?;
    if !out.status.success() {
        return Err(anyhow!("{}", String::from_utf8_lossy(&out.stderr)));
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

pub fn mpris_players() -> Value {
    let players = playerctl(&["--list-all"])
        .map(|s| s.lines().map(str::to_string).collect::<Vec<_>>())
        .unwrap_or_default();
    let mut out = Vec::new();
    for p in players {
        out.push(mpris_metadata_named(&p));
    }
    Value::Array(out)
}

pub fn mpris_metadata_named(player: &str) -> Value {
    let fmt = "{{playerName}}|{{title}}|{{artist}}|{{album}}|{{status}}|{{mpris:length}}|{{mpris:artUrl}}";
    match playerctl(&["--player", player, "metadata", "--format", fmt]) {
        Ok(line) => {
            let parts: Vec<&str> = line.split('|').collect();
            let pos = playerctl(&["--player", player, "position"]).unwrap_or_default();
            json!({
                "playerName": parts.first().copied().unwrap_or(player),
                "title": parts.get(1).copied().unwrap_or(""),
                "artist": parts.get(2).copied().unwrap_or(""),
                "album": parts.get(3).copied().unwrap_or(""),
                "status": parts.get(4).copied().unwrap_or("Stopped"),
                "lengthUs": parts.get(5).copied().unwrap_or("0").parse::<f64>().unwrap_or(0.0),
                "artUrl": parts.get(6).copied().unwrap_or(""),
                "positionUs": pos.parse::<f64>().unwrap_or(0.0),
            })
        }
        Err(e) => json!({"playerName": player, "error": e.to_string()}),
    }
}

pub fn mpris_action(player: &str, action: &str) -> Value {
    let action = match action {
        "play" | "pause" | "play-pause" | "next" | "previous" | "stop" | "shuffle" | "repeat" => {
            action
        }
        _ => return json!({"ok": false, "error": "unknown action"}),
    };
    match playerctl(&["--player", player, action]) {
        Ok(_) => json!({"ok": true}),
        Err(e) => json!({"ok": false, "error": e.to_string()}),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn script_captures_stdout() {
        let result = run_script("printf corcho", Duration::from_secs(5)).unwrap();
        assert_eq!(result["ok"], true);
        assert!(result["stdout"].as_str().unwrap().contains("corcho"));
    }

    #[test]
    fn adblock_matches_hosts_and_subdomains() {
        let mut block = Adblock::new();
        assert!(!block.blocked("https://doubleclick.net/x"));
        block.set_enabled(true);
        assert!(block.blocked("https://doubleclick.net/x"));
        assert!(block.blocked("https://ads.doubleclick.net/x"));
        assert!(!block.blocked("https://example.com/x"));
    }
}
