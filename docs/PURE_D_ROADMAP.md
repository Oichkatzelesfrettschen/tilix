# Tilix Pure D: Complete Rebuild Roadmap

**Version:** 1.0.0
**Date:** 2026-01-07
**Target:** Feature parity with GTK/VTE3 Tilix
**Timeline:** 16-20 weeks for core features

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Why Pure D?](#2-why-pure-d)
3. [Architecture Overview](#3-architecture-overview)
4. [Module Structure](#4-module-structure)
5. [Phase Breakdown](#5-phase-breakdown)
6. [Detailed Walkthroughs](#6-detailed-walkthroughs)
7. [Dependency Graph](#7-dependency-graph)
8. [Testing Strategy](#8-testing-strategy)
9. [Migration Path](#9-migration-path)
10. [Risk Assessment](#10-risk-assessment)

---

## 1. Executive Summary

### What We're Building

A complete rewrite of Tilix terminal emulator in Pure D, replacing:
- **GTK3** with custom OpenGL rendering + lightweight widget system
- **VTE3** with `arsd.terminalemulator` + custom PTY management
- **GLib/GIO** with native D implementations
- **GSettings** with JSON-based configuration

### Current State vs Target

| Metric | GTK Tilix | Current Pure D | Target Pure D |
|--------|-----------|----------------|---------------|
| FPS | 40 (capped) | 8000+ | 320+ (vsync) |
| Input Latency | ~50ms | <1ms | <1ms |
| Binary Size | ~2MB + GTK | ~500KB | ~1MB |
| Dependencies | GTK3, VTE3, GLib | GLFW, FreeType | GLFW, FreeType |
| Features | 100% | 5% | 100% |

### Recent Progress (2026-01-07)
- Window-title search prompt with editable query and search highlight overlay.
- Bottom-row search prompt overlay during active search input.
- Zoom controls (Ctrl+=/-, Ctrl+0) and fullscreen toggle (F11).
- PRIMARY selection uses X11/XCB or Wayland primary-selection; falls back to clipboard when unsupported.
- DUB dependencies staged for xcb/wayland/xkbcommon integration.

### Why This Document Exists

This roadmap serves as:
1. **Contract** - What we're building and in what order
2. **Tutorial** - How to implement each component
3. **Reference** - Architecture decisions and rationale
4. **Checklist** - Track progress toward feature parity

---

## 2. Why Pure D?

### 2.1 Problems with GTK/VTE3

```
PROBLEM 1: Performance Ceiling
- VTE3 hardcodes 40 FPS refresh rate
- GTK's retained-mode rendering adds latency
- Cairo software rendering is CPU-bound
- No path to modern GPU acceleration

PROBLEM 2: Dependency Hell
- GTK3 is 15+ shared libraries
- VTE3 requires specific GTK version
- GLib/GIO runtime overhead
- Difficult cross-compilation

PROBLEM 3: Limited Control
- VTE3 escape sequence handling is opaque
- Cannot customize rendering pipeline
- Widget behavior locked to GTK patterns
- No access to raw terminal buffer

PROBLEM 4: Maintenance Burden
- GTK4 migration would require rewrite anyway
- VTE maintainers have different priorities
- D bindings lag behind C releases
```

### 2.2 Benefits of Pure D

```
BENEFIT 1: Performance
- Direct OpenGL 4.5 rendering
- Uncapped framerate (hardware-limited)
- Sub-millisecond input latency
- SIMD-optimized text processing

BENEFIT 2: Control
- Own the entire rendering pipeline
- Custom escape sequence handling
- Flexible widget system
- Memory layout optimization

BENEFIT 3: Simplicity
- Single binary deployment
- Minimal runtime dependencies
- D's built-in testing
- No FFI marshalling overhead

BENEFIT 4: Maintainability
- All code in one language
- No C/D boundary bugs
- Unified build system
- Better tooling (DCD, D-Scanner)
```

### 2.3 Trade-offs Accepted

```
TRADE-OFF 1: Development Time
- Must implement everything ourselves
- No existing widget library to lean on
- Longer initial development
- MITIGATION: Incremental delivery, reuse arsd

TRADE-OFF 2: Platform Support
- GLFW abstracts most platforms
- Wayland support via XWayland initially
- macOS/Windows need testing
- MITIGATION: Platform abstraction layer

TRADE-OFF 3: Accessibility
- GTK has mature a11y support
- Must implement screen reader support
- MITIGATION: Phase 10 dedicated to a11y

TRADE-OFF 4: Theme Integration
- Won't match system GTK theme
- Custom theming system needed
- MITIGATION: Theme import from GTK
```

---

## 3. Architecture Overview

### 3.1 Layer Diagram

```
+============================================================+
|                    APPLICATION LAYER                        |
|  TilixApp -> WindowManager -> SessionManager -> Config      |
+============================================================+
                              |
+============================================================+
|                     WIDGET LAYER                            |
|  TabBar | SplitContainer | Terminal | SearchOverlay | Menu  |
+============================================================+
                              |
+============================================================+
|                    RENDERING LAYER                          |
|  Renderer -> FontAtlas -> ShaderManager -> TextureCache     |
+============================================================+
                              |
+============================================================+
|                   TERMINAL LAYER                            |
|  PTYManager -> Emulator -> ScreenBuffer -> SelectionMgr     |
+============================================================+
                              |
+============================================================+
|                    PLATFORM LAYER                           |
|  Window -> Input -> Clipboard -> FileSystem -> Process      |
+============================================================+
                              |
+============================================================+
|                    BINDINGS LAYER                           |
|  GLFW | OpenGL | FreeType | FontConfig | (X11/Wayland)      |
+============================================================+
```

### 3.2 Data Flow

```
INPUT FLOW (Keyboard -> Shell):
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌─────────┐
│  GLFW    │───>│  Input   │───>│ Terminal │───>│   PTY   │
│ Callback │    │ Manager  │    │  Widget  │    │  Write  │
└──────────┘    └──────────┘    └──────────┘    └─────────┘
     │                               │
     │         ┌─────────────────────┘
     │         v
     │    ┌──────────┐
     └───>│ Shortcut │ (if matched, don't send to terminal)
          │ Manager  │
          └──────────┘

OUTPUT FLOW (Shell -> Screen):
┌─────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│   PTY   │───>│ Emulator │───>│  Screen  │───>│ Renderer │
│  Read   │    │  Parse   │    │  Buffer  │    │   Draw   │
└─────────┘    └──────────┘    └──────────┘    └──────────┘
                    │                               │
                    v                               v
              ┌──────────┐                   ┌──────────┐
              │  Title   │                   │   Swap   │
              │  Change  │                   │  Buffers │
              └──────────┘                   └──────────┘

RESIZE FLOW:
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌─────────┐
│  GLFW    │───>│  Window  │───>│  Layout  │───>│ Terminal│
│ Callback │    │ Manager  │    │  Solver  │    │ Resize  │
└──────────┘    └──────────┘    └──────────┘    └─────────┘
                                                     │
                                                     v
                                               ┌─────────┐
                                               │   PTY   │
                                               │ TIOCSWINSZ
                                               └─────────┘
```

### 3.3 Component Responsibilities

```
TilixApp (Singleton)
├── Owns: WindowManager, Config, ShortcutManager
├── Handles: Application lifecycle, global actions
└── Spawns: Main window(s), quake window

WindowManager
├── Owns: Windows[], FocusedWindow
├── Handles: Window creation/destruction, focus
└── Delegates: Input to focused window

Window
├── Owns: TabBar, SessionManager, MenuBar
├── Handles: Window-level shortcuts, chrome
└── Contains: Multiple Sessions (tabs)

Session
├── Owns: SplitContainer (root), TerminalWidgets[]
├── Handles: Pane layout, focus within session
└── Serializes: Layout to JSON for save/restore

SplitContainer (recursive)
├── Owns: Children[] (Terminal or SplitContainer)
├── Handles: Split direction, resize ratios
└── Renders: Divider handles

Terminal (Widget)
├── Owns: PTY, Emulator, SelectionManager, SearchState
├── Handles: Input, rendering, scrollback
└── Emits: Title change, bell, hyperlink events

Renderer (Singleton per GL context)
├── Owns: FontAtlas, ShaderProgram, VAO/VBO
├── Handles: Batched cell rendering
└── Optimizes: Dirty rectangle, instancing
```

---

## 4. Module Structure

### 4.1 Directory Layout

```
pured/
├── package.d                 # Public API exports
├── main.d                    # Entry point
│
├── app/
│   ├── package.d
│   ├── application.d         # TilixApp singleton
│   ├── config.d              # Configuration management
│   ├── shortcuts.d           # Keybinding system
│   └── actions.d             # Action definitions
│
├── window/
│   ├── package.d
│   ├── manager.d             # WindowManager
│   ├── window.d              # Window class
│   └── quake.d               # Quake-mode window
│
├── session/
│   ├── package.d
│   ├── manager.d             # SessionManager
│   ├── session.d             # Session (tab content)
│   └── serializer.d          # Save/load sessions
│
├── widget/
│   ├── package.d
│   ├── base.d                # Widget base class
│   ├── container.d           # Container base
│   ├── split.d               # SplitContainer
│   ├── tabbar.d              # TabBar widget
│   ├── terminal.d            # Terminal widget
│   ├── scrollbar.d           # Scrollbar widget
│   ├── search.d              # Search overlay
│   ├── menu.d                # Menu system
│   └── dialog.d              # Dialog base
│
├── terminal/
│   ├── package.d
│   ├── pty.d                 # PTY management
│   ├── emulator.d            # arsd adapter
│   ├── buffer.d              # Screen buffer
│   ├── selection.d           # Text selection
│   ├── search.d              # Search logic
│   ├── hyperlink.d           # URL detection
│   └── colors.d              # Color palette
│
├── render/
│   ├── package.d
│   ├── renderer.d            # Main renderer
│   ├── fontatlas.d           # Glyph cache
│   ├── shaders.d             # GLSL shaders
│   ├── batch.d               # Batched drawing
│   └── texture.d             # Texture management
│
├── platform/
│   ├── package.d
│   ├── window.d              # GLFW wrapper
│   ├── input.d               # Input processing
│   ├── clipboard.d           # Clipboard access
│   └── process.d             # Process utilities
│
├── ui/
│   ├── package.d
│   ├── theme.d               # Theming system
│   ├── colors.d              # Color schemes
│   ├── fonts.d               # Font configuration
│   └── icons.d               # Icon management
│
└── util/
    ├── package.d
    ├── json.d                # JSON helpers
    ├── unicode.d             # UTF-8 utilities
    ├── rect.d                # Rectangle math
    └── signal.d              # Event/signal system
```

### 4.2 Module Dependencies

```
    ┌─────────────────────────────────────────────────────┐
    │                      main.d                          │
    └─────────────────────────────────────────────────────┘
                              │
                              v
    ┌─────────────────────────────────────────────────────┐
    │                   app/application.d                  │
    │  imports: window/*, session/*, config, shortcuts     │
    └─────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          v                   v                   v
    ┌───────────┐      ┌───────────┐      ┌───────────┐
    │  window/  │      │  session/ │      │   app/    │
    │  manager  │      │  manager  │      │  config   │
    └───────────┘      └───────────┘      └───────────┘
          │                   │
          v                   v
    ┌───────────┐      ┌───────────┐
    │  window/  │      │  session/ │
    │  window   │      │  session  │
    └───────────┘      └───────────┘
          │                   │
          │         ┌─────────┴─────────┐
          │         v                   v
          │   ┌───────────┐      ┌───────────┐
          │   │  widget/  │      │  widget/  │
          │   │  tabbar   │      │   split   │
          │   └───────────┘      └───────────┘
          │                           │
          │         ┌─────────────────┘
          v         v
    ┌─────────────────────────────────────────────────────┐
    │                 widget/terminal.d                    │
    │  imports: terminal/*, render/*, platform/*           │
    └─────────────────────────────────────────────────────┘
          │                   │                   │
          v                   v                   v
    ┌───────────┐      ┌───────────┐      ┌───────────┐
    │ terminal/ │      │  render/  │      │ platform/ │
    │    pty    │      │ renderer  │      │  input    │
    └───────────┘      └───────────┘      └───────────┘
```

---

## 5. Phase Breakdown

### Phase 0: Foundation (COMPLETE)
**Duration:** 2 weeks | **Status:** Done

What was built:
- [x] GLFW window creation
- [x] OpenGL 4.5 context
- [x] Basic shader pipeline
- [x] PTY spawn/read/write
- [x] arsd.terminalemulator integration
- [x] Font atlas with FreeType
- [x] Basic cell rendering
- [x] Keyboard input -> PTY

---

### Phase 1: Core Terminal (Weeks 1-2)
**Goal:** Production-quality single terminal

#### 1.1 Complete Input Handling
```
Files: pured/platform/input.d, pured/terminal/keymap.d

Tasks:
- [ ] Full GLFW key code mapping
- [ ] Application cursor mode (DECCKM)
- [ ] Keypad application mode (DECKPAM)
- [ ] Alt sends ESC prefix
- [ ] Modifier key combinations
- [ ] Dead key / compose support

Why: Without complete input, vim/emacs/tmux don't work properly.
     Application cursor mode changes arrow key sequences.
     Alt+key must send ESC+key for readline shortcuts.

How:
1. Create KeyMapper class with mode state
2. Handle GLFW key callbacks with modifier tracking
3. Implement mode toggle on DECCKM/DECKPAM sequences
4. Test with: vim, emacs, tmux, mc, htop
```

#### 1.2 Mouse Support
```
Files: pured/platform/input.d, pured/terminal/mouse.d

Tasks:
- [ ] Mouse button events
- [ ] Mouse motion tracking
- [ ] Scroll wheel
- [ ] X10 mouse mode
- [ ] Normal mouse mode
- [ ] SGR mouse mode (1006)
- [ ] UTF-8 mouse mode (1005)

Why: Modern terminals need mouse. mc, vim, tmux use it.
     Different modes encode coordinates differently.
     SGR mode handles large terminals (>223 cols).

How:
1. Track mouse mode from escape sequences
2. Encode clicks per current mode
3. Send encoded bytes to PTY
4. Handle scroll -> scroll action or send to PTY
```

#### 1.3 Selection System
```
Files: pured/terminal/selection.d, pured/widget/terminal.d

Tasks:
- [ ] Click to position cursor (for apps)
- [ ] Drag to select text
- [ ] Double-click word select
- [ ] Triple-click line select
- [ ] Shift+click extend selection
- [ ] Selection rendering (inverted colors)
- [ ] Copy selection to clipboard

Why: Text selection is fundamental terminal UX.
     Word/line selection improves productivity.
     Must work with scrollback.

How:
1. Track selection state (start, end, active)
2. Convert screen coords to buffer coords
3. Render selected cells with inverted colors
4. Implement word boundary detection
5. Hook Ctrl+Shift+C to copy
```

#### 1.4 Scrollback Navigation
```
Files: pured/terminal/buffer.d, pured/widget/terminal.d

Tasks:
- [ ] Scroll wheel moves viewport
- [ ] Shift+PageUp/PageDown
- [ ] Scrollbar widget
- [ ] Scroll position indicator
- [ ] Auto-scroll on new output
- [ ] Scrollback size configuration

Why: Terminal without scrollback is unusable.
     arsd.terminalemulator has scrollback, we need UI.

How:
1. Track viewport offset in ScreenBuffer
2. Handle scroll events in Terminal widget
3. Adjust rendering to use viewport offset
4. Create Scrollbar widget
5. Auto-scroll when at bottom and new output arrives
```

#### 1.5 Clipboard Integration
```
Files: pured/platform/clipboard.d

Tasks:
- [ ] Copy to clipboard (Ctrl+Shift+C)
- [ ] Paste from clipboard (Ctrl+Shift+V)
- [ ] Primary selection (X11)
- [ ] Middle-click paste
- [ ] Bracketed paste mode

Why: Copy/paste is essential.
     Primary selection is X11 convention.
     Bracketed paste prevents code injection.

How:
1. Use GLFW clipboard API for basic clipboard
2. For X11 primary: use arsd.simpledisplay or raw X11
3. Wrap paste in bracketed paste sequences when mode enabled
4. Handle paste of multi-line text
```

---

### Phase 2: Widget System (Weeks 3-4)
**Goal:** Reusable widget infrastructure

#### 2.1 Widget Base Classes
```
Files: pured/widget/base.d, pured/widget/container.d

Tasks:
- [ ] Widget base class with bounds, visibility, focus
- [ ] Container base with children management
- [ ] Layout protocol (measure, arrange)
- [ ] Event propagation (bubble, capture)
- [ ] Focus management
- [ ] Dirty rectangle tracking

Why: Need consistent widget infrastructure for tabs, splits, menus.
     Layout protocol enables flexible arrangements.
     Dirty rectangles optimize rendering.

How:
1. Define Widget interface/class:
   - bounds: Rect
   - visible, enabled, focused: bool
   - parent: Container
   - measure(available: Size) -> Size
   - arrange(bounds: Rect)
   - render(renderer: Renderer)
   - handleEvent(event: Event) -> bool

2. Define Container:
   - children: Widget[]
   - addChild, removeChild
   - layout strategy (abstract)
```

#### 2.2 Event System
```
Files: pured/util/signal.d, pured/widget/events.d

Tasks:
- [ ] Signal/slot pattern for D
- [ ] Event base class
- [ ] Mouse events (down, up, move, scroll)
- [ ] Keyboard events (key, char)
- [ ] Focus events (gain, lose)
- [ ] Custom events (title change, bell)

Why: Widgets need to communicate.
     Events decouple components.
     Signal/slot is proven pattern.

How:
1. Implement Signal!T template:
   Signal!void onClick;
   onClick.connect(&handler);
   onClick.emit();

2. Event hierarchy:
   Event
   ├── MouseEvent (x, y, button, modifiers)
   ├── KeyEvent (key, scancode, action, mods)
   ├── CharEvent (codepoint)
   └── FocusEvent (gained: bool)
```

#### 2.3 Layout Engine
```
Files: pured/widget/layout.d

Tasks:
- [ ] Horizontal layout
- [ ] Vertical layout
- [ ] Split layout with ratios
- [ ] Stack layout (overlapping)
- [ ] Constraint-based hints

Why: Tab bars need horizontal layout.
     Split containers need ratio-based layout.
     Dialogs need stacking.

How:
1. Layout strategies as separate classes
2. Two-pass layout: measure then arrange
3. Split layout maintains ratios on resize
4. Support min/max size constraints
```

---

### Phase 3: Tab System (Weeks 5-6)
**Goal:** Multiple terminals in tabs

#### 3.1 TabBar Widget
```
Files: pured/widget/tabbar.d

Tasks:
- [ ] Tab rendering with title
- [ ] Active tab highlight
- [ ] Tab click to switch
- [ ] Tab close button
- [ ] New tab button
- [ ] Tab overflow (scroll or dropdown)
- [ ] Tab drag reordering
- [ ] Tab drag to detach (new window)

Why: Tabs are core Tilix feature.
     Must support many tabs gracefully.
     Drag reorder is expected UX.

How:
1. TabBar contains Tab[] and active index
2. Each Tab has: title, icon, closeable, terminal reference
3. Render tabs horizontally with measured widths
4. Handle click in tab bounds
5. Drag detection with threshold
6. Reorder by swapping in array
```

#### 3.2 Session Management
```
Files: pured/session/session.d, pured/session/manager.d

Tasks:
- [ ] Session class (one per tab)
- [ ] Session contains terminal tree
- [ ] Session title (from active terminal or custom)
- [ ] Session manager in window
- [ ] Session switching
- [ ] Session notifications (activity, bell)

Why: Session abstracts tab content.
     Allows complex layouts per tab.
     Notification badges show activity.

How:
1. Session owns root SplitContainer
2. Tracks focused terminal for title
3. Aggregates notifications from terminals
4. SessionManager maps tabs to sessions
```

#### 3.3 Tab Shortcuts
```
Tasks:
- [ ] Ctrl+Shift+T: New tab
- [ ] Ctrl+Shift+W: Close tab
- [ ] Ctrl+PageUp/Down: Switch tabs
- [ ] Ctrl+Shift+PageUp/Down: Move tab
- [ ] Alt+1-9: Switch to tab N
- [ ] Configurable shortcuts

Why: Power users need keyboard navigation.
     Must match expected terminal shortcuts.

How:
1. Register shortcuts in ShortcutManager
2. Actions create/close/switch sessions
3. Action handlers in Window class
```

---

### Phase 4: Split Panes (Weeks 7-8)
**Goal:** Tiled terminal layout within tabs

#### 4.1 SplitContainer Widget
```
Files: pured/widget/split.d

Tasks:
- [ ] Horizontal split
- [ ] Vertical split
- [ ] Nested splits (recursive)
- [ ] Split ratio maintenance
- [ ] Resize handles
- [ ] Minimum pane size
- [ ] Drag to resize
- [ ] Double-click to equalize

Why: Tiling is Tilix's core feature.
     Must support arbitrary nesting.
     Resize must be smooth.

How:
1. SplitContainer has direction and ratio
2. Two children: first and second (Widget)
3. Children can be Terminal or SplitContainer
4. Resize handle is gap between children
5. Drag updates ratio, re-layouts
```

#### 4.2 Terminal Focus
```
Tasks:
- [ ] Click to focus terminal
- [ ] Visual focus indicator (border)
- [ ] Focus follows mouse (optional)
- [ ] Keyboard focus navigation
- [ ] Alt+Arrow: Focus adjacent terminal

Why: With multiple terminals, focus matters.
     Visual indicator prevents confusion.
     Keyboard nav for efficiency.

How:
1. Session tracks focused terminal
2. Terminal renders border when focused
3. Alt+Arrow finds adjacent terminal geometrically
4. Focus change fires event
```

#### 4.3 Split Actions
```
Tasks:
- [ ] Ctrl+Shift+E: Split right
- [ ] Ctrl+Shift+O: Split down
- [ ] Ctrl+Shift+Q: Close terminal
- [ ] Maximize/restore terminal
- [ ] Zoom terminal (hide others)

Why: Keyboard-driven splitting is core workflow.
     Maximize helps focus on one terminal.

How:
1. Split action creates new SplitContainer
2. Close action removes from parent, merges if needed
3. Maximize stores layout, shows single terminal
4. Restore recovers stored layout
```

#### 4.4 Layout Persistence
```
Files: pured/session/serializer.d

Tasks:
- [ ] Serialize layout to JSON
- [ ] Deserialize layout from JSON
- [ ] Save session to file
- [ ] Load session from file
- [ ] Auto-save on close (optional)

Why: Users expect layout to persist.
     Session files enable templates.

How:
1. Recursive serialization of split tree
2. Each node: type, direction, ratio, children
3. Terminal nodes: profile, working directory
4. JSON format matches GTK Tilix for migration
```

---

### Phase 5: Configuration (Weeks 9-10)
**Goal:** User-customizable settings

#### 5.1 Config System
```
Files: pured/app/config.d

Tasks:
- [ ] JSON config file format
- [ ] Default values
- [ ] Config file locations (XDG)
- [ ] Live reload on change
- [ ] Config validation
- [ ] Migration from GSettings

Why: Users need customization.
     JSON is simple and portable.
     Live reload improves UX.

How:
1. Config class loads from ~/.config/tilix/config.json
2. Defaults embedded in code
3. File watcher triggers reload
4. Validation on load with error messages
5. Import tool reads dconf and writes JSON
```

#### 5.2 Profile System
```
Files: pured/app/profiles.d

Tasks:
- [ ] Profile definition (font, colors, behavior)
- [ ] Multiple profiles
- [ ] Default profile
- [ ] Profile per terminal
- [ ] Profile editor (future: GUI)

Why: Different shells need different settings.
     SSH sessions might want different colors.

How:
1. Profile struct with all terminal settings
2. Profiles stored in config.json
3. Terminal references profile by name
4. Profile changes apply immediately
```

#### 5.3 Color Schemes
```
Files: pured/ui/colors.d

Tasks:
- [ ] Color scheme definition
- [ ] 16 ANSI colors
- [ ] Foreground/background
- [ ] Cursor colors
- [ ] Selection colors
- [ ] Built-in schemes (Tango, Solarized, etc.)
- [ ] Custom scheme creation
- [ ] Import from iTerm2, Alacritty formats

Why: Color customization is essential.
     Common formats enable scheme sharing.

How:
1. ColorScheme struct with 16 + special colors
2. Load from JSON files in schemes directory
3. Parse common formats (iTerm2 XML, Alacritty YAML)
4. Profile references scheme by name
```

#### 5.4 Font Configuration
```
Files: pured/ui/fonts.d

Tasks:
- [ ] Font family selection
- [ ] Font size
- [ ] Font discovery (fontconfig)
- [ ] Fallback fonts for Unicode
- [ ] Bold/italic variants
- [ ] Font preview

Why: Font is personal preference.
     Unicode coverage needs fallbacks.
     Bold text needs bold font.

How:
1. Use fontconfig to enumerate fonts
2. Filter to monospace fonts
3. Resolve font file path
4. Load primary + fallback into FontAtlas
5. Select bold/italic variants
```

---

### Phase 6: Search & URLs (Weeks 11-12)
**Goal:** Find text, detect and open URLs

#### 6.1 Search Overlay
```
Files: pured/widget/search.d, pured/terminal/search.d

Tasks:
- [ ] Search overlay UI
- [ ] Search input field
- [ ] Find next/previous
- [ ] Match highlighting
- [ ] Case sensitive toggle
- [ ] Regex toggle
- [ ] Wrap around toggle
- [ ] Match count display

Why: Finding text in scrollback is essential.
     Regex enables powerful patterns.

How:
1. SearchOverlay widget appears at top/bottom
2. Input field with options checkboxes
3. Search executes on input change (debounced)
4. Results highlight in terminal
5. F3/Shift+F3 for next/previous
6. Escape closes overlay
```

#### 6.2 URL Detection
```
Files: pured/terminal/hyperlink.d

Tasks:
- [ ] URL regex patterns
- [ ] Email patterns
- [ ] File path patterns
- [ ] Hyperlink rendering (underline)
- [ ] Ctrl+click to open
- [ ] Right-click context menu
- [ ] Copy link address

Why: Clickable URLs improve workflow.
     Must not false-positive on code.

How:
1. Regex patterns from terminal/regex.d
2. Scan visible lines for matches
3. Store hyperlink ranges
4. Render with underline
5. On click, check if in hyperlink, open if so
6. Use xdg-open or similar
```

#### 6.3 OSC 8 Hyperlinks
```
Tasks:
- [ ] Parse OSC 8 sequences
- [ ] Store hyperlink ID per cell
- [ ] Render based on hover
- [ ] Click to open

Why: Modern terminals support explicit hyperlinks.
     Compilers output clickable file:line links.

How:
1. arsd.terminalemulator may already parse OSC 8
2. If not, extend parser
3. Store hyperlink metadata per cell
4. On hover, highlight entire link
5. On click, open URL
```

---

### Phase 7: Dialogs & Menus (Weeks 13-14)
**Goal:** Modal dialogs and context menus

#### 7.1 Dialog System
```
Files: pured/widget/dialog.d

Tasks:
- [ ] Modal dialog base
- [ ] Dialog chrome (title bar, close)
- [ ] OK/Cancel buttons
- [ ] Keyboard navigation
- [ ] Escape to cancel
- [ ] Enter to confirm

Why: Preferences, save session need dialogs.
     Must block input to rest of app.

How:
1. Dialog is overlay widget
2. Captures all input
3. Renders dimmed background
4. Standard button layout
5. Focus trap within dialog
```

#### 7.2 Menu System
```
Files: pured/widget/menu.d

Tasks:
- [ ] Menu bar (optional)
- [ ] Context menu
- [ ] Menu items with icons
- [ ] Keyboard shortcuts display
- [ ] Submenus
- [ ] Separator items
- [ ] Checkbox items

Why: Right-click menus expected.
     Menu bar for discoverability.

How:
1. Menu is popup widget
2. Positioned near click or anchor
3. Items render with icon, text, shortcut
4. Hover highlights item
5. Click executes action
6. Submenu opens on hover/arrow
```

#### 7.3 Preferences Dialog
```
Tasks:
- [ ] Tabbed interface
- [ ] General settings
- [ ] Profile editor
- [ ] Color scheme editor
- [ ] Shortcut editor
- [ ] Apply/Cancel/OK

Why: GUI preferences more discoverable than JSON.
     Live preview of changes.

How:
1. Dialog with tab bar
2. Each tab is settings category
3. Changes apply on OK or Apply
4. Cancel reverts to saved config
```

---

### Phase 8: Polish & Performance (Weeks 15-16)
**Goal:** Production quality

#### 8.1 Rendering Optimization
```
Tasks:
- [ ] Instanced rendering for cells
- [ ] Dirty rectangle tracking
- [ ] Only re-render changed cells
- [ ] Texture atlas defragmentation
- [ ] Frame pacing (adaptive vsync)

Why: 8000 FPS is wasteful.
     Reduce GPU/CPU usage.
     Smooth scrolling needs consistent timing.

How:
1. Convert to instanced draw call
2. Track which cells changed since last frame
3. Only update changed vertices
4. VSync to monitor refresh rate
```

#### 8.2 Memory Optimization
```
Tasks:
- [ ] Scrollback memory limits
- [ ] Scrollback compression
- [ ] Font atlas size management
- [ ] Widget object pooling

Why: Long-running terminals accumulate scrollback.
     Must not exhaust memory.

How:
1. Limit scrollback lines (default 10,000)
2. Compress old lines (store as string, not cells)
3. Evict unused glyphs from atlas
4. Reuse widget objects
```

#### 8.3 Error Handling
```
Tasks:
- [ ] PTY error recovery
- [ ] GL error checking
- [ ] Config parse errors
- [ ] User-friendly error messages
- [ ] Crash recovery (restore session)

Why: Robust software handles errors gracefully.
     Users shouldn't lose work on crash.

How:
1. Wrap PTY operations in try/catch
2. Check GL errors in debug builds
3. Validate config with helpful messages
4. Auto-save session periodically
5. On startup, offer to restore
```

---

### Phase 9: Advanced Features (Weeks 17-18)
**Goal:** Power user features

#### 9.1 Synchronized Input
```
Tasks:
- [ ] Input broadcast to all terminals
- [ ] Input broadcast to selected terminals
- [ ] Toggle per terminal

Why: Admins run same commands on multiple servers.
     Must be explicit to prevent accidents.

How:
1. SyncInput mode flag
2. When enabled, KeyEvent sent to all terminals
3. Visual indicator (badge or border color)
4. Shortcut to toggle
```

#### 9.2 Process Monitoring
```
Tasks:
- [x] Detect child exit and close tab
- [ ] Detect running process name
- [ ] Show in tab title
- [ ] Notification on process exit
- [ ] Notification on silence

Why: Know what's running in each terminal.
     Get alerted when long command finishes.

How:
1. Read /proc/<pid>/stat periodically
2. Walk process tree to find foreground
3. Update title on change
4. Timer for silence detection
```

#### 9.3 Triggers
```
Tasks:
- [ ] Pattern matching on output
- [ ] Execute command on match
- [ ] Highlight on match
- [ ] Sound on match

Why: Automate responses to output.
     Highlight errors in build output.

How:
1. List of regex patterns
2. Check each line against patterns
3. On match, execute configured action
4. Store in profile config
```

---

### Phase 10: Accessibility & Integration (Weeks 19-20)
**Goal:** Complete application

#### 10.1 Accessibility
```
Tasks:
- [ ] Screen reader support (AT-SPI?)
- [ ] High contrast themes
- [ ] Keyboard-only operation
- [ ] Focus indicators

Why: Accessibility is important.
     Legal requirements in some jurisdictions.

How:
1. Research AT-SPI D bindings
2. Expose widget tree to a11y API
3. Announce text changes
4. Ensure all actions have shortcuts
```

#### 10.2 Desktop Integration
```
Tasks:
- [ ] .desktop file
- [ ] D-Bus interface
- [ ] Desktop notifications
- [ ] File manager integration
- [ ] System tray (optional)

Why: Good citizenship in desktop environment.
     Notifications for background activity.

How:
1. Install .desktop to applications
2. D-Bus interface for remote control
3. libnotify or native D-Bus for notifications
4. Register as default terminal (optional)
```

#### 10.3 Documentation
```
Tasks:
- [ ] User manual
- [ ] Configuration reference
- [ ] Man page
- [ ] Keyboard shortcuts reference
- [ ] Migration guide from GTK Tilix

Why: Users need documentation.
     Migration guide helps existing users.

How:
1. Markdown docs in docs/
2. Generate man page from markdown
3. In-app help (F1)
4. Shortcuts overlay (Ctrl+?)
```

---

## 6. Detailed Walkthroughs

### 6.1 Implementing the Widget System

**For Senior Dev:**

The widget system is the foundation. Everything - tabs, terminals, dialogs - is a widget. We need:

1. **Abstract base** - Common interface for all widgets
2. **Layout protocol** - Two-phase measure/arrange like WPF/Flutter
3. **Event routing** - Bubble up, capture down
4. **Focus management** - Tab order, focus stealing prevention

**For Junior:**

Think of widgets like building blocks. Each block knows:
- Where it is (bounds rectangle)
- How big it wants to be (measure)
- How to draw itself (render)
- What to do when clicked (handleEvent)

Let's walk through creating a Button widget:

```d
// pured/widget/button.d
module pured.widget.button;

import pured.widget.base;
import pured.render.renderer;
import pured.util.signal;

class Button : Widget {
    private string _label;
    private bool _hovered;
    private bool _pressed;

    // Signal that fires when clicked
    Signal!void onClick;

    this(string label) {
        _label = label;
    }

    // Phase 1: How big do I want to be?
    override Size measure(Size available) {
        // Measure text + padding
        auto textSize = renderer.measureText(_label);
        return Size(
            textSize.width + 20,   // 10px padding each side
            textSize.height + 10   // 5px padding top/bottom
        );
    }

    // Phase 2: Where should I put myself?
    // (Container already set our bounds, nothing to do for simple widget)
    override void arrange(Rect bounds) {
        _bounds = bounds;
    }

    // Draw myself
    override void render(Renderer r) {
        // Background
        auto bgColor = _pressed ? Color(0.3, 0.3, 0.3) :
                       _hovered ? Color(0.4, 0.4, 0.4) :
                                  Color(0.2, 0.2, 0.2);
        r.fillRect(_bounds, bgColor);

        // Border
        r.drawRect(_bounds, Color(0.6, 0.6, 0.6));

        // Text (centered)
        r.drawText(_label, _bounds.center, Color.white);
    }

    // Handle input
    override bool handleEvent(Event e) {
        if (auto me = cast(MouseEvent)e) {
            bool inside = _bounds.contains(me.x, me.y);

            if (me.type == MouseEvent.Type.Move) {
                _hovered = inside;
                return inside;  // Consume if inside
            }
            else if (me.type == MouseEvent.Type.Down && inside) {
                _pressed = true;
                return true;
            }
            else if (me.type == MouseEvent.Type.Up && _pressed) {
                _pressed = false;
                if (inside) {
                    onClick.emit();  // Fire click signal!
                }
                return true;
            }
        }
        return false;
    }
}
```

**Usage:**

```d
auto button = new Button("Click Me");
button.onClick.connect({
    writeln("Button was clicked!");
});
```

### 6.2 Implementing the Split Container

**For Senior Dev:**

SplitContainer is recursive - children can be Terminal or another SplitContainer. Key challenges:
1. Maintaining ratios on resize
2. Resize handle hit testing
3. Minimum size propagation
4. Serialization of nested structure

**For Junior:**

Imagine a window split in half. You can drag the divider to resize. Now imagine each half can also be split. That's what we're building.

```d
// pured/widget/split.d
module pured.widget.split;

import pured.widget.base;
import pured.widget.container;

enum SplitDirection { Horizontal, Vertical }

class SplitContainer : Container {
    private SplitDirection _direction;
    private float _ratio = 0.5;  // 0.0 to 1.0
    private Widget _first;
    private Widget _second;

    private enum HANDLE_SIZE = 6;  // pixels
    private bool _dragging;

    this(SplitDirection dir, Widget first, Widget second) {
        _direction = dir;
        _first = first;
        _second = second;
        addChild(first);
        addChild(second);
    }

    // Calculate where the divider is
    private Rect handleRect() {
        if (_direction == SplitDirection.Horizontal) {
            int splitX = cast(int)(_bounds.x + _bounds.width * _ratio);
            return Rect(
                splitX - HANDLE_SIZE/2,
                _bounds.y,
                HANDLE_SIZE,
                _bounds.height
            );
        } else {
            int splitY = cast(int)(_bounds.y + _bounds.height * _ratio);
            return Rect(
                _bounds.x,
                splitY - HANDLE_SIZE/2,
                _bounds.width,
                HANDLE_SIZE
            );
        }
    }

    override void arrange(Rect bounds) {
        _bounds = bounds;

        auto handle = handleRect();

        if (_direction == SplitDirection.Horizontal) {
            // First gets left portion
            _first.arrange(Rect(
                bounds.x,
                bounds.y,
                handle.x - bounds.x,
                bounds.height
            ));
            // Second gets right portion
            _second.arrange(Rect(
                handle.x + HANDLE_SIZE,
                bounds.y,
                bounds.right - handle.x - HANDLE_SIZE,
                bounds.height
            ));
        } else {
            // Vertical split - first on top, second on bottom
            _first.arrange(Rect(
                bounds.x,
                bounds.y,
                bounds.width,
                handle.y - bounds.y
            ));
            _second.arrange(Rect(
                bounds.x,
                handle.y + HANDLE_SIZE,
                bounds.width,
                bounds.bottom - handle.y - HANDLE_SIZE
            ));
        }
    }

    override void render(Renderer r) {
        // Render children
        _first.render(r);
        _second.render(r);

        // Render divider handle
        auto handle = handleRect();
        auto color = _dragging ? Color(0.4, 0.6, 0.9) : Color(0.3, 0.3, 0.3);
        r.fillRect(handle, color);
    }

    override bool handleEvent(Event e) {
        if (auto me = cast(MouseEvent)e) {
            auto handle = handleRect();

            if (me.type == MouseEvent.Type.Down && handle.contains(me.x, me.y)) {
                _dragging = true;
                return true;
            }
            else if (me.type == MouseEvent.Type.Up) {
                _dragging = false;
            }
            else if (me.type == MouseEvent.Type.Move && _dragging) {
                // Update ratio based on mouse position
                if (_direction == SplitDirection.Horizontal) {
                    _ratio = cast(float)(me.x - _bounds.x) / _bounds.width;
                } else {
                    _ratio = cast(float)(me.y - _bounds.y) / _bounds.height;
                }
                // Clamp to valid range (min 10% each side)
                _ratio = clamp(_ratio, 0.1, 0.9);
                // Re-layout
                arrange(_bounds);
                return true;
            }
        }

        // Let children handle events
        if (_first.handleEvent(e)) return true;
        if (_second.handleEvent(e)) return true;
        return false;
    }

    // Split one child into two
    void split(Widget target, SplitDirection dir, Widget newWidget) {
        if (_first is target) {
            _first = new SplitContainer(dir, target, newWidget);
            addChild(_first);
        } else if (_second is target) {
            _second = new SplitContainer(dir, target, newWidget);
            addChild(_second);
        }
        arrange(_bounds);  // Re-layout
    }
}
```

### 6.3 Implementing Tab Drag-and-Drop

**For Senior Dev:**

Tab DnD has two modes:
1. Reorder within same tab bar
2. Detach to new window

Need drag threshold to distinguish click from drag. During drag, render ghost tab at cursor.

**For Junior:**

When you drag a tab, several things happen:
1. We wait until you've moved enough to "start" the drag
2. We show a preview of where the tab will go
3. When you release, we either reorder or detach

```d
// In TabBar.handleEvent:

override bool handleEvent(Event e) {
    if (auto me = cast(MouseEvent)e) {
        // Find which tab was hit
        int tabIndex = hitTestTab(me.x, me.y);

        if (me.type == MouseEvent.Type.Down && tabIndex >= 0) {
            _pressedTab = tabIndex;
            _dragStart = Point(me.x, me.y);
            _dragging = false;
            return true;
        }
        else if (me.type == MouseEvent.Type.Move && _pressedTab >= 0) {
            // Check if we've moved enough to start drag
            auto dist = distance(_dragStart, Point(me.x, me.y));
            if (!_dragging && dist > DRAG_THRESHOLD) {
                _dragging = true;
            }

            if (_dragging) {
                _dragPos = Point(me.x, me.y);

                // Calculate drop position
                _dropIndex = calculateDropIndex(me.x);

                // Check if outside tab bar (detach)
                if (!_bounds.contains(me.x, me.y)) {
                    _willDetach = true;
                }

                markDirty();  // Need to redraw
            }
            return true;
        }
        else if (me.type == MouseEvent.Type.Up && _pressedTab >= 0) {
            if (_dragging) {
                if (_willDetach) {
                    // Detach to new window
                    auto session = _sessions[_pressedTab];
                    removeTab(_pressedTab);

                    // Create new window at cursor
                    auto newWindow = windowManager.createWindow();
                    newWindow.addSession(session);
                    newWindow.moveTo(me.screenX, me.screenY);
                } else if (_dropIndex != _pressedTab) {
                    // Reorder
                    auto session = _sessions[_pressedTab];
                    _sessions.remove(_pressedTab);
                    _sessions.insert(_dropIndex, session);
                }
            } else {
                // Just a click - switch to tab
                setActiveTab(_pressedTab);
            }

            _pressedTab = -1;
            _dragging = false;
            return true;
        }
    }
    return false;
}

override void render(Renderer r) {
    // Render normal tabs
    foreach (i, tab; _tabs) {
        if (_dragging && i == _pressedTab) continue;  // Skip dragged tab
        renderTab(r, i, tab);
    }

    // Render drop indicator
    if (_dragging && !_willDetach) {
        auto x = tabPositions[_dropIndex];
        r.fillRect(Rect(x-2, _bounds.y, 4, _bounds.height), Color.accent);
    }

    // Render dragged tab at cursor
    if (_dragging) {
        auto tab = _tabs[_pressedTab];
        renderTab(r, _pressedTab, tab, _dragPos.x, _dragPos.y);
    }
}
```

---

## 7. Dependency Graph

### Build Order

```
Level 0 (No internal deps):
  util/rect.d
  util/signal.d
  util/json.d
  util/unicode.d

Level 1 (Depends on util):
  platform/window.d     <- util/rect
  platform/clipboard.d  <- util/unicode
  render/shaders.d      <- (standalone GLSL)
  terminal/colors.d     <- (standalone palette)

Level 2 (Platform layer):
  platform/input.d      <- platform/window, util/signal
  render/fontatlas.d    <- platform/window (GL context)
  render/texture.d      <- platform/window (GL context)

Level 3 (Rendering):
  render/renderer.d     <- render/fontatlas, render/shaders
  render/batch.d        <- render/renderer

Level 4 (Terminal core):
  terminal/buffer.d     <- terminal/colors
  terminal/pty.d        <- (POSIX APIs)
  terminal/emulator.d   <- arsd.terminalemulator

Level 5 (Widget base):
  widget/base.d         <- util/rect, util/signal
  widget/events.d       <- widget/base
  widget/container.d    <- widget/base

Level 6 (Widgets):
  widget/terminal.d     <- terminal/*, widget/base, render/renderer
  widget/split.d        <- widget/container
  widget/tabbar.d       <- widget/container, util/signal
  widget/scrollbar.d    <- widget/base
  widget/menu.d         <- widget/container
  widget/dialog.d       <- widget/container

Level 7 (Session):
  session/session.d     <- widget/split, widget/terminal
  session/manager.d     <- session/session
  session/serializer.d  <- session/session, util/json

Level 8 (Window):
  window/window.d       <- session/manager, widget/tabbar
  window/manager.d      <- window/window
  window/quake.d        <- window/window

Level 9 (Application):
  app/config.d          <- util/json
  app/shortcuts.d       <- platform/input
  app/actions.d         <- util/signal
  app/application.d     <- window/manager, app/config

Level 10 (Entry):
  main.d                <- app/application
```

### External Dependencies

```
Required (bindbc bindings):
├── bindbc-glfw        # Window, input, GL context
├── bindbc-opengl      # OpenGL 4.5 rendering
├── bindbc-freetype    # Font rasterization
└── arsd-official      # terminalemulator subpackage

Optional (for enhancements):
├── fontconfig-d       # System font discovery
├── dbus-d             # Desktop integration
└── libnotify-d        # Notifications

Build-time only:
└── dmd/ldc2           # D compiler
```

---

## 8. Testing Strategy

### Unit Tests

```d
// pured/widget/split_test.d
unittest {
    // Test split ratio clamping
    auto split = new SplitContainer(
        SplitDirection.Horizontal,
        new MockWidget(),
        new MockWidget()
    );
    split.arrange(Rect(0, 0, 100, 100));

    // Drag to extreme left
    split.handleEvent(new MouseEvent(MouseEvent.Type.Down, 50, 50));
    split.handleEvent(new MouseEvent(MouseEvent.Type.Move, 5, 50));
    split.handleEvent(new MouseEvent(MouseEvent.Type.Up, 5, 50));

    // Ratio should clamp to 0.1, not 0.05
    assert(split.ratio >= 0.1);
}
```

### Integration Tests

```d
// test/integration/terminal_test.d
unittest {
    // Test PTY + Emulator integration
    auto term = new Terminal();
    term.spawn("/bin/bash");

    // Send command
    term.sendInput("echo hello\n");

    // Wait for output
    Thread.sleep(100.msecs);
    term.processOutput();

    // Check screen buffer contains "hello"
    auto screen = term.getScreenText();
    assert(screen.canFind("hello"));
}
```

### Visual Tests

```bash
# Screenshot comparison tests
./test/visual/run.sh

# Captures screenshots at key states:
# - Empty terminal
# - With colored output (ls --color)
# - Split panes
# - Tab bar with multiple tabs
# - Search overlay
# - Context menu

# Compares against golden images
# Fails if pixel diff > threshold
```

---

## 9. Migration Path

### For Existing Tilix Users

```
Phase 1: Parallel Installation
- Pure D version installs as "tilix-pure"
- Different binary, different config location
- Can run alongside GTK version

Phase 2: Config Migration
- Tool to convert GSettings to JSON
- Import existing color schemes
- Import keybindings

Phase 3: Session Migration
- Read GTK Tilix session files
- Convert to Pure D format
- Preserve layouts

Phase 4: Default Switch
- Pure D becomes "tilix"
- GTK version becomes "tilix-gtk"
- Deprecation warnings in GTK version

Phase 5: GTK Removal
- Remove GTK code from repository
- Single Pure D codebase
```

### Migration Tool

```bash
# Convert existing config
tilix-migrate --from-gtk --to-pure

# What it does:
# 1. Reads dconf database for com.gexperts.Tilix
# 2. Converts each key to JSON equivalent
# 3. Writes to ~/.config/tilix-pure/config.json
# 4. Copies color schemes
# 5. Converts keybindings
```

---

## 10. Risk Assessment

### High Risk

| Risk | Mitigation |
|------|------------|
| arsd.terminalemulator edge cases | Fork and patch, contribute upstream |
| Wayland native support | Start with XWayland, plan native later |
| Font rendering differences | Test extensively, provide fallbacks |

### Medium Risk

| Risk | Mitigation |
|------|------------|
| Performance regression in complex layouts | Profile early, optimize continuously |
| Missing escape sequences | Test against vttest, document gaps |
| Input method (CJK) support | Research early, may need platform-specific |

### Low Risk

| Risk | Mitigation |
|------|------------|
| OpenGL compatibility | Require GL 4.5, vast majority support |
| Build system complexity | DUB handles most cases |
| Documentation gaps | Write as we build |

---

## Appendix A: Code Style Guide

```d
// Module-level documentation
/**
 * Brief description of module purpose.
 *
 * Longer explanation if needed. Explain the "why" not just "what".
 * Reference related modules.
 */
module pured.widget.terminal;

// Imports grouped: std, third-party, internal
import std.algorithm : map, filter;
import std.array : array;

import arsd.terminalemulator : TerminalEmulator;

import pured.widget.base : Widget;
import pured.terminal.pty : PTY;

// Class documentation
/**
 * Terminal widget displaying a PTY session.
 *
 * Handles:
 * - Keyboard/mouse input to PTY
 * - PTY output rendering
 * - Text selection
 * - Scrollback navigation
 */
class Terminal : Widget {
    // Private fields first, grouped by purpose
    private {
        // Core components
        PTY _pty;
        TerminalEmulator _emulator;

        // Selection state
        SelectionRange _selection;
        bool _selecting;
    }

    // Public interface
    public {
        // Properties
        @property int cols() const { return _emulator.width; }
        @property int rows() const { return _emulator.height; }

        // Methods documented with params and returns
        /**
         * Send input text to the PTY.
         *
         * Params:
         *   text = UTF-8 encoded text to send
         */
        void sendInput(string text) {
            _pty.write(cast(ubyte[])text);
        }
    }
}
```

---

## Appendix B: Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Frame time | <3ms | GPU timer queries |
| Input latency | <1ms | Input timestamp to PTY write |
| Scrollback search | <100ms for 100k lines | Stopwatch |
| Startup time | <100ms to first frame | Process start to



frame |
| Memory per terminal | <10MB base + scrollback | Process memory |
| Binary size | <2MB stripped | File size |

---

## Appendix C: Glossary

| Term | Definition |
|------|------------|
| Cell | Single character position in terminal grid |
| PTY | Pseudo-terminal, Unix mechanism for terminal I/O |
| Emulator | VT100/ANSI escape sequence parser |
| Session | Tab content, contains terminal layout |
| Split | Division of space between terminals |
| Scrollback | History of terminal output above visible area |
| Atlas | Texture containing pre-rendered glyphs |
| Widget | UI element with bounds, rendering, and input handling |

---

**Document Version:** 1.0.0
**Last Updated:** 2026-01-05
**Authors:** Claude + Human
**Status:** Living Document - Update as implementation progresses
