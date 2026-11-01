# Accessibility and color grading

## Targets

| Role | Requirement | Corcho value |
| --- | --- | --- |
| Body text | WCAG AA 4.5:1, APCA Lc 75+ | `text` on every surface |
| Secondary text | WCAG AA 4.5:1 | `text2` |
| Muted text | WCAG AA 4.5:1 at 13 px | `muted` |
| Large text | WCAG AA 3:1, APCA Lc 45 | titles |
| UI borders / focus ring / icons | WCAG 3:1 non-text | `borderStrong`, `accent` |
| Placeholder / disabled | APCA Lc 30 minimum | 45–55% of text on ink |

## Palette

Two base neutrals and one distinct accent (60-30-10):

- ink `#121417` (60%)
- paper `#ECE7DE` text and light surfaces (30%)
- ember `#D98E5C` accent (10%)

Accent text uses `accentInk` chosen by relative luminance, so both dark and
light themes keep ≥ 4.5:1.

## Themes

All 19 themes are generated from the same `buildTheme` function in
`qml/Main.qml`; it derives surfaces, hover, borders, text2 and muted from the
base pair. Light themes use darker muted/text2 values; dark themes use lighter
ones. The High Contrast theme is the fallback for low-vision users.

## Focus and keyboard

- Every button, field, toggle, select and menu row is tab-reachable.
- Focus is a 1.5–2 px ember ring, not a glow.
- Space/Return activates buttons, toggles and selects.
- Escape closes overlays; Ctrl+K opens the Powerbar; Ctrl+Z/Y undo/redo.

## Screen readers

Interactive elements expose `Accessible.role`, `Accessible.name` and, where
relevant, `Accessible.checked` / `Accessible.description`. Icons are marked
`Accessible.ignored` so they do not add noise.

## Motion

`Reduced motion` (Settings → Appearance) disables card spawn, canvas ripple,
fragment animation and audio-reactive motion. Fragment audio can still play.

## Research

- WCAG 2.1 SC 1.4.3 Contrast (Minimum), W3C WAI.
- APCA, *The Easy Intro to the APCA Contrast Method*, Myndex.
- 60-30-10 color rule and “two neutrals + one accent” guidance.
