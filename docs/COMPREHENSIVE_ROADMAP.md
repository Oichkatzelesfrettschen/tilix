# Tilix Comprehensive Development Roadmap (2026-01-07)

This roadmap synthesizes findings from four parallel analysis efforts:
1. Technical Debt Audit (22 items identified)
2. Architectural Schizophrenia Audit (8 critical conflicts)
3. Phase 5 Planning (process indicators, tab previews)
4. Phase 6 Planning (vi-mode, hints system)

---

## Executive Summary

### Critical Findings

**Architectural Schizophrenia (8 Issues)**:
- Backend abstraction exists but is completely unused (IRenderBackend dead code)
- IOThreadManager fully implemented but never instantiated
- State management fragmented across 5+ locations
- VTE direct imports throughout supposedly backend-agnostic code
- Synchronous UI blocking in signal handlers
- Threading model mismatch (single-threaded reality vs multi-threaded design)

**Technical Debt (22 Items)**:
- 2 Critical: Regex caching, 4677-line file; resolved: non-blocking PTY read, layout metrics
- 4 High: Error handling gaps, massive methods, resource leaks, GC pressure
- 7 Medium: Queue overflow, singletons, missing tests
- 5 Low: Code smells, typos, magic numbers
- 2 Architectural: VTE abstraction gap, global state

**Blocking Relationships**:
- Phase 5 and 6 cannot proceed until architectural issues resolved
- Backend abstraction must work before OpenGL rendering can be deployed
- IOThread integration blocks high-refresh-rate rendering
- State consolidation required before reliable multi-backend support

### Pure D Backend Snapshot (2026-01-07)

**Completed**:
- Clipboard + PRIMARY selection (GLFW/X11 bridge)
- Truecolor mapping and per-cell colors
- Cursor styles (block/underline/bar/outline) with configurable selection highlight
- HarfBuzz shaping + font fallback
- Config + theme import (Xresources/Alacritty) with hot reload
- Selection-driven search (Ctrl+Shift+F + F3 cycling)
- Window-title search prompt (editable query, Enter confirm, Esc cancel)
- Bottom-row search prompt overlay during active query
- Search highlight overlay + configurable search colors
- Search/hyperlink buffer preallocation + strict @nogc guards
- Hyperlink detection overlay + Ctrl+click activation
- Config schema (JSON Schema) + validation script + performance harness scripts
- IPC schema + local UNIX socket listener (capnproto-dlang) + DUB IPC client
- Accessibility presets (high-contrast/low-vision) + theme preset examples
- Strict `pure-d-nogc` build profile with non-alloc glyph lookups
- SIMD delimiter scan + scrollback search unit tests
- Capnp bindings regenerated via capnpc-dlang
- Pure D headless test harness (`pure-d-tests`)
- Quake/dropdown mode (GLFW floating + borderless) + `quakeHeight` config
- Crash recovery snapshot (visible grid dump + restore)
- Scene graph layout + multi-viewport render loop (mirrored panes)
- Scene graph tabs with Ctrl+Shift+T and Ctrl+PageUp/Down switching
- Split creation (Ctrl+Shift+E/O) + resize (Ctrl+Shift+Alt+Arrows, Alt-drag boundary)
- Split layout persistence (root + active pane) saved to pure-d.json
- Zoom controls (Ctrl+=/-, Ctrl+0) + fullscreen toggle (F11)
- Pure D test matrix script (`scripts/pure-d/run_test_matrix.sh`)

**Open**:
- IPC command coverage beyond newTab (split/close/focus/paste)
- IME implementation + preedit overlay
- Tab bar + split persistence polish
- Renderer perf handoff (PBO/triple buffer)

---

## PHASE 0: CRITICAL BLOCKERS (MUST FIX FIRST)

### Duration: 2-3 weeks
### Blocking: All subsequent phases

These issues prevent any further architecture work and must be resolved before proceeding.

### 0.1 Create RenderingTerminal Abstraction [CRITICAL-P1]

**Problem**: Backend abstraction (IRenderBackend) exists but Terminal.d ignores it completely.

**Root Cause**: Terminal.d hard-codes VTE widget creation and direct method calls.

**Files**:
- `source/gx/tilix/backend/render.d` (interface exists, unused)
- `source/gx/tilix/backend/vte3.d` (VTE3RenderBackend exists, unreachable)
- `source/gx/tilix/terminal/terminal.d:214, 897` (direct VTE creation)

**Solution**:
1. Create `source/gx/tilix/terminal/rendering_interface.d`:
```d
interface IRenderingContainer {
    Widget asWidget();
    void applyFont(PgFontDescription fd);
    void applyColors(RGBA fg, RGBA bg, RGBA[] palette);
    void feedChild(ubyte[] data);
    void queueDraw();
    @property IRenderBackend backend();
}
```

2. Refactor Terminal.d:
```d
class Terminal : EventBox, ITerminal {
private:
    IRenderingContainer _renderContainer;  // NOT ExtendedVTE

    Widget createRendering(RenderBackendType type) {
        _renderContainer = createRenderingContainer(type);
        return _renderContainer.asWidget();
    }
}
```

3. Move backend factory from render.d into Terminal initialization.

**Dependencies**: None (this is the foundation)

**Effort**: 3-4 days

**Verification**:
- [ ] Terminal.d does NOT import `vte.Terminal`
- [ ] Terminal.d does NOT contain `ExtendedVTE vte` field
- [ ] Both VTE3 and OpenGL backends instantiable from same code path

---

### 0.2 Integrate IOThreadManager into Terminal [CRITICAL-P1]

**Problem**: IOThreadManager is fully implemented (iothread.d) but never instantiated anywhere.

**Root Cause**: Terminal.d still uses synchronous GTK signal handlers.

**Files**:
- `source/gx/tilix/terminal/iothread.d:256-427` (IOThreadManager complete)
- `source/gx/tilix/terminal/terminal.d:952-1002` (synchronous handlers)

**Solution**:
1. Terminal acquires IOThreadManager:
```d
class Terminal {
private:
    IOThreadManager _ioThread;

    void initialize() {
        _ioThread = new IOThreadManager();
        _ioThread.start();

        // Connect to frame-ready signal
        _ioThread.onFrameReady.connect(&handleFrame);
    }

    void handleFrame(ref TerminalBufferState state) {
        // Update UI from lock-free buffer
        _renderContainer.backend.prepareFrame(convertToRenderModel(state));
        _renderContainer.backend.present();
    }
}
```

2. Remove synchronous VTE queries:
```d
// REMOVE THIS:
vteHandlers ~= vte.addOnContentsChanged(delegate(VTE) {
    glong cursorCol, cursorRow;
    vte.getCursorPosition(cursorCol, cursorRow);  // BLOCKING
    string text = vte.getTextRange(...);          // BLOCKING
});

// REPLACE WITH:
// IO thread delivers parsed buffer via lock-free queue
// Main thread reads from queue in idle callback
```

**Dependencies**:
- Requires 0.1 (IRenderingContainer must accept RenderModel)
- Requires unified RenderModel definition

**Effort**: 4-5 days

**Verification**:
- [ ] IOThreadManager._ioThread running for each terminal
- [ ] No synchronous VTE queries in signal handlers
- [ ] PTY reads happen in IO thread, not GTK main thread
- [ ] DoubleBuffer swap rate matches configured refresh rate

---

### 0.3 Consolidate State Management [HIGH-P2]

**Problem**: Terminal state tracked in 5+ separate locations without synchronization.

**Locations**:
1. GlobalTerminalState (terminal.d:4503-4656)
2. Terminal private fields (terminal.d:200-310)
3. TerminalBufferState (iothread.d:198-245)
4. RenderModel (render.d:62-70)
5. VTE internal state (inaccessible)

**Root Cause**: No single source of truth, no versioning, no atomic updates.

**Solution**:
1. Create `source/gx/tilix/terminal/state_manager.d`:
```d
struct UnifiedTerminalState {
    // Dimensions
    ushort cols;
    ushort rows;

    // Cursor
    ushort cursorCol;
    ushort cursorRow;
    bool cursorVisible;

    // Colors
    RGBA[16] palette;
    RGBA defaultFg;
    RGBA defaultBg;

    // Profile
    string activeProfileUUID;
    string defaultProfileUUID;

    // Working directory / process
    string currentDirectory;
    string activeProcessName;

    // Versioning
    ulong version_;
}

class TerminalStateManager {
    private UnifiedTerminalState _current;
    private Mutex _mutex;

    @property UnifiedTerminalState current() {
        synchronized(_mutex) {
            return _current;
        }
    }

    void update(scope void delegate(ref UnifiedTerminalState) updater) {
        synchronized(_mutex) {
            updater(_current);
            _current.version_++;
        }
    }
}
```

2. Migrate all state access through TerminalStateManager.

**Dependencies**: None (can start in parallel with 0.1/0.2)

**Effort**: 3-4 days

**Verification**:
- [ ] Single TerminalStateManager per Terminal
- [ ] No direct field access to state variables
- [ ] All state updates go through .update() with version increment
- [ ] RenderModel generated from UnifiedTerminalState atomically

---

### 0.4 Fix Critical Tech Debt Items [CRITICAL]

Four blocking technical debt items must be resolved immediately.

#### 0.4.1 Regex Compilation Cache (terminal.d:2032-2065)

**File**: `source/gx/tilix/terminal/terminal.d:2032-2065`

**Problem**: GRegex compiled on every link click → O(n) patterns performance hit.

**Solution**:
```d
private GRegex[string] _regexCache;

GRegex getCompiledRegex(string pattern) {
    if (pattern !in _regexCache) {
        _regexCache[pattern] = compileGRegex(pattern);
    }
    return _regexCache[pattern];
}

// Usage at line 2044:
GRegex regex = getCompiledRegex(tr);  // Cached
```

**Effort**: 2 hours

**Verification**:
- [ ] Profile with 10+ custom URL patterns
- [ ] Confirm regex compilation happens once per pattern
- [ ] No memory leak from unbounded cache (add LRU if needed)

---

#### 0.4.2 Layout Metrics (resolved)

**File**: `source/gx/tilix/session.d:1465-1475`

**Status**: LayoutConfig now uses `terminal.charWidth` and `terminal.charHeight`.

**Follow-up**:
- [ ] Layout calculations correct for 6pt font
- [ ] Layout calculations correct for 24pt font
- [ ] Layout adapts when font changed at runtime

---

#### 0.4.3 Non-blocking PTY Read (resolved)

**File**: `source/gx/tilix/terminal/iothread.d:399-439`

**Status**: Implemented with `select()` and a 1ms timeout in the IO loop.

**Follow-up**:
- [ ] Verify IOThreadManager is instantiated per terminal
- [ ] Validate frame-ready signaling under high bandwidth

---

#### 0.4.4 Decompose terminal.d (4,677 lines)

**File**: `source/gx/tilix/terminal/terminal.d`

**Problem**: 4,677-line monolithic class → impossible to test or maintain.

**Solution**: Decompose into modules:

```
source/gx/tilix/terminal/
  terminal.d          (core Terminal class, <800 lines)
  ui.d                (createUI, createTitlePane, widget hierarchy)
  events.d            (on* signal handlers)
  renderer.d          (rendering coordination, not backend-specific)
  config.d            (applyPreference, profile application)
  triggers.d          (process monitoring, triggers)
```

**Approach**:
1. Extract UI creation methods → ui.d
2. Extract event handlers → events.d
3. Extract applyPreference massive switch → config.d with strategy pattern
4. Extract process monitoring → triggers.d
5. Terminal.d becomes coordinator, delegates to modules

**Dependencies**: Should happen after 0.1-0.3 to avoid rework.

**Effort**: 4-6 days

**Verification**:
- [ ] terminal.d <1,000 lines
- [ ] Each module <500 lines
- [ ] Clear separation of concerns
- [ ] No circular dependencies between modules

---

## PHASE 1: ARCHITECTURAL REPAIR (HIGH PRIORITY)

### Duration: 2-3 weeks
### Depends on: Phase 0 complete

### 1.1 Remove VTE Direct Imports from Terminal [HIGH-P2]

**File**: `source/gx/tilix/terminal/terminal.d:117-120`

**Problem**: Terminal.d imports VTE directly, violating backend abstraction.

**Solution**:
```d
// REMOVE:
import vte.Pty;
import vte.Regex : VRegex = Regex;
import vte.Terminal : VTE = Terminal;
import vtec.vtetypes;

// Terminal should only import:
import gx.tilix.terminal.rendering_interface;
import gx.tilix.backend.render;
```

**Dependencies**: Requires 0.1 (IRenderingContainer)

**Effort**: 2-3 days (touch many call sites)

**Verification**:
- [ ] `grep -r "import vte" terminal.d` returns nothing
- [ ] Terminal.d compiles with -w (warnings as errors)
- [ ] Both VTE3 and OpenGL backends functional

---

### 1.2 Implement Backend Switching at Window Level [HIGH-P2]

**Files**:
- `source/gx/tilix/appwindow.d`
- `source/gx/tilix/session.d`

**Problem**: Backend choice hard-coded at compile time, not runtime.

**Solution**:
1. Add gsettings key: `backend-type` (enum: auto, vte3, opengl)
2. AppWindow reads preference at startup
3. Session creates Terminal with backend parameter
4. Terminal uses factory to create appropriate RenderingContainer

```d
// appwindow.d
void createNewSession() {
    RenderBackendType backendType = parseBackendType(
        gsSettings.getString(SETTINGS_BACKEND_TYPE)
    );

    Session session = new Session(backendType);
    // ...
}

// session.d
this(RenderBackendType backendType) {
    _backendType = backendType;
}

void addTerminal() {
    Terminal term = new Terminal(_backendType);
    // ...
}
```

**Dependencies**: Requires 0.1, 1.1

**Effort**: 2-3 days

**Verification**:
- [ ] User can switch backend via preferences
- [ ] Backend selection persists across restarts
- [ ] Changing backend doesn't require recompile
- [ ] OpenGL backend bypasses VTE 40 FPS limit

---

### 1.3 Implement Proper Signal Handler Cleanup [MEDIUM-P3]

**File**: `source/gx/tilix/terminal/terminal.d:215, 907-1008`

**Problem**: Signal handlers stored but never disconnected → potential use-after-free.

**Solution**:
```d
class Terminal {
private:
    gulong[] vteHandlers;

    ~this() {
        dispose();
    }

    void dispose() {
        if (_renderContainer !is null) {
            Widget widget = _renderContainer.asWidget();

            foreach (handlerId; vteHandlers) {
                widget.handlerDisconnect(handlerId);
            }
            vteHandlers = [];

            _renderContainer = null;
        }

        if (_ioThread !is null) {
            _ioThread.stop();
            _ioThread = null;
        }
    }
}
```

**Dependencies**: None (can do in parallel)

**Effort**: 1 day

**Verification**:
- [ ] Valgrind shows no handler-related leaks
- [ ] Closing terminal doesn't crash
- [ ] No GTK critical warnings on terminal destruction

---

### 1.4 Move Font/Color Application to Backend [MEDIUM-P3]

**Files**:
- `source/gx/tilix/terminal/terminal.d:444-796` (applyFont, applyColors)
- `source/gx/tilix/backend/render.d` (add methods)
- `source/gx/tilix/backend/vte3.d` (implement for VTE)
- `source/gx/tilix/backend/opengl.d` (implement for OpenGL)

**Problem**: Font/color application assumes VTE methods exist.

**Solution**:
1. Add to IRenderBackend:
```d
interface IRenderBackend {
    // Existing...
    void updateFont(PgFontDescription fd);
    void updateColors(RGBA fg, RGBA bg, RGBA[] palette);
}
```

2. VTE3RenderBackend:
```d
void updateFont(PgFontDescription fd) {
    _vte.setFont(fd);
}

void updateColors(RGBA fg, RGBA bg, RGBA[] palette) {
    _vte.setColors(fg, bg, palette);
}
```

3. OpenGLRenderBackend:
```d
void updateFont(PgFontDescription fd) {
    _fontAtlas.rebuild(fd);
    _shaderNeedsRecompile = true;
}

void updateColors(RGBA fg, RGBA bg, RGBA[] palette) {
    _palette = palette.dup;
    _uniformsNeedUpdate = true;
}
```

4. Terminal.d delegates:
```d
void applyFont() {
    PgFontDescription fd = buildFontDescription();
    _renderContainer.backend.updateFont(fd);
}
```

**Dependencies**: Requires 0.1, 1.1

**Effort**: 2-3 days

**Verification**:
- [ ] Font changes work with VTE3 backend
- [ ] Font changes work with OpenGL backend
- [ ] Color scheme changes work for both backends
- [ ] No crashes when backend is null

---

## PHASE 2: FEATURE IMPLEMENTATION

### Duration: 6-8 weeks
### Depends on: Phase 0 and 1 complete

### 2.1 Implement Phase 5: Process Indicators and Tab Previews

**Duration**: 2-3 weeks

Based on detailed Phase 5 plan from planning agent.

#### 2.1.1 Process Indicator Badges

**Files** (new):
- `source/gx/tilix/terminal/process_indicator.d`

**Integration Points**:
- `source/gx/tilix/terminal/activeprocess.d` (existing process tracking)
- `source/gx/tilix/appwindow.d:2100-2280` (SessionTabLabel)
- `source/gx/tilix/theme/palette.d:42-50` (indicator colors defined)

**Implementation**:
```d
class ProcessIndicatorManager {
private:
    SessionTabLabel _tabLabel;
    Palette _currentPalette;

public:
    void updateFromProcess(Process proc) {
        if (proc.isSudo || proc.isRoot) {
            showBadge(BadgeType.Superuser, _currentPalette.superuserBg[0]);
        } else if (proc.isSSH || proc.isContainer) {
            showBadge(BadgeType.Remote, _currentPalette.remoteBg[0]);
        } else {
            hideBadge();
        }
    }

private:
    void showBadge(BadgeType type, RGBA color) {
        _tabLabel.setBadge(getBadgeIcon(type), color);
    }
}
```

**Effort**: 1 week

**Verification**:
- [ ] Badge appears when sudo command runs
- [ ] Badge appears when SSH session active
- [ ] Badge disappears when normal shell returns
- [ ] Colors match palette superuserBg/remoteBg

---

#### 2.1.2 Tab Preview Popover

**Files** (new):
- `source/gx/tilix/terminal/tab_preview.d`

**Integration Points**:
- `source/gx/tilix/session.d` (ImageSurface snapshot pattern)
- `source/gx/tilix/backend/opengl.d` (framebuffer snapshot)
- `source/gx/tilix/appwindow.d` (notebook tab events)

**Implementation**:
```d
class TabOverviewPopover : Popover {
private:
    Image[] _previews;

public:
    void updatePreviews(Session[] sessions) {
        foreach (i, session; sessions) {
            ImageSurface snapshot = session.captureSnapshot(200, 150);
            _previews[i].setFromSurface(snapshot);
        }
    }
}
```

**Effort**: 1-2 weeks

**Verification**:
- [ ] Hover over tab shows preview
- [ ] Preview updates every 2 seconds
- [ ] Preview shows actual terminal content
- [ ] Works with both VTE3 and OpenGL backends

---

### 2.2 Implement Phase 6: Vi-Mode and Hints System

**Duration**: 6-10 weeks

Based on detailed Phase 6 plan from planning agent.

#### 2.2.1 Vi-Mode Core (Phase 6A)

**Files** (new):
```
source/gx/tilix/vimode/
  core.d          (State machine, mode management)
  motion.d        (28 vi motions implementation)
  bindings.d      (Keymap configuration)
  overlay.d       (Visual selection rendering)
```

**State Machine**:
```d
enum ViMode {
    Inactive,
    Normal,
    Visual,
    VisualLine,
    VisualBlock,
    Search,
    InlineSearch
}

class ViModeController {
private:
    ViMode _currentMode;
    CursorPosition _anchorPos;
    CursorPosition _cursorPos;

public:
    void handleKey(GdkEventKey* event) {
        switch (_currentMode) {
            case ViMode.Normal:
                handleNormalModeKey(event);
                break;
            case ViMode.Visual:
                handleVisualModeKey(event);
                break;
            // ...
        }
    }

private:
    void handleNormalModeKey(GdkEventKey* event) {
        switch (event.keyval) {
            case 'h': moveLeft(); break;
            case 'j': moveDown(); break;
            case 'k': moveUp(); break;
            case 'l': moveRight(); break;
            case 'w': moveWordForward(); break;
            // ... 28 motions total
        }
    }
}
```

**Effort**: 3-4 weeks

**Verification**:
- [ ] All 28 vi motions work correctly
- [ ] Visual selection highlights properly
- [ ] Mode transitions match vim behavior
- [ ] Keybindings configurable via gsettings

---

#### 2.2.2 Hints System (Phase 6C)

**Files** (new):
```
source/gx/tilix/hints/
  patterns.d      (Regex patterns for URLs, paths, git hashes, IPs)
  detector.d      (Scan visible buffer for hint matches)
  labels.d        (Generate hint labels, Alacritty algorithm)
  controller.d    (Manage hint lifecycle, keyboard navigation)
```

**Hint Detection**:
```d
struct HintPattern {
    string name;
    Regex!char regex;
    HintAction action;
}

class HintDetector {
private:
    HintPattern[] _patterns;

public:
    Hint[] detectHints(string[] visibleLines) {
        Hint[] hints;

        foreach (i, line; visibleLines) {
            foreach (pattern; _patterns) {
                foreach (match; matchAll(line, pattern.regex)) {
                    hints ~= Hint(
                        pattern.name,
                        i,  // row
                        match.pre.length,  // col
                        match.hit,  // text
                        pattern.action
                    );
                }
            }
        }

        return assignLabels(hints);
    }
}
```

**Effort**: 2-3 weeks

**Verification**:
- [ ] URLs detected and highlighted
- [ ] File paths detected (relative and absolute)
- [ ] Git hashes detected (7+ hex chars)
- [ ] IPv4 addresses detected
- [ ] Hint labels unique and easy to type
- [ ] Actions execute correctly (open URL, open file, copy)

---

## PHASE 3: QUALITY AND INFRASTRUCTURE

### Duration: 2-3 weeks
### Can run in parallel with Phase 2

### 3.1 Set Up Unit Testing Infrastructure [PENDING]

**Files** (new):
- `source/gx/tilix/tests/terminal_state_test.d`
- `source/gx/tilix/tests/vimode_test.d`
- `source/gx/tilix/tests/hints_test.d`
- `source/gx/tilix/tests/process_indicator_test.d`

**Coverage Target**: 70% of core logic paths

**Effort**: 1-2 weeks

**Verification**:
- [ ] All critical code paths have unit tests
- [ ] Tests run in CI on every commit
- [ ] Coverage reports generated automatically
- [ ] No tests depend on X11 (use mocks)

---

### 3.2 Set Up Sanitizers and Instrumentation [PENDING]

**Build Configurations** (add to meson.build and dub.json):

```meson
# Address Sanitizer
if get_option('enable-asan')
  add_project_arguments('-fsanitize=address', language: 'd')
  add_project_link_arguments('-fsanitize=address', language: 'd')
endif

# Undefined Behavior Sanitizer
if get_option('enable-ubsan')
  add_project_arguments('-fsanitize=undefined', language: 'd')
  add_project_link_arguments('-fsanitize=undefined', language: 'd')
endif
```

**Run Suite**:
```bash
# Address Sanitizer
meson configure builddir -Denable-asan=true
meson compile -C builddir
./builddir/tilix

# UB Sanitizer
meson configure builddir -Denable-ubsan=true
meson compile -C builddir
./builddir/tilix

# Thread Sanitizer (requires LDC)
dub build --build=release --compiler=ldc2 -a x86_64 -- -fsanitize=thread
```

**Effort**: 1 week

**Verification**:
- [ ] ASAN detects memory leaks
- [ ] UBSAN catches undefined behavior
- [ ] TSAN finds race conditions
- [ ] CI runs sanitizers on every PR

---

### 3.3 Run Valgrind Heap Analysis [PENDING]

**Procedure**:
```bash
meson configure builddir -Dbuildtype=debug
meson compile -C builddir

valgrind --leak-check=full \
         --show-leak-kinds=all \
         --track-origins=yes \
         --verbose \
         --log-file=valgrind-tilix.log \
         ./builddir/tilix
```

**Focus Areas**:
- GTK widget lifecycle (SessionTabLabel, Terminal destruction)
- Signal handler connections/disconnections
- IOThreadManager start/stop
- Backend switching (VTE3 → OpenGL)

**Effort**: 3-5 days

**Verification**:
- [ ] No definite leaks
- [ ] All signal handlers disconnected
- [ ] IO threads joined cleanly
- [ ] Backends disposed without leaks

---

### 3.4 Generate Flamegraphs and Performance Profiles [PENDING]

**Tools**:
- `perf` (Linux profiler)
- `flamegraph.pl` (Brendan Gregg's tool)

**Procedure**:
```bash
# Record performance data
perf record -F 99 -g ./builddir/tilix

# Generate flamegraph
perf script | stackcollapse-perf.pl | flamegraph.pl > tilix-flamegraph.svg
```

**Focus Areas**:
- Terminal rendering hotpaths
- Font atlas generation
- VT sequence parsing
- OpenGL shader compilation

**Effort**: 2-3 days

**Verification**:
- [ ] Identify hottest code paths
- [ ] No unexpected CPU usage
- [ ] OpenGL backend faster than VTE3 for high refresh rates
- [ ] Font atlas generation <100ms

---

## IMPLEMENTATION SCHEDULE

### Month 1: Critical Blockers
**Week 1-2**: Phase 0.1, 0.2 (RenderingTerminal abstraction, IOThread integration)
**Week 3**: Phase 0.3 (State consolidation)
**Week 4**: Phase 0.4 (Critical tech debt fixes)

### Month 2: Architectural Repair
**Week 5-6**: Phase 1.1, 1.2 (Remove VTE imports, backend switching)
**Week 7**: Phase 1.3, 1.4 (Signal cleanup, font/color abstraction)
**Week 8**: Phase 0.4.4 (Decompose terminal.d)

### Month 3: Features Begin
**Week 9-10**: Phase 2.1.1 (Process indicator badges)
**Week 11-12**: Phase 2.1.2 (Tab preview popover)

### Month 4-5: Vi-Mode and Hints
**Week 13-16**: Phase 2.2.1 (Vi-mode core, 28 motions)
**Week 17-19**: Phase 2.2.2 (Hints system)
**Week 20**: Phase 2.2.3 (Integration and polish)

### Month 6: Quality and Stabilization
**Week 21-22**: Phase 3.1, 3.2 (Unit tests, sanitizers)
**Week 23**: Phase 3.3, 3.4 (Valgrind, flamegraphs)
**Week 24**: Final integration, documentation, release prep

---

## DEPENDENCY GRAPH

```
Phase 0.1 (RenderingTerminal) ← [CRITICAL BLOCKER]
  ├─→ Phase 0.2 (IOThread integration)
  ├─→ Phase 1.1 (Remove VTE imports)
  └─→ Phase 1.2 (Backend switching)

Phase 0.3 (State consolidation) ← [CRITICAL BLOCKER]
  └─→ Phase 0.2 (IOThread needs unified state)

Phase 0.4 (Tech debt) ← [CRITICAL BLOCKER]
  ├─→ 0.4.1 (Regex cache) - Independent
  ├─→ 0.4.2 (Layout metrics, resolved) - Verify
  ├─→ 0.4.3 (PTY read verification) - Needs 0.2
  └─→ 0.4.4 (Decompose terminal.d) - After 0.1-0.3

Phase 1 (Architectural repair) ← Blocked by Phase 0
  ├─→ 1.1, 1.2, 1.4 all need Phase 0 complete
  └─→ 1.3 (Signal cleanup) - Independent, can start anytime

Phase 2 (Features) ← Blocked by Phase 0 and 1
  ├─→ 2.1 (Process indicators) - Needs stable architecture
  └─→ 2.2 (Vi-mode) - Needs backend abstraction for overlays

Phase 3 (Quality) ← Can run in parallel with Phase 2
  └─→ All items independent
```

---

## EFFORT SUMMARY

| Phase | Item | Effort | Status |
|-------|------|--------|--------|
| 0.1 | RenderingTerminal abstraction | 3-4 days | BLOCKER |
| 0.2 | IOThread integration | 4-5 days | BLOCKER |
| 0.3 | State consolidation | 3-4 days | BLOCKER |
| 0.4.1 | Regex cache | 2 hours | BLOCKER |
| 0.4.2 | Layout metrics | 2-3 hours | RESOLVED |
| 0.4.3 | PTY read verification (resolved) | 1-2 hours | VERIFY |
| 0.4.4 | Decompose terminal.d | 4-6 days | BLOCKER |
| **Phase 0 Total** | | **~3 weeks** | |
| 1.1 | Remove VTE imports | 2-3 days | HIGH |
| 1.2 | Backend switching | 2-3 days | HIGH |
| 1.3 | Signal cleanup | 1 day | MEDIUM |
| 1.4 | Font/color backend | 2-3 days | MEDIUM |
| **Phase 1 Total** | | **~2 weeks** | |
| 2.1.1 | Process indicators | 1 week | PENDING |
| 2.1.2 | Tab previews | 1-2 weeks | PENDING |
| 2.2.1 | Vi-mode core | 3-4 weeks | PENDING |
| 2.2.2 | Hints system | 2-3 weeks | PENDING |
| **Phase 2 Total** | | **~8 weeks** | |
| 3.1 | Unit tests | 1-2 weeks | PENDING |
| 3.2 | Sanitizers | 1 week | PENDING |
| 3.3 | Valgrind | 3-5 days | PENDING |
| 3.4 | Flamegraphs | 2-3 days | PENDING |
| **Phase 3 Total** | | **~3 weeks** | |
| **GRAND TOTAL** | | **~16 weeks (4 months)** | |

---

## RISK MITIGATION

### High-Risk Areas

1. **IOThread Integration Complexity**
   - Risk: Race conditions, deadlocks, buffer corruption
   - Mitigation: Thread Sanitizer, extensive unit tests, gradual rollout
   - Fallback: Keep synchronous path as compile-time option

2. **Backend Abstraction Breaking Changes**
   - Risk: Touching 4,677-line file can introduce regressions
   - Mitigation: Comprehensive test suite before refactoring
   - Fallback: Feature flag for old vs new architecture

3. **State Consolidation Data Loss**
   - Risk: Migrating state management could lose user data
   - Mitigation: Parallel validation (old and new state match)
   - Fallback: Gradual migration with verification at each step

4. **Vi-Mode Scope Creep**
   - Risk: Vi-mode could expand beyond 28 motions
   - Mitigation: Strict MVP definition, defer advanced features
   - Fallback: Ship basic motions first, iterate based on feedback

---

## SUCCESS METRICS

### Phase 0 Success Criteria
- [ ] Both VTE3 and OpenGL backends instantiable
- [ ] IOThread running for each terminal
- [ ] No synchronous VTE queries in signal handlers
- [ ] Single UnifiedTerminalState source of truth
- [ ] All 4 critical tech debt items resolved
- [ ] terminal.d <1,000 lines

### Phase 1 Success Criteria
- [ ] Terminal.d does NOT import vte.*
- [ ] User can switch backend via preferences
- [ ] No signal handler leaks in valgrind
- [ ] Font/color changes work for both backends

### Phase 2 Success Criteria
- [ ] Process indicator badges appear for sudo/ssh
- [ ] Tab preview popover functional
- [ ] All 28 vi motions implemented
- [ ] Hints detect URLs, paths, git hashes, IPs

### Phase 3 Success Criteria
- [ ] 70% code coverage on core paths
- [ ] ASAN, UBSAN, TSAN pass cleanly
- [ ] Valgrind shows no definite leaks
- [ ] Flamegraph shows no unexpected hotspots

---

## REFERENCES

- Technical Debt Audit: `docs/TECH_DEBT_AUDIT.md`
- Architectural Audit: This roadmap, Section "Architectural Schizophrenia"
- Phase 5 Plan: Planning agent output (process indicators, tab previews)
- Phase 6 Plan: Planning agent output (vi-mode, hints)
- Backend Interface Map: `docs/architecture/backend-interface-map.md`
- TODO List: `docs/TODO.md`
- Build Guide: `docs/BUILD_DUB.md`
- Contributing: `CONTRIBUTING.md`

---

**Roadmap Generated**: 2026-01-05
**Next Review**: After Phase 0 complete
**Owner**: Tilix Development Team
**Status**: READY FOR EXECUTION
