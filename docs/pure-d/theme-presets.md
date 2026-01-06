# Pure D Theme Presets

High-contrast (dark background):
```json
{
  "theme": {
    "foreground": [1.0, 1.0, 1.0, 1.0],
    "background": [0.0, 0.0, 0.0, 1.0],
    "palette": [
      [0.0, 0.0, 0.0, 1.0],
      [0.8, 0.0, 0.0, 1.0],
      [0.0, 0.8, 0.0, 1.0],
      [0.8, 0.8, 0.0, 1.0],
      [0.0, 0.0, 0.8, 1.0],
      [0.8, 0.0, 0.8, 1.0],
      [0.0, 0.8, 0.8, 1.0],
      [0.9, 0.9, 0.9, 1.0],
      [0.3, 0.3, 0.3, 1.0],
      [1.0, 0.2, 0.2, 1.0],
      [0.2, 1.0, 0.2, 1.0],
      [1.0, 1.0, 0.2, 1.0],
      [0.2, 0.2, 1.0, 1.0],
      [1.0, 0.2, 1.0, 1.0],
      [0.2, 1.0, 1.0, 1.0],
      [1.0, 1.0, 1.0, 1.0]
    ]
  }
}
```
Notes:
- Use this as the `theme` block in `pure-d.json`, or save as a file and set `themePath` + `themeFormat`.
- Palette entries map to ANSI 0-15.
