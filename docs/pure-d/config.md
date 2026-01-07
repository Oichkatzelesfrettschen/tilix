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
  "quakeMode": false,
  "quakeHeight": 0.4,
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
  "splitLayout": {
    "rootPaneId": 1,
    "activePaneId": 0,
    "nodes": [
      { "paneId": 1, "first": 0, "second": 2, "orientation": "vertical", "splitRatio": 0.5 },
      { "paneId": 0, "first": -1, "second": -1, "orientation": "", "splitRatio": 0.5 },
      { "paneId": 2, "first": -1, "second": -1, "orientation": "", "splitRatio": 0.5 }
    ]
  },
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
- `quakeMode`: enable drop-down terminal behavior (borderless, top-aligned).
- `quakeHeight`: height fraction (0.1 to 1.0) used when `quakeMode` is true.
- Quake mode details: `docs/pure-d/quake-mode.md`.
- `palette` requires 16 entries (RGBA, 0.0 to 1.0).
- Invalid or missing config falls back to defaults.
- Unknown keys are ignored with a warning.
- Changes are polled every ~250ms and applied live.
- If `themePath` is set, it overrides the inline `theme` block.
- `themeFormat` supports `xresources` and `alacritty` (auto-detected by extension).
- `cursorStyle`: `block`, `underline`, `bar`, or `outline` (alias `block-outline`).
- `cursorThickness`: pixels at 1x scale (0 uses adaptive thickness).
- `accessibilityPreset`: `high-contrast` or `low-vision`. Presets only fill unset fields.
- `selectionBg`: RGBA highlight color (0.0 to 1.0, clamped).
- `selectionBg` alpha blends with the underlying cell background.
- `selectionFg`: RGBA selection text color (0.0 to 1.0, clamped). Defaults to high-contrast black/white based on `selectionBg`.
- `searchBg`: RGBA search highlight color (0.0 to 1.0, clamped).
- `searchFg`: RGBA search text color (0.0 to 1.0, clamped). Defaults to high-contrast black/white based on `searchBg`.
- `linkFg`: RGBA hyperlink foreground color (0.0 to 1.0, clamped).
- Accessibility guidance: `docs/pure-d/accessibility.md`.
- `splitLayout`: optional split tree snapshot used to restore panes and ratios.
- `splitLayout.rootPaneId`: internal root node id.
- `splitLayout.activePaneId`: active leaf pane to focus on startup.
- `splitLayout.nodes`: array of nodes with `first`/`second` set to `-1` for leaf panes.

Schema:
- `docs/pure-d/config.schema.json` (JSON Schema draft 2020-12).
- `docs/pure-d/theme-presets.md` (sample high-contrast palette).

Validation:
- `scripts/pure-d/validate_config.sh` (uses Python `jsonschema`).
- Defaults to `$XDG_CONFIG_HOME/tilix/pure-d.json` when no path is provided.
- Sample config for CI/test matrix: `docs/pure-d/sample-config.json`.

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
