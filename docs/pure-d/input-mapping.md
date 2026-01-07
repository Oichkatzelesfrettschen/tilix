# Pure D Input Mapping (Parity Audit)

Scope: compares Pure D GLFW input translation against Tilix/VTE defaults.
Sources: `pured/platform/input.d`, `pured/main.d`, `data/gsettings/com.gexperts.Tilix.gschema.xml`.

## Terminal escape sequences (PTY input)
- Arrow keys: CSI A/B/C/D; with modifiers uses CSI 1;{mod} A/B/C/D.
- Home/End: CSI H/F (modded uses CSI 1;{mod} H/F).
- Insert/Delete/PageUp/PageDown: CSI 2~/3~/5~/6~ (modded uses CSI {n};{mod}~).
- Function keys: F1-F4 use SS3 P/Q/R/S; F5-F12 use CSI 15~..24~; F13-F20 use CSI 25~..34~ (modded uses CSI {n};{mod}~).
- Tab: HT; Shift+Tab: CSI Z.
- Enter: CR; Backspace: DEL (0x7f); Escape: ESC.
- Ctrl combos: Ctrl+A..Z -> ASCII 1..26; Ctrl+[ -> ESC; Ctrl+\ -> FS (28); Ctrl+] -> GS (29); Ctrl+6 -> RS (30); Ctrl+- -> US (31); Ctrl+Space -> NUL.
- Alt sends ESC prefix for Unicode input.
- Keypad digits/operators honor application keypad mode (SS3 p-y for 0-9, SS3 j/k/m/o/n/X for */-+/./=, SS3 M for KP Enter).

## Mouse reporting
- Modes: X10 (press), normal (press/release), button-event (motion while pressed), any-event (all motion).
- Encodings: X10, UTF-8, SGR, URxvt.
- Focus in/out sequences: CSI I / CSI O when focus reporting enabled.
- Bracketed paste: CSI 200~ / CSI 201~.

Parity notes:
- Matches xterm encodings for X10/UTF-8/SGR/URxvt.
- Focus reporting is wired via emulator mode flags.
- Selection is suppressed while mouse reporting is active (no drag selection in that mode).

## App-level shortcuts in Pure D
- Ctrl+Q: close window.
- Ctrl+Shift+F: open search prompt (prefilled with selection/last query).
- Enter confirms search, Esc cancels, Backspace edits prompt.
- F3 / Shift+F3: next/previous search hit.
- Shift+PageUp/Down/Home/End: scrollback navigation.
- Ctrl+Shift+N: new window (spawns new instance).
- Ctrl+Shift+Q: close active tab.
- Ctrl+Shift+C: copy selection.
- Ctrl+Shift+V or Shift+Insert: paste clipboard.
- Ctrl+Click: open hyperlink (selection/cursor unaffected).
- Middle click: paste PRIMARY when mouse reporting is off.
- Ctrl+Shift+E: split horizontally.
- Ctrl+Shift+O: split vertically.
- Ctrl+Shift+Alt+Arrows: resize active split.
- Alt+drag split boundary: resize split with mouse.
- Ctrl+Tab / Ctrl+Shift+Tab: cycle panes.
- Ctrl+Shift+T: new tab (Pure D scenegraph tab).
- Ctrl+PageUp / Ctrl+PageDown: previous/next tab.

## Tilix default shortcut parity (gsettings baseline)
| Action | Tilix default | Pure D status |
| --- | --- | --- |
| New window | Ctrl+Shift+N | implemented (spawns new instance) |
| New session/tab | Ctrl+Shift+T | implemented (scenegraph tab) |
| Close session | Ctrl+Shift+Q | implemented (closes active tab) |
| Copy | Ctrl+Shift+C | implemented |
| Paste | Ctrl+Shift+V | implemented |
| Paste selection | Shift+Insert | implemented (clipboard; PRIMARY paste via middle-click) |
| Find | Ctrl+Shift+F | implemented (selection-first) |
| Find next/prev | F3 / Shift+F3 | implemented |
| Split add/switch/resize | Alt+arrows & gsettings | implemented (Ctrl+Shift+E/O, Ctrl+Shift+Alt+Arrows, Alt-drag boundary) |
| Zoom in/out/normal | Ctrl+Plus/Minus/0 | missing |
| Toggle fullscreen | F11 (GTK default) | missing |
| Open preferences/shortcuts | disabled by default | missing |
| Next/prev session | Ctrl+PageUp/Down | implemented (tab switch) |

Notes:
- Tilix defaults are defined in `data/gsettings/com.gexperts.Tilix.gschema.xml` and surfaced in `data/resources/ui/shortcuts.ui`.
- Pure D input translation lives in `pured/platform/input.d`; app shortcuts are in `pured/main.d`.
- F21-F24 are mapped (CSI 35~..38~); additional extended keypad keys remain unmapped.
