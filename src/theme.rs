use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

use anyhow::{anyhow, bail, Context, Result};
use serde_json::{json, Map, Value};

use crate::model;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TokenKind {
    Color,
    Length,
    Number,
    Integer,
    Duration,
    Text,
}

pub struct TokenSpec {
    pub key: &'static str,
    pub css: &'static str,
    pub kind: TokenKind,
    pub default: Value,
    #[allow(dead_code)]
    pub comment: &'static str,
}

macro_rules! spec {
    ($key:literal, $css:literal, $kind:ident, $default:expr, $comment:literal) => {
        TokenSpec {
            key: $key,
            css: $css,
            kind: TokenKind::$kind,
            default: json!($default),
            comment: $comment,
        }
    };
}

static SPECS: LazyLock<Vec<TokenSpec>> = LazyLock::new(|| {
    vec![
        spec!(
            "bg",
            "--bg",
            Color,
            "#121417",
            "Window and canvas background"
        ),
        spec!(
            "sidebar",
            "--sidebar",
            Color,
            "#202329",
            "Sidebar background"
        ),
        spec!(
            "surface",
            "--surface",
            Color,
            "#1b1e23",
            "Panels and dialogs"
        ),
        spec!("card", "--card", Color, "#2b2e34", "Card surface"),
        spec!(
            "surfaceStrong",
            "--surface-strong",
            Color,
            "#3a3e46",
            "Raised controls and selected rows"
        ),
        spec!("menu", "--menu", Color, "#2b2e34", "Menus and popovers"),
        spec!(
            "input",
            "--input",
            Color,
            "#221b1e23",
            "Text field background"
        ),
        spec!("hover", "--hover", Color, "#2e1b1e23", "Hover background"),
        spec!("border", "--border", Color, "#171b1e23", "Default border"),
        spec!(
            "borderStrong",
            "--border-strong",
            Color,
            "#291b1e23",
            "Hover and focus border"
        ),
        spec!("text", "--text", Color, "#ece7de", "Primary text"),
        spec!("text2", "--text-2", Color, "#dbebe7de", "Secondary text"),
        spec!(
            "muted",
            "--muted",
            Color,
            "#a8ece7de",
            "Muted text and icons"
        ),
        spec!("accent", "--accent", Color, "#d98e5c", "Accent color"),
        spec!(
            "accentButton",
            "--accent-button",
            Color,
            "#d98e5c",
            "Solid button background"
        ),
        spec!(
            "accentText",
            "--accent-text",
            Color,
            "#e7a97f",
            "Accent-colored text"
        ),
        spec!(
            "accentInk",
            "--accent-ink",
            Color,
            "#171717",
            "Text on accent backgrounds"
        ),
        spec!(
            "danger",
            "--danger",
            Color,
            "#d97a72",
            "Errors and destructive actions"
        ),
        spec!("success", "--success", Color, "#7fae83", "Success state"),
        spec!(
            "selection",
            "--selection",
            Color,
            "#59d98e5c",
            "Text selection"
        ),
        spec!("focus", "--focus", Color, "#d98e5c", "Focus ring"),
        spec!("overlay", "--overlay", Color, "#8c000000", "Modal scrim"),
        spec!("shadow", "--shadow", Color, "#40000000", "Shadow color"),
        spec!(
            "calendarToday",
            "--calendar-today",
            Color,
            "#29d98e5c",
            "Calendar today highlight"
        ),
        spec!(
            "fontFamily",
            "--font-family",
            Text,
            "Inter",
            "UI font family"
        ),
        spec!(
            "fontMono",
            "--font-mono",
            Text,
            "JetBrains Mono",
            "Monospace font family"
        ),
        spec!(
            "fontSizeCaption",
            "--font-size-caption",
            Length,
            10,
            "Caption text size"
        ),
        spec!(
            "fontSizeSmall",
            "--font-size-small",
            Length,
            12,
            "Small text size"
        ),
        spec!(
            "fontSizeBody",
            "--font-size-body",
            Length,
            14,
            "Body text size"
        ),
        spec!(
            "fontSizeSubtitle",
            "--font-size-subtitle",
            Length,
            15,
            "Subtitle text size"
        ),
        spec!(
            "fontSizeTitle",
            "--font-size-title",
            Length,
            16,
            "Title text size"
        ),
        spec!(
            "fontSizePage",
            "--font-size-page",
            Length,
            18,
            "Page and card title size"
        ),
        spec!(
            "fontSizeLarge",
            "--font-size-large",
            Length,
            22,
            "Large display text"
        ),
        spec!(
            "fontSizeDisplay",
            "--font-size-display",
            Length,
            32,
            "Hero display text"
        ),
        spec!(
            "fontWeightRegular",
            "--font-weight-regular",
            Integer,
            400,
            "Regular font weight"
        ),
        spec!(
            "fontWeightMedium",
            "--font-weight-medium",
            Integer,
            500,
            "Medium font weight"
        ),
        spec!(
            "fontWeightSemi",
            "--font-weight-semibold",
            Integer,
            600,
            "Semibold font weight"
        ),
        spec!(
            "lineHeightTight",
            "--line-height-tight",
            Number,
            1.2,
            "Tight line height"
        ),
        spec!(
            "lineHeightNormal",
            "--line-height-normal",
            Number,
            1.35,
            "Normal line height"
        ),
        spec!("space0", "--space-0", Length, 0, "No space"),
        spec!("space1", "--space-1", Length, 4, "Extra small gap"),
        spec!("space2", "--space-2", Length, 8, "Small gap"),
        spec!("spaceSnug", "--space-snug", Length, 10, "Snug gap"),
        spec!("space3", "--space-3", Length, 12, "Medium gap"),
        spec!("space4", "--space-4", Length, 16, "Default gap"),
        spec!("space5", "--space-5", Length, 24, "Large gap"),
        spec!("space6", "--space-6", Length, 32, "Section gap"),
        spec!("space7", "--space-7", Length, 40, "Page gap"),
        spec!("space8", "--space-8", Length, 48, "Hero gap"),
        spec!("spaceHalf", "--space-half", Length, 2, "Hairline gap"),
        spec!("spaceTight", "--space-tight", Length, 5, "Tight gap"),
        spec!("spaceCompact", "--space-compact", Length, 6, "Compact gap"),
        spec!(
            "fontSizeMicro",
            "--font-size-micro",
            Length,
            9,
            "Micro text size"
        ),
        spec!(
            "fontSizeHuge",
            "--font-size-huge",
            Length,
            40,
            "Oversized display text"
        ),
        spec!("radiusLine", "--radius-line", Length, 1, "Hairline radius"),
        spec!(
            "radiusHairline",
            "--radius-hairline",
            Length,
            2,
            "Hairline corner"
        ),
        spec!("radiusSmall", "--radius-small", Length, 3, "Small corner"),
        spec!("radiusMicro", "--radius-micro", Length, 4, "Micro corner"),
        spec!("radiusDot", "--radius-dot", Length, 5, "Dot corner"),
        spec!("radiusLoose", "--radius-loose", Length, 7, "Loose corner"),
        spec!("radiusBadge", "--radius-badge", Length, 9, "Badge corner"),
        spec!("radiusWide", "--radius-wide", Length, 11, "Wide corner"),
        spec!(
            "radiusLarge",
            "--radius-large",
            Length,
            24,
            "Large panel corner"
        ),
        spec!(
            "opacityNone",
            "--opacity-none",
            Number,
            0.0,
            "Fully transparent"
        ),
        spec!(
            "opacityEmphasis",
            "--opacity-emphasis",
            Number,
            0.65,
            "Emphasized decoration opacity"
        ),
        spec!(
            "radiusControl",
            "--radius-control",
            Length,
            8,
            "Buttons and inputs"
        ),
        spec!("radiusCard", "--radius-card", Length, 14, "Cards"),
        spec!(
            "radiusPanel",
            "--radius-panel",
            Length,
            16,
            "Panels and dialogs"
        ),
        spec!(
            "radiusMenu",
            "--radius-menu",
            Length,
            10,
            "Menus and popovers"
        ),
        spec!(
            "radiusPill",
            "--radius-pill",
            Length,
            999,
            "Pills and toggles"
        ),
        spec!(
            "radiusKeycap",
            "--radius-keycap",
            Length,
            6,
            "Keyboard keycaps"
        ),
        spec!(
            "borderWidth",
            "--border-width",
            Number,
            1,
            "Default border width"
        ),
        spec!(
            "borderWidthStrong",
            "--border-width-strong",
            Number,
            1.5,
            "Emphasized border width"
        ),
        spec!(
            "borderWidthFocus",
            "--border-width-focus",
            Number,
            1.5,
            "Focus border width"
        ),
        spec!("iconSmall", "--icon-small", Length, 14, "Small icon"),
        spec!("iconBody", "--icon-body", Length, 16, "Default icon"),
        spec!("iconLarge", "--icon-large", Length, 20, "Large icon"),
        spec!("iconPage", "--icon-page", Length, 32, "Page mark"),
        spec!(
            "controlHeight",
            "--control-height",
            Length,
            36,
            "Default control height"
        ),
        spec!(
            "controlHeightSmall",
            "--control-height-small",
            Length,
            30,
            "Compact control height"
        ),
        spec!(
            "topbarHeight",
            "--topbar-height",
            Length,
            56,
            "Top bar height"
        ),
        spec!(
            "statusbarHeight",
            "--statusbar-height",
            Length,
            32,
            "Status bar height"
        ),
        spec!(
            "sidebarWidth",
            "--sidebar-width",
            Length,
            256,
            "Expanded sidebar width"
        ),
        spec!(
            "sidebarCollapsedWidth",
            "--sidebar-collapsed-width",
            Length,
            64,
            "Collapsed sidebar width"
        ),
        spec!(
            "sidebarHeaderHeight",
            "--sidebar-header-height",
            Length,
            40,
            "Sidebar brand row height"
        ),
        spec!(
            "sidebarRowHeight",
            "--sidebar-row-height",
            Length,
            36,
            "Sidebar grid row height"
        ),
        spec!(
            "cardHeaderHeight",
            "--card-header-height",
            Length,
            48,
            "Card title row height"
        ),
        spec!(
            "cardMinWidth",
            "--card-min-width",
            Length,
            180,
            "Minimum card width"
        ),
        spec!(
            "cardMinHeight",
            "--card-min-height",
            Length,
            120,
            "Minimum card height"
        ),
        spec!(
            "menuItemHeight",
            "--menu-item-height",
            Length,
            36,
            "Menu row height"
        ),
        spec!(
            "menuMinWidth",
            "--menu-min-width",
            Length,
            220,
            "Minimum menu width"
        ),
        spec!(
            "menuMaxHeight",
            "--menu-max-height",
            Length,
            420,
            "Maximum menu height"
        ),
        spec!(
            "swatchSize",
            "--swatch-size",
            Length,
            16,
            "Colour swatch size"
        ),
        spec!(
            "keycapHeight",
            "--keycap-height",
            Length,
            22,
            "Keyboard keycap height"
        ),
        spec!(
            "switchWidth",
            "--switch-width",
            Length,
            40,
            "Toggle switch width"
        ),
        spec!(
            "switchHeight",
            "--switch-height",
            Length,
            24,
            "Toggle switch height"
        ),
        spec!(
            "switchThumb",
            "--switch-thumb",
            Length,
            18,
            "Toggle switch thumb size"
        ),
        spec!(
            "launcherMaxWidth",
            "--launcher-max-width",
            Length,
            680,
            "Launcher maximum width"
        ),
        spec!(
            "launcherHeight",
            "--launcher-height",
            Length,
            440,
            "Launcher height"
        ),
        spec!(
            "launcherTopMargin",
            "--launcher-top-margin",
            Length,
            96,
            "Launcher top offset"
        ),
        spec!(
            "minimapWidth",
            "--minimap-width",
            Length,
            176,
            "Minimap width"
        ),
        spec!(
            "minimapHeight",
            "--minimap-height",
            Length,
            112,
            "Minimap height"
        ),
        spec!(
            "gridStep",
            "--grid-step",
            Length,
            32,
            "Canvas snap and dot spacing"
        ),
        spec!(
            "gridDotSize",
            "--grid-dot-size",
            Number,
            1.1,
            "Canvas dot radius"
        ),
        spec!(
            "gridDotOpacity",
            "--grid-dot-opacity",
            Number,
            0.09,
            "Canvas dot opacity"
        ),
        spec!(
            "parallaxDistance",
            "--parallax-distance",
            Number,
            8,
            "Card parallax distance"
        ),
        spec!(
            "motionFast",
            "--motion-fast",
            Duration,
            110,
            "Fast transition (ms)"
        ),
        spec!(
            "motionNormal",
            "--motion-normal",
            Duration,
            140,
            "Normal transition (ms)"
        ),
        spec!(
            "motionSlow",
            "--motion-slow",
            Duration,
            180,
            "Slow transition (ms)"
        ),
        spec!(
            "motionSpawn",
            "--motion-spawn",
            Duration,
            180,
            "Card spawn animation (ms)"
        ),
        spec!(
            "motionRipple",
            "--motion-ripple",
            Duration,
            420,
            "Grid ripple animation (ms)"
        ),
        spec!(
            "easingStandard",
            "--easing-standard",
            Text,
            "OutCubic",
            "Standard easing curve"
        ),
        spec!(
            "opacityDisabled",
            "--opacity-disabled",
            Number,
            0.45,
            "Disabled control opacity"
        ),
        spec!(
            "opacityFaint",
            "--opacity-faint",
            Number,
            0.35,
            "Faint decoration opacity"
        ),
        spec!(
            "opacityMedium",
            "--opacity-medium",
            Number,
            0.6,
            "Medium decoration opacity"
        ),
        spec!(
            "shadowBlur",
            "--shadow-blur",
            Number,
            24,
            "Shadow blur radius"
        ),
        spec!(
            "shadowOffsetY",
            "--shadow-offset-y",
            Number,
            8,
            "Shadow vertical offset"
        ),
        spec!(
            "shadowOpacity",
            "--shadow-opacity",
            Number,
            0.25,
            "Shadow opacity"
        ),
    ]
});

pub fn specs() -> &'static [TokenSpec] {
    &SPECS
}

pub fn spec_map() -> BTreeMap<&'static str, &'static TokenSpec> {
    specs().iter().map(|s| (s.css, s)).collect()
}

pub fn default_tokens() -> Map<String, Value> {
    specs()
        .iter()
        .map(|s| (s.key.to_string(), s.default.clone()))
        .collect()
}

fn parse_hex(value: &str) -> Option<(u8, u8, u8, u8)> {
    // Internal color format follows QML: #AARRGGBB for translucent colors.
    let hex = value.trim().trim_start_matches('#');
    let expand = |c: char| -> Option<u8> { c.to_digit(16).map(|v| (v * 17) as u8) };
    match hex.len() {
        3 => {
            let mut it = hex.chars();
            Some((
                expand(it.next()?)?,
                expand(it.next()?)?,
                expand(it.next()?)?,
                255,
            ))
        }
        6 => Some((
            u8::from_str_radix(&hex[0..2], 16).ok()?,
            u8::from_str_radix(&hex[2..4], 16).ok()?,
            u8::from_str_radix(&hex[4..6], 16).ok()?,
            255,
        )),
        8 => Some((
            u8::from_str_radix(&hex[2..4], 16).ok()?,
            u8::from_str_radix(&hex[4..6], 16).ok()?,
            u8::from_str_radix(&hex[6..8], 16).ok()?,
            u8::from_str_radix(&hex[0..2], 16).ok()?,
        )),
        _ => None,
    }
}

fn css_hex_from_qml(value: &str) -> String {
    let Some((r, g, b, a)) = parse_hex(value) else {
        return value.to_string();
    };
    if a == 255 {
        format!("#{r:02x}{g:02x}{b:02x}")
    } else {
        format!("#{r:02x}{g:02x}{b:02x}{a:02x}")
    }
}

fn qml_hex(r: u8, g: u8, b: u8, a: u8) -> String {
    if a == 255 {
        format!("#{r:02x}{g:02x}{b:02x}")
    } else {
        format!("#{a:02x}{r:02x}{g:02x}{b:02x}")
    }
}

fn parse_css_color(value: &str) -> Result<String> {
    let raw = value.trim();
    if raw.eq_ignore_ascii_case("transparent") {
        return Ok("#00000000".into());
    }
    if raw.eq_ignore_ascii_case("white") {
        return Ok("#ffffff".into());
    }
    if raw.eq_ignore_ascii_case("black") {
        return Ok("#000000".into());
    }
    let css_hex = raw.trim().trim_start_matches('#');
    if css_hex.len() == 8 {
        let parse = |range: std::ops::Range<usize>| u8::from_str_radix(&css_hex[range], 16).ok();
        if let (Some(r), Some(g), Some(b), Some(a)) =
            (parse(0..2), parse(2..4), parse(4..6), parse(6..8))
        {
            return Ok(qml_hex(r, g, b, a));
        }
    }
    if css_hex.len() == 4 {
        let expand = |c: char| -> Option<u8> { c.to_digit(16).map(|v| (v * 17) as u8) };
        let mut it = css_hex.chars();
        if let (Some(r), Some(g), Some(b), Some(a)) = (
            expand(it.next().unwrap_or('0')),
            expand(it.next().unwrap_or('0')),
            expand(it.next().unwrap_or('0')),
            expand(it.next().unwrap_or('0')),
        ) {
            return Ok(qml_hex(r, g, b, a));
        }
    }
    if let Some((r, g, b, a)) = parse_hex(raw) {
        return Ok(qml_hex(r, g, b, a));
    }
    let lower = raw.to_ascii_lowercase();
    if lower.starts_with("rgb(") || lower.starts_with("rgba(") {
        let body = lower
            .split_once('(')
            .and_then(|(_, rest)| rest.split_once(')'))
            .map(|(body, _)| body)
            .unwrap_or("");
        let parts: Vec<&str> = body.split(',').map(str::trim).collect();
        if parts.len() == 3 || parts.len() == 4 {
            let channel = |s: &str| -> Result<u8> {
                let n: f64 = s
                    .trim_end_matches('%')
                    .parse()
                    .context("invalid rgb channel")?;
                let n = if s.contains('%') { n * 2.55 } else { n };
                Ok(n.round().clamp(0.0, 255.0) as u8)
            };
            let alpha = if parts.len() == 4 {
                let n: f64 = parts[3]
                    .trim_end_matches('%')
                    .parse()
                    .context("invalid alpha")?;
                let n = if parts[3].contains('%') { n / 100.0 } else { n };
                (n.clamp(0.0, 1.0) * 255.0).round() as u8
            } else {
                255
            };
            return Ok(qml_hex(
                channel(parts[0])?,
                channel(parts[1])?,
                channel(parts[2])?,
                alpha,
            ));
        }
    }
    bail!("invalid color `{raw}`")
}

fn color_luminance(hex: &str) -> f64 {
    fn ch(c: u8) -> f64 {
        let c = c as f64 / 255.0;
        if c <= 0.04045 {
            c / 12.92
        } else {
            ((c + 0.055) / 1.055).powf(2.4)
        }
    }
    let Some((r, g, b, _)) = parse_hex(hex) else {
        return 0.0;
    };
    0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
}

fn contrast(a: &str, b: &str) -> f64 {
    let (la, lb) = (color_luminance(a), color_luminance(b));
    let (hi, lo) = if la > lb { (la, lb) } else { (lb, la) };
    (hi + 0.05) / (lo + 0.05)
}

fn darken(hex: &str, factor: f64) -> String {
    let Some((r, g, b, a)) = parse_hex(hex) else {
        return hex.into();
    };
    let f = |c: u8| ((c as f64) / factor).round().clamp(0.0, 255.0) as u8;
    qml_hex(f(r), f(g), f(b), a)
}

fn lighten(hex: &str, factor: f64) -> String {
    let Some((r, g, b, a)) = parse_hex(hex) else {
        return hex.into();
    };
    let f = |c: u8| ((c as f64) * factor).round().clamp(0.0, 255.0) as u8;
    qml_hex(f(r), f(g), f(b), a)
}

fn with_alpha(hex: &str, alpha: f64) -> String {
    let Some((r, g, b, _)) = parse_hex(hex) else {
        return hex.into();
    };
    let a = (alpha.clamp(0.0, 1.0) * 255.0).round() as u8;
    qml_hex(r, g, b, a)
}

#[derive(Clone, Debug)]
pub struct ThemeEntry {
    pub id: String,
    pub name: String,
    pub light: bool,
    pub builtin: bool,
    pub source: String,
    pub tokens: Map<String, Value>,
}

impl ThemeEntry {
    pub fn to_json(&self) -> Value {
        let mut tokens = Map::new();
        for (k, v) in &self.tokens {
            tokens.insert(k.clone(), v.clone());
        }
        json!({
            "id": self.id,
            "name": self.name,
            "light": self.light,
            "builtin": self.builtin,
            "source": self.source,
            "bg": self.tokens.get("bg").cloned().unwrap_or(json!("#121417")),
            "surface": self.tokens.get("surface").cloned().unwrap_or(json!("#1b1e23")),
            "accent": self.tokens.get("accent").cloned().unwrap_or(json!("#d98e5c")),
            "text": self.tokens.get("text").cloned().unwrap_or(json!("#ece7de")),
            "tokens": tokens
        })
    }
}

pub fn build_tokens(
    bg: &str,
    surface: &str,
    accent: &str,
    text: &str,
    light: bool,
    font: &str,
) -> Map<String, Value> {
    let mut tokens = default_tokens();
    let mut set = |key: &str, value: Value| {
        tokens.insert(key.to_string(), value);
    };
    set("bg", json!(bg));
    set("surface", json!(surface));
    set(
        "sidebar",
        json!(if light {
            darken(bg, 1.03)
        } else {
            lighten(bg, 1.12)
        }),
    );
    set(
        "card",
        json!(if light {
            darken(surface, 1.02)
        } else {
            lighten(surface, 1.10)
        }),
    );
    set(
        "surfaceStrong",
        json!(if light {
            darken(surface, 1.06)
        } else {
            lighten(surface, 1.28)
        }),
    );
    set(
        "menu",
        json!(if light {
            darken(surface, 1.02)
        } else {
            lighten(surface, 1.18)
        }),
    );
    set(
        "input",
        json!(with_alpha(text, if light { 0.04 } else { 0.05 })),
    );
    set(
        "hover",
        json!(with_alpha(text, if light { 0.05 } else { 0.06 })),
    );
    set(
        "border",
        json!(with_alpha(text, if light { 0.10 } else { 0.09 })),
    );
    set(
        "borderStrong",
        json!(with_alpha(text, if light { 0.18 } else { 0.16 })),
    );
    set("text", json!(text));
    set(
        "text2",
        json!(with_alpha(text, if light { 0.80 } else { 0.86 })),
    );
    set(
        "muted",
        json!(with_alpha(text, if light { 0.72 } else { 0.66 })),
    );
    set("accent", json!(accent));
    let dark_ink = "#171717";
    let light_ink = "#f7f4ec";
    let best = if contrast(accent, dark_ink) >= contrast(accent, light_ink) {
        dark_ink
    } else {
        light_ink
    };
    let mut button = accent.to_string();
    if contrast(accent, best) < 4.5 {
        button = if best == dark_ink {
            lighten(accent, 1.2)
        } else {
            darken(accent, 1.2)
        };
    }
    set("accentButton", json!(button));
    set(
        "accentText",
        json!(if light {
            darken(accent, 1.3)
        } else {
            lighten(accent, 1.15)
        }),
    );
    set("accentInk", json!(best));
    set("danger", json!(if light { "#b3261e" } else { "#d97a72" }));
    set("success", json!(if light { "#2e7d32" } else { "#7fae83" }));
    set("selection", json!(with_alpha(accent, 0.35)));
    set("focus", json!(accent));
    set("calendarToday", json!(with_alpha(accent, 0.16)));
    set("fontFamily", json!(font));
    tokens
}

pub fn builtin_entries() -> Vec<ThemeEntry> {
    let value = model::themes();
    let mut out = Vec::new();
    if let Some(items) = value.as_array() {
        for item in items {
            let id = item["id"].as_str().unwrap_or_default().to_string();
            let name = item["name"].as_str().unwrap_or(&id).to_string();
            let light = item["light"].as_bool().unwrap_or(false);
            let bg = item["bg"].as_str().unwrap_or("#121417");
            let surface = item["surface"].as_str().unwrap_or("#1b1e23");
            let accent = item["accent"].as_str().unwrap_or("#d98e5c");
            let text = item["text"].as_str().unwrap_or("#ece7de");
            out.push(ThemeEntry {
                id,
                name,
                light,
                builtin: item["builtin"].as_bool().unwrap_or(false),
                source: "builtin".into(),
                tokens: build_tokens(bg, surface, accent, text, light, "Inter"),
            });
        }
    }
    out
}

fn strip_comments(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    let mut in_comment = false;
    while let Some(c) = chars.next() {
        if in_comment {
            if c == '*' && chars.peek() == Some(&'/') {
                chars.next();
                in_comment = false;
            }
        } else if c == '/' && chars.peek() == Some(&'*') {
            chars.next();
            in_comment = true;
        } else {
            out.push(c);
        }
    }
    out
}

fn parse_number(value: &str, kind: TokenKind) -> Result<Value> {
    let raw = value.trim();
    let cleaned = raw
        .trim_end_matches("px")
        .trim_end_matches("ms")
        .trim_end_matches('%')
        .trim();
    let n: f64 = cleaned
        .parse()
        .with_context(|| format!("invalid number `{raw}`"))?;
    if !n.is_finite() {
        bail!("number must be finite");
    }
    match kind {
        TokenKind::Integer => Ok(json!(n.round() as i64)),
        TokenKind::Length | TokenKind::Number | TokenKind::Duration => Ok(json!(n)),
        _ => bail!("not a number token"),
    }
}

pub fn parse_css_theme(text: &str, fallback_id: &str) -> Result<ThemeEntry> {
    let clean = strip_comments(text);
    let mut declarations: BTreeMap<String, String> = BTreeMap::new();
    let mut found_root = false;
    let mut rest = clean.as_str();
    while let Some(pos) = rest.find(":root") {
        found_root = true;
        rest = &rest[pos + 5..];
        let Some(open) = rest.find('{') else { break };
        let Some(close) = rest[open + 1..].find('}') else {
            break;
        };
        let body = &rest[open + 1..open + 1 + close];
        for decl in body.split(';') {
            let Some((key, value)) = decl.split_once(':') else {
                continue;
            };
            let key = key.trim();
            if !key.starts_with("--") {
                continue;
            }
            declarations.insert(key.to_string(), value.trim().to_string());
        }
        rest = &rest[open + 1 + close + 1..];
    }
    if !found_root {
        bail!("theme CSS needs a :root rule");
    }

    let meta = |name: &str| declarations.get(name).cloned().unwrap_or_default();
    let id = {
        let v = meta("--theme-id");
        if v.is_empty() {
            fallback_id.to_string()
        } else {
            v.trim_matches('"').to_string()
        }
    };
    if id.is_empty()
        || !id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    {
        bail!("theme id must contain only letters, numbers, '-' or '_'");
    }
    let name = {
        let v = meta("--theme-name");
        let v = v.trim_matches('"');
        if v.is_empty() {
            id.clone()
        } else {
            v.to_string()
        }
    };
    let light = match meta("--theme-light").to_ascii_lowercase().as_str() {
        "true" | "yes" | "1" => true,
        "false" | "no" | "0" | "" => false,
        other => bail!("--theme-light must be true or false, got `{other}`"),
    };

    let mut tokens = default_tokens();
    for value in declarations.values() {
        let _ = value;
    }
    let known: BTreeMap<&str, &TokenSpec> = spec_map();
    for (css, value) in &declarations {
        if matches!(
            css.as_str(),
            "--theme-id" | "--theme-name" | "--theme-light"
        ) {
            continue;
        }
        let Some(spec) = known.get(css.as_str()) else {
            bail!("unknown theme token `{css}`");
        };
        let parsed = match spec.kind {
            TokenKind::Color => json!(parse_css_color(value)?),
            TokenKind::Length | TokenKind::Number | TokenKind::Integer | TokenKind::Duration => {
                parse_number(value, spec.kind)?
            }
            TokenKind::Text => json!(value.trim_matches('"').trim_matches('\'')),
        };
        tokens.insert(spec.key.to_string(), parsed);
    }
    Ok(ThemeEntry {
        id,
        name,
        light,
        builtin: false,
        source: "css".into(),
        tokens,
    })
}

pub fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

pub fn themes_dir(data_dir: &Path) -> PathBuf {
    data_dir.join("themes")
}

pub fn load_css_themes(data_dir: &Path) -> Vec<ThemeEntry> {
    let dir = themes_dir(data_dir);
    let Ok(read) = std::fs::read_dir(&dir) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for entry in read.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("css") {
            continue;
        }
        let fallback = path.file_stem().and_then(|s| s.to_str()).unwrap_or("theme");
        match std::fs::read_to_string(&path)
            .map_err(|e| anyhow!(e))
            .and_then(|text| parse_css_theme(&text, fallback))
        {
            Ok(mut theme) => {
                theme.source = path.display().to_string();
                out.push(theme);
            }
            Err(err) => tracing::warn!("theme {}: {err}", path.display()),
        }
    }
    out.sort_by_key(|t| t.name.to_lowercase());
    out
}

pub fn all_themes(data_dir: &Path) -> Vec<ThemeEntry> {
    let mut out = builtin_entries();
    out.extend(load_css_themes(data_dir));
    out
}

pub fn themes_json(data_dir: &Path) -> Value {
    Value::Array(
        all_themes(data_dir)
            .iter()
            .map(ThemeEntry::to_json)
            .collect(),
    )
}

pub fn theme_exists(data_dir: &Path, id: &str) -> bool {
    all_themes(data_dir).iter().any(|t| t.id == id)
}

pub fn write_css_theme(data_dir: &Path, entry: &ThemeEntry) -> Result<PathBuf> {
    std::fs::create_dir_all(themes_dir(data_dir))?;
    let path = themes_dir(data_dir).join(format!("{}.css", entry.id));
    let text = css_from_entry(entry);
    std::fs::write(&path, text)?;
    Ok(path)
}

pub fn css_from_entry(entry: &ThemeEntry) -> String {
    let mut out = String::new();
    out.push_str("/* Corcho CSS theme. */\n:root {\n");
    out.push_str(&format!("  --theme-id: {};\n", entry.id));
    out.push_str(&format!("  --theme-name: {};\n", entry.name));
    out.push_str(&format!("  --theme-light: {};\n", entry.light));
    for spec in specs() {
        let value = entry
            .tokens
            .get(spec.key)
            .cloned()
            .unwrap_or_else(|| spec.default.clone());
        let text = match spec.kind {
            TokenKind::Color => css_hex_from_qml(value.as_str().unwrap_or("#000000")),
            TokenKind::Length => format!("{}px", value.as_f64().unwrap_or(0.0)),
            TokenKind::Duration => format!("{}ms", value.as_i64().unwrap_or(0)),
            TokenKind::Number | TokenKind::Integer => value.to_string(),
            TokenKind::Text => value.as_str().unwrap_or("").to_string(),
        };
        out.push_str(&format!("  {}: {};\n", spec.css, text));
    }
    out.push_str("}\n");
    out
}

pub const TEMPLATE: &str = include_str!("../themes/template.css");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn template_contains_every_token() {
        for spec in specs() {
            assert!(
                TEMPLATE.contains(spec.css),
                "missing {} in themes/template.css",
                spec.css
            );
        }
        let parsed = parse_css_theme(TEMPLATE, "my-theme").unwrap();
        for spec in specs() {
            assert!(
                parsed.tokens.contains_key(spec.key),
                "{} not parsed from template",
                spec.key
            );
        }
    }

    #[test]
    fn css_parser_accepts_colors_and_units() {
        let css = r#"
            :root {
              --theme-id: test;
              --theme-name: Test;
              --theme-light: true;
              --bg: #f7f4ee;
              --text: rgba(31, 27, 22, 1);
              --space-3: 12px;
              --motion-fast: 110ms;
              --opacity-medium: 0.6;
              --font-family: Inter;
            }
        "#;
        let theme = parse_css_theme(css, "fallback").unwrap();
        assert_eq!(theme.id, "test");
        assert!(theme.light);
        assert_eq!(theme.tokens["bg"], "#f7f4ee");
        assert_eq!(theme.tokens["space3"], 12.0);
        assert_eq!(theme.tokens["motionFast"], 110.0);
        assert_eq!(theme.tokens["opacityMedium"], 0.6);
        assert_eq!(theme.tokens["fontFamily"], "Inter");
    }

    #[test]
    fn theme_ids_cannot_escape_themes_dir() {
        assert!(valid_id("paper"));
        assert!(valid_id("my-theme_2"));
        assert!(!valid_id("../paper"));
        assert!(!valid_id("a/b"));
        assert!(!valid_id(""));
    }

    #[test]
    fn css_parser_rejects_unknown_tokens() {
        let css = ":root { --theme-id: bad; --not-a-token: 1; }";
        assert!(parse_css_theme(css, "bad").is_err());
    }

    #[test]
    fn qml_references_only_registered_tokens() {
        let known: std::collections::BTreeSet<&str> = specs().iter().map(|s| s.key).collect();
        for entry in std::fs::read_dir("qml").unwrap().flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("qml") {
                continue;
            }
            let text = std::fs::read_to_string(&path).unwrap();
            for line in text.lines() {
                let mut rest = line;
                while let Some(pos) = rest.find("root.th.") {
                    rest = &rest[pos + 8..];
                    let key: String = rest
                        .chars()
                        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                        .collect();
                    if key.is_empty() {
                        continue;
                    }
                    assert!(
                        known.contains(key.as_str()),
                        "{} uses unknown theme token `{}`",
                        path.display(),
                        key
                    );
                }
            }
        }
    }

    #[test]
    fn builtin_themes_have_all_tokens() {
        for theme in builtin_entries() {
            for spec in specs() {
                assert!(
                    theme.tokens.contains_key(spec.key),
                    "{} missing {}",
                    theme.id,
                    spec.key
                );
            }
        }
    }
}
