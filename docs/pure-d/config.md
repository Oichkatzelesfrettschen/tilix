# Pure D Config (pure-d.json)

Location:
- `$XDG_CONFIG_HOME/tilix/pure-d.json`
- Defaults to `~/.config/tilix/pure-d.json`

```json
{
  "fontPath": "",
  "fontSize": 16,
  "windowWidth": 1280,
  "windowHeight": 720,
  "scrollbackMaxLines": 200000,
  "swapInterval": 0,
  "themePath": "",
  "themeFormat": "",
  "cursorStyle": "outline",
  "cursorThickness": 2.0,
  "accessibilityPreset": "",
  "selectionBg": [0.2, 0.6, 0.8, 1.0],
  "selectionFg": [0.0, 0.0, 0.0, 1.0],
  "searchBg": [0.85, 0.7, 0.2, 1.0],
  "searchFg": [0.0, 0.0, 0.0, 1.0],
  "linkFg": [0.2, 0.6, 1.0, 1.0],
  "theme": {
    "foreground": [0.9, 0.9, 0.9, 1.0],
    "background": [0.1, 0.1, 0.15, 1.0],
    "palette": [
      [0.0, 0.0, 0.0, 1.0],
      [0.8, 0.0, 0.0, 1.0],
      [0.0, 0.8, 0.0, 1.0],
      [0.8, 0.8, 0.0, 1.0],
      [0.0, 0.0, 0.8, 1.0],
      [0.8, 0.0, 0.8, 1.0],
      [0.0, 0.8, 0.8, 1.0],
      [0.75, 0.75, 0.75, 1.0],
      [0.5, 0.5, 0.5, 1.0],
      [1.0, 0.0, 0.0, 1.0],      [0.0, 1.0, 0.0, 1.0],
      [1.0, 1.0, 0.0, 1.0],
      [0.0, 0.0, 1.0, 1.0],
      [1.0, 0.0, 1.0, 1.0],
      [0.0, 1.0, 1.0, 1.0],
      [1.0, 1.0, 1.0, 1.0]
    ]
  }
}
```

Notes:
- `swapInterval`: 0 = uncapped, 1 = vsync.
- `palette` requires 16 entries (RGBA, 0.0 to 1.0).
- Invalid or missing config falls back to defaults.
- Changes are polled every ~250ms and applied live.
- If `themePath` is set, it overrides the inline `theme` block.
- `themeFormat` supports `xresources` and `alacritty` (auto-detected by extension).
- `cursorStyle`: `block`, `underline`, `bar`, or `outline` (block outline).
- `cursorThickness`: pixels at 1x scale (0 uses adaptive thickness).
- `accessibilityPreset`: `high-contrast` or `low-vision`. Presets only fill unset fields.
- `selectionBg`: RGBA highlight color (0.0 to 1.0, clamped).
- `selectionFg`: RGBA selection text color (0.0 to 1.0, clamped). Defaults to high-contrast black/white based on `selectionBg`.
- `searchBg`: RGBA search highlight color (0.0 to 1.0, clamped).
- `searchFg`: RGBA search text color (0.0 to 1.0, clamped). Defaults to high-contrast black/white based on `searchBg`.
- `linkFg`: RGBA hyperlink foreground color (0.0 to 1.0, clamped).

Schema:
- `docs/pure-d/config.schema.json` (JSON Schema draft 2020-12).
- `docs/pure-d/theme-presets.md` (sample high-contrast palette).

Accessibility presets (example):
```json
{
  "accessibilityPreset": "high-contrast",
  "cursorStyle": "outline",
  "cursorThickness": 2.0
}
```

Key bindings (Pure D backend):
- `Ctrl+Shift+F` uses the current selection as search query.
- `F3` jumps to the next match, `Shift+F3` to the previous match.
