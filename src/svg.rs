use serde_json::Value;

const DEFAULT_STROKE_COLOR: &str = "#d98e5c";
const DEFAULT_STROKE_WIDTH: f64 = 3.0;

/// Return the SVG document embedded in pasted text, if the text looks like SVG
/// markup rather than prose that happens to mention an `<svg>` tag.
pub fn extract_svg(text: &str) -> Option<&str> {
    let trimmed = text.trim_start_matches('\u{feff}').trim();
    if trimmed.is_empty() {
        return None;
    }
    let lower = trimmed.to_ascii_lowercase();
    let start = lower.find("<svg")?;
    let after = lower[start + 4..].chars().next()?;
    if !(after.is_whitespace() || after == '>' || after == '/') {
        return None;
    }
    let prefix = trimmed[..start].trim().to_ascii_lowercase();
    let prefix_ok = prefix.is_empty()
        || prefix.starts_with("<?xml")
        || prefix.starts_with("<!--")
        || prefix.starts_with("<!doctype");
    if !prefix_ok {
        return None;
    }
    let open_end = start + lower[start..].find('>')?;
    let self_closing = lower[start..open_end].trim_end().ends_with('/');
    if !self_closing && !lower.contains("</svg") {
        return None;
    }
    Some(trimmed)
}

/// Render the whiteboard stroke list as a standalone SVG document. Pressure
/// sensitive strokes become a set of line segments with their own width, just
/// like the live canvas renderer.
pub fn strokes_to_svg(strokes: &[Value], width: f64, height: f64) -> String {
    let width = positive_or(width, 416.0);
    let height = positive_or(height, 320.0);
    let mut svg = format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{}\" height=\"{}\" viewBox=\"0 0 {} {}\" fill=\"none\">\n",
        num(width),
        num(height),
        num(width),
        num(height)
    );
    for stroke in strokes {
        let color = escape_attr(
            stroke
                .get("color")
                .and_then(Value::as_str)
                .unwrap_or(DEFAULT_STROKE_COLOR),
        );
        let base = positive_or(
            stroke
                .get("width")
                .and_then(Value::as_f64)
                .unwrap_or(DEFAULT_STROKE_WIDTH),
            DEFAULT_STROKE_WIDTH,
        )
        .max(0.1);
        let points = stroke_points(stroke);
        if points.len() < 2 {
            continue;
        }
        if points.iter().all(|point| point.2.is_some()) {
            for pair in points.windows(2) {
                let a = pair[0];
                let b = pair[1];
                let pressure = ((a.2.unwrap_or(1.0) + b.2.unwrap_or(1.0)) / 2.0).clamp(0.0, 1.0);
                svg.push_str(&format!(
                    "<line x1=\"{}\" y1=\"{}\" x2=\"{}\" y2=\"{}\" stroke=\"{}\" stroke-width=\"{}\" stroke-linecap=\"round\"/>\n",
                    num(a.0),
                    num(a.1),
                    num(b.0),
                    num(b.1),
                    color,
                    num(base * (0.25 + 0.75 * pressure))
                ));
            }
            continue;
        }
        let mut path = format!("M {} {}", num(points[0].0), num(points[0].1));
        for point in &points[1..] {
            path.push_str(&format!(" L {} {}", num(point.0), num(point.1)));
        }
        svg.push_str(&format!(
            "<path d=\"{}\" stroke=\"{}\" stroke-width=\"{}\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n",
            path,
            color,
            num(base)
        ));
    }
    svg.push_str("</svg>\n");
    svg
}

/// Serialize the raw stroke list for "Copy as Stroke". The output can be fed
/// back into the `strokes` payload or the MCP `whiteboard.stroke` tool.
pub fn strokes_to_json(strokes: &[Value]) -> String {
    serde_json::to_string_pretty(strokes).unwrap_or_else(|_| "[]".to_string())
}

fn stroke_points(stroke: &Value) -> Vec<(f64, f64, Option<f64>)> {
    stroke
        .get("points")
        .and_then(Value::as_array)
        .map(|points| {
            points
                .iter()
                .filter_map(|point| {
                    let x = point.get("x").and_then(Value::as_f64)?;
                    let y = point.get("y").and_then(Value::as_f64)?;
                    if !x.is_finite() || !y.is_finite() {
                        return None;
                    }
                    let pressure = point
                        .get("p")
                        .and_then(Value::as_f64)
                        .filter(|value| value.is_finite());
                    Some((x, y, pressure))
                })
                .collect()
        })
        .unwrap_or_default()
}

fn positive_or(value: f64, fallback: f64) -> f64 {
    if value.is_finite() && value > 0.0 {
        value
    } else {
        fallback
    }
}

fn num(value: f64) -> String {
    if !value.is_finite() {
        return "0".to_string();
    }
    let text = format!("{value:.2}");
    let trimmed = text.trim_end_matches('0').trim_end_matches('.');
    if trimmed.is_empty() || trimmed == "-0" {
        "0".to_string()
    } else {
        trimmed.to_string()
    }
}

fn escape_attr(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(ch),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn detects_plain_svg_markup() {
        let svg = r#"<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>"#;
        assert_eq!(extract_svg(svg), Some(svg));
    }

    #[test]
    fn detects_svg_with_xml_prolog_and_leading_space() {
        let svg = "  <?xml version=\"1.0\"?>\n<!-- drawing -->\n<svg xmlns=\"http://www.w3.org/2000/svg\"/>\n";
        assert!(extract_svg(svg).is_some());
    }

    #[test]
    fn ignores_prose_and_incomplete_svg() {
        assert!(extract_svg("Use <svg> tags to draw icons.").is_none());
        assert!(extract_svg("<svg xmlns=\"http://www.w3.org/2000/svg\"><rect/>").is_none());
        assert!(extract_svg("just some pasted text").is_none());
    }

    #[test]
    fn renders_strokes_as_svg_paths() {
        let strokes = vec![json!({
            "color": "#7aa2f7",
            "width": 4,
            "points": [{"x": 10, "y": 12}, {"x": 20, "y": 24}, {"x": 30, "y": 18}]
        })];
        let svg = strokes_to_svg(&strokes, 320.0, 200.0);
        assert!(svg.starts_with("<svg "));
        assert!(svg.contains("viewBox=\"0 0 320 200\""));
        assert!(svg
            .contains("<path d=\"M 10 12 L 20 24 L 30 18\" stroke=\"#7aa2f7\" stroke-width=\"4\""));
        assert!(svg.ends_with("</svg>\n"));
    }

    #[test]
    fn renders_pressure_strokes_as_variable_width_lines() {
        let strokes = vec![json!({
            "color": "#ffffff",
            "width": 4,
            "points": [
                {"x": 0, "y": 0, "p": 0.0},
                {"x": 10, "y": 0, "p": 1.0}
            ]
        })];
        let svg = strokes_to_svg(&strokes, 100.0, 100.0);
        assert!(svg.contains("<line "));
        assert!(svg.contains("stroke-width=\"2.5\""));
        assert!(!svg.contains("<path "));
    }

    #[test]
    fn escapes_attribute_values() {
        let strokes = vec![json!({
            "color": "\"><script>alert(1)</script>",
            "width": 2,
            "points": [{"x": 0, "y": 0}, {"x": 1, "y": 1}]
        })];
        let svg = strokes_to_svg(&strokes, 10.0, 10.0);
        assert!(!svg.contains("<script>"));
        assert!(svg.contains("&quot;&gt;&lt;script&gt;"));
    }

    #[test]
    fn stroke_json_roundtrips() {
        let strokes = vec![json!({
            "color": "#d98e5c",
            "width": 3,
            "points": [{"x": 1, "y": 2, "p": 0.5}]
        })];
        let json = strokes_to_json(&strokes);
        let parsed: Value = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, Value::Array(strokes));
    }

    #[test]
    fn falls_back_to_default_canvas_size() {
        let svg = strokes_to_svg(&[], 0.0, f64::NAN);
        assert!(svg.contains("viewBox=\"0 0 416 320\""));
    }
}
