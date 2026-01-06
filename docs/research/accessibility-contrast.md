# Accessibility Contrast References (Pure D)

Sources
- WCAG 2.1 Understanding Non-text Contrast (UI components and states should be >= 3:1 against adjacent colors): https://www.w3.org/WAI/WCAG21/Understanding/non-text-contrast.html
- WCAG 2.1 Understanding Contrast (Minimum) (text should be >= 4.5:1; large text >= 3:1): https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html

Application to Pure D
- Selection highlight is treated as a UI state, so the default highlight target is >= 3:1 against the default background.
- Selected text remains readable by auto-selecting a high-contrast black/white foreground when `selectionFg` is not explicitly set.
- Accessibility presets now expose `high-contrast` and `low-vision` defaults for cursor/selection/search colors.
