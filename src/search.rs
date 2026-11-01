use serde_json::json;

use crate::model::Workspace;

pub fn search(ws: &Workspace, query: &str) -> Vec<serde_json::Value> {
    let q = query.trim().to_lowercase();
    let mut results = Vec::new();

    if q.is_empty() {
        for g in &ws.grids {
            results.push(grid_result(g, ws));
        }
        return results;
    }

    for g in &ws.grids {
        if g.name.to_lowercase().contains(&q) {
            results.push(grid_result(g, ws));
        }
        for c in &g.cards {
            let hay = c.search_text().to_lowercase();
            if hay.contains(&q) {
                results.push(json!({
                    "type": "card",
                    "id": c.id,
                    "gridId": g.id,
                    "gridName": g.name,
                    "label": if c.title.is_empty() { c.kind.clone() } else { c.title.clone() },
                    "icon": c.icon,
                    "color": c.color,
                    "snippet": snippet(&c.text, &q),
                }));
            }
            if results.len() >= 60 {
                break;
            }
        }
        if results.len() >= 60 {
            break;
        }
    }
    results
}

pub fn grid_result(g: &crate::model::Grid, ws: &Workspace) -> serde_json::Value {
    let folder = g
        .folder_id
        .as_ref()
        .and_then(|id| ws.folders.iter().find(|f| &f.id == id))
        .map(|f| f.name.clone());
    json!({
        "type": "grid",
        "gridId": g.id,
        "gridName": g.name,
        "icon": "grid-2x2",
        "cardCount": g.cards.len(),
        "folder": folder,
    })
}

fn snippet(text: &str, q: &str) -> serde_json::Value {
    let lower = text.to_lowercase();
    if let Some(pos) = lower.find(q) {
        let start = pos.saturating_sub(24);
        let end = (pos + q.len() + 24).min(text.len());
        let before = text[start..pos].to_string();
        let match_part = text[pos..pos + q.len()].to_string();
        let after = text[pos + q.len()..end].to_string();
        json!({"before": before, "match": match_part, "after": after})
    } else {
        json!({"before": "", "match": "", "after": ""})
    }
}
