# CSS themes

Corcho themes are CSS custom-property files. QML has no CSS selector engine, so a
theme file is a token sheet, not a stylesheet: every visual value is a variable
in `:root`, and the app maps those variables onto its Qt/QML components.

## Where themes live

- User themes: `<data>/themes/*.css`
- Linux default: `~/.local/share/corcho/themes/`
- Template: `themes/template.css` in the source tree, also available from the
  `theme.css.template` MCP tool.
- Settings → Appearance → **CSS themes** has **Folder** and **Template**
  buttons.

The template is the authoritative list of every token. If a token is not in the
template, it is not themeable yet.

## Format

```css
:root {
  --theme-id: dusk;
  --theme-name: Dusk;
  --theme-light: false;

  --bg: #121417;
  --surface: #1b1e23;
  --text: #ece7de;
  --accent: #d98e5c;

  --space-3: 12px;
  --radius-card: 14px;
  --font-size-body: 14px;
  --motion-fast: 110ms;
  --opacity-muted: 0.72;
}
```

Metadata:

- `--theme-id`: file-safe id used by settings and MCP. It must match the
  requested id when using `theme.css.set`.
- `--theme-name`: label shown in Appearance.
- `--theme-light`: `true` or `false`, used to group the theme in the Light or
  Dark selector.

Colors accept CSS hex (`#rgb`, `#rrggbb`, `#rrggbbaa`), `rgb()`, `rgba()`,
`transparent`, `white`, and `black`. Lengths use `px`; durations use `ms`.
Missing tokens fall back to the built-in defaults, but the template includes
every token and is the recommended starting point.

## Tokens

The categories are:

- palette: background, surfaces, cards, menus, text, accent, borders, states;
- typography: families, sizes, weights, line heights;
- spacing, radii, border widths;
- icon and control sizes;
- layout: top bar, status bar, sidebar, card, menu, launcher, minimap;
- motion and easing;
- opacity, shadow, grid, and parallax values.

See `themes/template.css` for the complete annotated table.

CSS themes control visual styling. User preferences such as `theme_mode`,
`reduced_motion`, spawn animations, parallax, and font choice remain settings,
not theme tokens.

## MCP

| Tool | Purpose |
| --- | --- |
| `theme.css.template` | Return the complete CSS template |
| `theme.css.get` | Read a user theme |
| `theme.css.set` | Validate and create/update a theme |
| `theme.css.delete` | Delete a user theme |
| `theme.list` | List built-in and CSS themes |
| `theme.set` | Assign a theme to the light or dark slot |

Example:

```json
{"name":"theme.css.set","arguments":{"themeId":"dusk","css":":root{--theme-id:dusk;--theme-name:Dusk;--theme-light:false;--bg:#111;}"}}
```

The running GUI watches the themes directory and reloads changed CSS themes
without a restart.
