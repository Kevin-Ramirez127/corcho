use anyhow::{anyhow, Context, Result};
use futures_util::StreamExt;
use serde_json::{json, Value};

use crate::model::models_by_provider;

#[derive(Clone, Debug)]
pub struct AIRequest {
    pub provider: String,
    pub model: String,
    pub api_key: String,
    pub prompt: String,
    pub system_prompt: String,
    pub web_search: bool,
    pub server_url: String,
}

pub fn default_model(provider: &str) -> &'static str {
    match provider {
        "openai" => "gpt-5.4",
        "google" => "gemini-2.5-flash",
        "grok" => "grok-4-1-fast-reasoning",
        "mistral" => "mistral-large-latest",
        "local" => "",
        _ => "claude-opus-4-7",
    }
}

#[allow(dead_code)]
pub fn models_json() -> String {
    models_by_provider().to_string()
}

fn client() -> Result<reqwest::Client> {
    Ok(reqwest::Client::builder()
        .user_agent("Corcho/0.1")
        .build()?)
}

fn auth_header(req: &AIRequest) -> String {
    req.api_key.clone()
}

fn openai_like_base(provider: &str, server_url: &str) -> String {
    match provider {
        "openai" => "https://api.openai.com/v1".to_string(),
        "xai" | "grok" => "https://api.x.ai/v1".to_string(),
        "mistral" => "https://api.mistral.ai/v1".to_string(),
        "local" => server_url.trim_end_matches('/').to_string(),
        _ => "https://api.openai.com/v1".to_string(),
    }
}

/// Validate an API key. Returns Ok(()) if the provider accepted it.
pub async fn validate_key(provider: &str, api_key: &str, server_url: &str) -> Result<()> {
    let c = client()?;
    match provider {
        "google" => {
            let url = format!(
                "https://generativelanguage.googleapis.com/v1beta/models?key={}",
                urlencode(api_key)
            );
            let r = c.get(url).send().await?;
            if r.status().is_success() {
                Ok(())
            } else {
                Err(anyhow!("Invalid API key"))
            }
        }
        "claude" | "anthropic" => {
            let body = json!({
                "model": "claude-haiku-4-5-20251001",
                "max_tokens": 1,
                "messages": [{"role": "user", "content": "ping"}]
            });
            let r = c
                .post("https://api.anthropic.com/v1/messages")
                .header("x-api-key", api_key)
                .header("anthropic-version", "2023-06-01")
                .json(&body)
                .send()
                .await?;
            if r.status().is_success() {
                Ok(())
            } else {
                Err(anyhow!("Invalid API key"))
            }
        }
        _ => {
            let base = openai_like_base(provider, server_url);
            let r = c
                .get(format!("{base}/models"))
                .bearer_auth(api_key)
                .send()
                .await?;
            if r.status().is_success() {
                Ok(())
            } else {
                Err(anyhow!("Invalid API key"))
            }
        }
    }
}

pub async fn fetch_models(server_url: &str, api_key: &str) -> Result<Vec<Value>> {
    let c = client()?;
    let base = server_url.trim_end_matches('/');
    let r = c
        .get(format!("{base}/models"))
        .bearer_auth(api_key)
        .send()
        .await?;
    let v: Value = r.json().await?;
    Ok(v.get("data")
        .and_then(|d| d.as_array())
        .cloned()
        .unwrap_or_default())
}

/// Run a completion; `on_chunk` receives incremental text when streaming.
pub async fn complete(req: AIRequest, mut on_chunk: impl FnMut(&str) + Send) -> Result<String> {
    match req.provider.as_str() {
        "claude" | "anthropic" => anthropic(req, &mut on_chunk).await,
        "google" => google(req, &mut on_chunk).await,
        _ => openai_like(req, &mut on_chunk).await,
    }
}

async fn anthropic(req: AIRequest, on_chunk: &mut (impl FnMut(&str) + Send)) -> Result<String> {
    let c = client()?;
    let body = json!({
        "model": req.model,
        "max_tokens": 4096,
        "stream": true,
        "system": req.system_prompt,
        "messages": [{"role": "user", "content": req.prompt}]
    });
    let r = c
        .post("https://api.anthropic.com/v1/messages")
        .header("x-api-key", auth_header(&req))
        .header("anthropic-version", "2023-06-01")
        .header("content-type", "application/json")
        .json(&body)
        .send()
        .await?;
    if !r.status().is_success() {
        return Err(anyhow!(
            "AI request failed: {}",
            r.text().await.unwrap_or_default()
        ));
    }
    read_sse(r, |event, data| {
        if event == "content_block_delta" {
            if let Ok(v) = serde_json::from_str::<Value>(data) {
                if let Some(text) = v.pointer("/delta/text").and_then(|t| t.as_str()) {
                    on_chunk(text);
                    return Some(text.to_string());
                }
            }
        }
        None
    })
    .await
}

async fn google(req: AIRequest, on_chunk: &mut (impl FnMut(&str) + Send)) -> Result<String> {
    let c = client()?;
    let mut contents = vec![json!({"role":"user","parts":[{"text": req.prompt}]})];
    if req.web_search {
        contents.insert(0, json!({"role":"user","parts":[{"text":"Answer using current web knowledge where relevant."}]}));
    }
    let body = json!({
        "contents": contents,
        "systemInstruction": {"parts":[{"text": req.system_prompt}]}
    });
    let url = format!(
        "https://generativelanguage.googleapis.com/v1beta/models/{}:streamGenerateContent?alt=sse&key={}",
        req.model,
        urlencode(&req.api_key)
    );
    let r = c.post(url).json(&body).send().await?;
    if !r.status().is_success() {
        return Err(anyhow!(
            "AI request failed: {}",
            r.text().await.unwrap_or_default()
        ));
    }
    read_sse(r, |_event, data| {
        if let Ok(v) = serde_json::from_str::<Value>(data) {
            if let Some(parts) = v
                .pointer("/candidates/0/content/parts")
                .and_then(|p| p.as_array())
            {
                let mut s = String::new();
                for p in parts {
                    if let Some(t) = p.get("text").and_then(|t| t.as_str()) {
                        s.push_str(t);
                    }
                }
                if !s.is_empty() {
                    on_chunk(&s);
                    return Some(s);
                }
            }
        }
        None
    })
    .await
}

async fn openai_like(req: AIRequest, on_chunk: &mut (impl FnMut(&str) + Send)) -> Result<String> {
    let c = client()?;
    let base = openai_like_base(&req.provider, &req.server_url);
    let mut messages = vec![json!({"role":"system","content": req.system_prompt})];
    messages.push(json!({"role":"user","content": req.prompt}));
    let body = json!({
        "model": req.model,
        "messages": messages,
        "stream": true,
        "max_tokens": 4096
    });
    let r = c
        .post(format!("{base}/chat/completions"))
        .bearer_auth(auth_header(&req))
        .json(&body)
        .send()
        .await?;
    if !r.status().is_success() {
        return Err(anyhow!(
            "AI request failed: {}",
            r.text().await.unwrap_or_default()
        ));
    }
    read_sse(r, |_event, data| {
        if data == "[DONE]" {
            return None;
        }
        if let Ok(v) = serde_json::from_str::<Value>(data) {
            if let Some(t) = v
                .pointer("/choices/0/delta/content")
                .and_then(|t| t.as_str())
            {
                on_chunk(t);
                return Some(t.to_string());
            }
        }
        None
    })
    .await
}

async fn read_sse(
    r: reqwest::Response,
    mut handle: impl FnMut(&str, &str) -> Option<String>,
) -> Result<String> {
    let mut out = String::new();
    let mut buf = String::new();
    let mut event = String::new();
    let mut stream = r.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let bytes = chunk.context("AI stream error")?;
        buf.push_str(&String::from_utf8_lossy(&bytes));
        while let Some(pos) = buf.find('\n') {
            let line = buf[..pos].trim_end_matches('\r').to_string();
            buf.drain(..=pos);
            if line.is_empty() {
                event.clear();
                continue;
            }
            if let Some(rest) = line.strip_prefix("event:") {
                event = rest.trim().to_string();
            } else if let Some(rest) = line.strip_prefix("data:") {
                if let Some(text) = handle(&event, rest.trim()) {
                    out.push_str(&text);
                }
            }
        }
    }
    Ok(out)
}

fn urlencode(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes()).collect()
}

pub fn system_prompt() -> String {
    "You are the AI processor inside Corcho, a personal-development canvas. \
     Be concise, concrete and useful. Return only the requested content."
        .into()
}
