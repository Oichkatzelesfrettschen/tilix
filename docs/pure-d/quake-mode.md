# Pure D Quake Mode

Quake mode creates a drop-down terminal window that is borderless,
anchored to the top of the primary monitor, and sized by `quakeHeight`.

Implementation notes:
- Uses GLFW window hints via `GLFW_FLOATING` and `GLFW_DECORATED`.
- Uses monitor work area for sizing; falls back to full video mode.
- The Pure D backend currently relies on GLFW for X11/Wayland hints.

Future improvements (optional):
- X11 EWMH hints (`_NET_WM_STATE_ABOVE`, `_NET_WM_STATE_STICKY`) via xcb-d.
- Wayland layer-shell integration (if a native Wayland backend is added).
