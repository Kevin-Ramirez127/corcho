use anyhow::{anyhow, Result};
use reqwest::Client;
use serde_json::{json, Value};

#[derive(Clone, Debug)]
pub struct RepoTokens {
    pub github: String,
    pub gitlab: String,
    pub forgejo: String,
    pub auth_gh: bool,
}

fn gh_token() -> String {
    std::process::Command::new("gh")
        .args(["auth", "token", "--hostname", "github.com"])
        .env("GH_PROMPT_DISABLED", "1")
        .output()
        .ok()
        .filter(|out| out.status.success())
        .map(|out| String::from_utf8_lossy(&out.stdout).trim().to_string())
        .unwrap_or_default()
}

struct Repo {
    provider: &'static str,
    host: String,
    owner: String,
    name: String,
}

fn parse_repo(input: &str) -> Result<Repo> {
    let raw = input.trim();
    if raw.is_empty() {
        return Err(anyhow!("no repository URL"));
    }
    let shorthand = raw.trim_matches('/').split('/').collect::<Vec<_>>();
    let (host, path) = if !raw.contains("://")
        && !raw.starts_with("git@")
        && shorthand.len() == 2
        && !shorthand[0].contains('.')
    {
        ("github.com".to_string(), raw.trim_matches('/').to_string())
    } else if let Some(rest) = raw.strip_prefix("git@") {
        let (host, path) = rest
            .split_once(':')
            .ok_or_else(|| anyhow!("invalid repository URL"))?;
        (host.to_string(), path.to_string())
    } else {
        let url = url::Url::parse(raw).or_else(|_| url::Url::parse(&format!("https://{raw}")))?;
        (
            url.host_str().unwrap_or("").to_string(),
            url.path().to_string(),
        )
    };
    let mut parts = path.trim_matches('/').split('/');
    let owner = parts
        .next()
        .filter(|part| !part.is_empty())
        .ok_or_else(|| anyhow!("missing repository owner"))?
        .to_string();
    let name = parts
        .next()
        .filter(|part| !part.is_empty())
        .ok_or_else(|| anyhow!("missing repository name"))?
        .trim_end_matches(".git")
        .to_string();
    let provider = if host.contains("github") {
        "github"
    } else if host.contains("gitlab") {
        "gitlab"
    } else {
        "forgejo"
    };
    Ok(Repo {
        provider,
        host,
        owner,
        name,
    })
}

fn client() -> Result<Client> {
    Ok(Client::builder()
        .user_agent("Corcho/0.1")
        .timeout(std::time::Duration::from_secs(20))
        .build()?)
}

fn token_for(provider: &str, tokens: &RepoTokens) -> String {
    match provider {
        "github" if tokens.auth_gh => gh_token(),
        "github" => tokens.github.clone(),
        "gitlab" => tokens.gitlab.clone(),
        _ => tokens.forgejo.clone(),
    }
}

async fn github(c: &Client, repo: &Repo, token: &str) -> Result<Value> {
    let base = "https://api.github.com";
    let slug = format!("{}/{}", repo.owner, repo.name);
    let auth = |r: reqwest::RequestBuilder| {
        let r = r.header("Accept", "application/vnd.github+json");
        if token.is_empty() {
            r
        } else {
            r.bearer_auth(token)
        }
    };
    let issues = auth(c.get(format!("{base}/search/issues")).query(&[
        ("q", format!("repo:{slug} is:issue is:open")),
        ("per_page", "1".to_string()),
    ]))
    .send()
    .await?
    .json::<Value>()
    .await
    .ok()
    .and_then(|v| v.get("total_count").and_then(|v| v.as_u64()))
    .unwrap_or(0);
    let prs = auth(c.get(format!("{base}/search/issues")).query(&[
        ("q", format!("repo:{slug} is:pr is:open")),
        ("per_page", "1".to_string()),
    ]))
    .send()
    .await?
    .json::<Value>()
    .await
    .ok()
    .and_then(|v| v.get("total_count").and_then(|v| v.as_u64()))
    .unwrap_or(0);
    let commits = auth(c.get(format!("{base}/repos/{slug}/commits?per_page=1")))
        .send()
        .await?
        .json::<Value>()
        .await
        .ok();
    let last = commits
        .as_ref()
        .and_then(|v| v.as_array())
        .and_then(|a| a.first())
        .cloned()
        .unwrap_or_else(|| json!({}));
    let ci = match auth(c.get(format!("{base}/repos/{slug}/actions/runs?per_page=1")))
        .send()
        .await
    {
        Ok(r) => r.json::<Value>().await.ok(),
        Err(_) => None,
    };
    let run = ci
        .as_ref()
        .and_then(|v| v.pointer("/workflow_runs/0"))
        .cloned()
        .unwrap_or_else(|| json!({}));
    Ok(json!({
        "issues": issues,
        "pullRequests": prs,
        "lastCommit": {
            "sha": last.get("sha").and_then(|v| v.as_str()).unwrap_or("").chars().take(7).collect::<String>(),
            "message": last.pointer("/commit/message").and_then(|v| v.as_str()).unwrap_or("").lines().next().unwrap_or(""),
            "author": last.pointer("/commit/author/name").and_then(|v| v.as_str()).unwrap_or(""),
            "date": last.pointer("/commit/author/date").and_then(|v| v.as_str()).unwrap_or(""),
            "url": last.get("html_url").and_then(|v| v.as_str()).unwrap_or("")
        },
        "ci": {
            "status": run.get("conclusion").and_then(|v| v.as_str())
                .or_else(|| run.get("status").and_then(|v| v.as_str()))
                .unwrap_or("unknown"),
            "name": run.get("name").and_then(|v| v.as_str()).unwrap_or("")
        }
    }))
}

fn total(header: Option<&str>) -> u64 {
    header.and_then(|v| v.parse().ok()).unwrap_or(0)
}

async fn gitlab(c: &Client, repo: &Repo, token: &str) -> Result<Value> {
    let base = format!("https://{}/api/v4", repo.host);
    let encoded: String =
        url::form_urlencoded::byte_serialize(format!("{}/{}", repo.owner, repo.name).as_bytes())
            .collect();
    let auth = |r: reqwest::RequestBuilder| {
        if token.is_empty() {
            r
        } else {
            r.header("PRIVATE-TOKEN", token)
        }
    };
    let project = format!("{base}/projects/{encoded}");
    let issues = auth(c.get(format!("{project}/issues?state=opened&per_page=1")))
        .send()
        .await?;
    let issues_total = total(
        issues
            .headers()
            .get("x-total")
            .and_then(|v| v.to_str().ok()),
    );
    let prs = auth(c.get(format!("{project}/merge_requests?state=opened&per_page=1")))
        .send()
        .await?;
    let prs_total = total(prs.headers().get("x-total").and_then(|v| v.to_str().ok()));
    let last = auth(c.get(format!("{project}/repository/commits?per_page=1")))
        .send()
        .await?
        .json::<Value>()
        .await
        .ok()
        .and_then(|v| v.as_array().and_then(|a| a.first().cloned()))
        .unwrap_or_else(|| json!({}));
    let pipeline = match auth(c.get(format!("{project}/pipelines?per_page=1")))
        .send()
        .await
    {
        Ok(r) => r
            .json::<Value>()
            .await
            .ok()
            .and_then(|v| v.as_array().and_then(|a| a.first().cloned()))
            .unwrap_or_else(|| json!({})),
        Err(_) => json!({}),
    };
    Ok(json!({
        "issues": issues_total,
        "pullRequests": prs_total,
        "lastCommit": {
            "sha": last.get("short_id").and_then(|v| v.as_str()).unwrap_or(""),
            "message": last.get("title").and_then(|v| v.as_str()).unwrap_or(""),
            "author": last.get("author_name").and_then(|v| v.as_str()).unwrap_or(""),
            "date": last.get("committed_date").and_then(|v| v.as_str()).unwrap_or("")
        },
        "ci": {
            "status": pipeline.get("status").and_then(|v| v.as_str()).unwrap_or("unknown"),
            "name": ""
        }
    }))
}

async fn forgejo(c: &Client, repo: &Repo, token: &str) -> Result<Value> {
    let base = format!("https://{}/api/v1", repo.host);
    let slug = format!("{}/{}", repo.owner, repo.name);
    let auth = |r: reqwest::RequestBuilder| {
        if token.is_empty() {
            r
        } else {
            r.header("Authorization", format!("token {token}"))
        }
    };
    let info = auth(c.get(format!("{base}/repos/{slug}")))
        .send()
        .await?
        .json::<Value>()
        .await
        .unwrap_or_else(|_| json!({}));
    let issues = info
        .get("open_issues_count")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);
    let prs = info
        .get("open_pr_counter")
        .and_then(|v| v.as_u64())
        .unwrap_or(0);
    let last = auth(c.get(format!("{base}/repos/{slug}/commits?limit=1")))
        .send()
        .await?
        .json::<Value>()
        .await
        .ok()
        .and_then(|v| v.as_array().and_then(|a| a.first().cloned()))
        .unwrap_or_else(|| json!({}));
    let sha = last.get("sha").and_then(|v| v.as_str()).unwrap_or("");
    let status = if sha.is_empty() {
        json!({})
    } else {
        match auth(c.get(format!("{base}/repos/{slug}/commits/{sha}/status")))
            .send()
            .await
        {
            Ok(r) => r.json::<Value>().await.unwrap_or_else(|_| json!({})),
            Err(_) => json!({}),
        }
    };
    Ok(json!({
        "issues": issues,
        "pullRequests": prs,
        "lastCommit": {
            "sha": sha.chars().take(7).collect::<String>(),
            "message": last.pointer("/commit/message").and_then(|v| v.as_str()).unwrap_or("").lines().next().unwrap_or(""),
            "author": last.pointer("/commit/author/name").and_then(|v| v.as_str()).unwrap_or(""),
            "date": last.pointer("/commit/author/date").and_then(|v| v.as_str()).unwrap_or("")
        },
        "ci": {
            "status": status.get("state").and_then(|v| v.as_str()).unwrap_or("unknown"),
            "name": ""
        }
    }))
}

pub async fn fetch(url: &str, tokens: RepoTokens) -> Value {
    let repo = match parse_repo(url) {
        Ok(repo) => repo,
        Err(err) => return json!({"error": err.to_string()}),
    };
    let token = token_for(repo.provider, &tokens);
    let c = match client() {
        Ok(c) => c,
        Err(err) => return json!({"error": err.to_string()}),
    };
    let result = match repo.provider {
        "github" => github(&c, &repo, &token).await,
        "gitlab" => gitlab(&c, &repo, &token).await,
        _ => forgejo(&c, &repo, &token).await,
    };
    match result {
        Ok(mut data) => {
            data["provider"] = json!(repo.provider);
            data["owner"] = json!(repo.owner);
            data["repo"] = json!(repo.name);
            data["url"] = json!(url);
            data
        }
        Err(err) => json!({"error": err.to_string(), "url": url}),
    }
}
