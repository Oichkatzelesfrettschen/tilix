# Pure D Accessibility Notes

These notes guide cursor and selection visibility for the Pure D backend.

## Contrast targets
- Cursor, selection, and focus indicators are UI components.
- Target >= 3:1 contrast between the indicator and adjacent background.
- For keyboard focus indicators, WCAG 2.2 suggests a visible perimeter of
  at least 2px with >= 3:1 contrast between focused and unfocused states.

## Recommendations
- Prefer `cursorStyle` "outline" (or "block-outline") with `cursorThickness`
  >= 2.0 for low-vision visibility.
- Avoid translucent selection colors that drop below 3:1 contrast.
- Use the built-in `high-contrast` or `low-vision` presets as baselines,
  then tune per theme.

## Preset examples
```json
{
  "accessibilityPreset": "high-contrast",
  "cursorStyle": "outline",
  "cursorThickness": 2.0
}
```

```json
{
  "accessibilityPreset": "low-vision",
  "cursorStyle": "outline",
  "cursorThickness": 3.0
}
```

## References
- https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html
- https://www.w3.org/WAI/WCAG22/Understanding/focus-appearance-minimum.html
