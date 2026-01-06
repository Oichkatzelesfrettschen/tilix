# IME and Key Repeat Strategy (Pure D)

Sources:
- GLFW Input Guide (keyboard input and key repeat): https://www.glfw.org/docs/latest/input_guide.html#input_keyboard

## Current behavior
- Key events (`GLFW_PRESS`/`GLFW_REPEAT`) drive special keys and navigation (`pured/platform/input.d`).
- Character events (`glfwSetCharCallback`) drive text input (`pured/main.d`).
- Alt sends ESC prefix when enabled.
- No IME preedit/composition overlay; no input method integration beyond GLFW callbacks.

## GLFW constraints
- GLFW separates key events from character events; a single key press may yield multiple characters, and input method behavior varies by layout/IME.
- `GLFW_REPEAT` is generated at the OS key-repeat rate and is best treated as a convenience for navigation, not text composition.

## Strategy (Pure D)
- Continue to route printable text through char callbacks; keep key callbacks for non-text controls.
- Treat `GLFW_REPEAT` as navigation repeat only; avoid duplicating text on repeat.
- Add IME integration per backend:
  - X11: integrate XIM/IBus/FCITX for preedit + candidate windows.
  - Wayland: use text-input protocol or an IME helper if available.
- Render preedit text as an overlay line with underline + cursor box; commit on IME finalize.

## Tracking gaps
- No IME preedit display or composition buffers yet.
- No API to forward IME candidate updates to renderer.
- No per-platform abstraction in `pured/platform/` for IME.

## Next actions
- Define `ImeState` struct and callbacks in `pured/platform`.
- Add renderer overlay pass for preedit string.
- Implement X11 IME adapter behind feature flag.
- Document key repeat vs text composition in user docs.
