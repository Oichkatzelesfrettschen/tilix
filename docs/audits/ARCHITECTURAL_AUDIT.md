# Tilix Architectural Schizophrenia Audit (2026-01-05)

This document details critical architectural conflicts discovered through comprehensive codebase analysis. These issues represent **fundamental split-brain design patterns** where the codebase has competing, incompatible architectural visions implemented simultaneously.

---

## Executive Summary

**Severity**: CRITICAL - Blocks all feature development and performance improvements

**Root Cause**: Incomplete refactoring left half-implemented abstractions alongside legacy direct implementations. The codebase exhibits architectural schizophrenia: backend abstraction exists but is unused, IOThread infrastructure is complete but never instantiated, state management is fragmented across 5+ locations.

**Impact**:
- Phase 5 and 6 features cannot be implemented reliably
- OpenGL backend exists but is unreachable
- High-refresh rendering impossible without IOThread hookup
- VTE 40 FPS limitation cannot be bypassed
- Testing is nearly impossible due to tight VTE coupling

**Blocking Items**: 8 critical architectural conflicts must be resolved before any feature work

---

## ISSUE 1: VTE VS BACKEND ABSTRACTION SPLIT - CRITICAL

### Severity: CRITICAL (P0)

### The Problem

A complete architectural disconnect between design intent and actual implementation. Backend abstraction layer (`IRenderBackend`) was designed and implemented but **never integrated into Terminal class**.

### Evidence

**File: source/gx/tilix/backend/render.d (lines 97-190)**

Interface exists with full implementation:
```d
interface IRenderBackend {
    void initialize(Widget container);
    void prepareFrame(ref const RenderModel model);
    void present();
    void resize(uint cols, uint rows);
    @property RenderCapabilities capabilities() const;
    @property bool isReady() const;
    void dispose();
}
```

Two implementations exist:
1. `VTE3RenderBackend` (vte3.d:27-100) - wraps VTE widget
2. `OpenGLRenderBackend` (opengl.d:1-100) - custom OpenGL renderer

Factory function exists but is unreachable:
```d
// Line 161 in render.d
IRenderBackend createRenderBackend(RenderBackendType type = RenderBackendType.Auto) {
    final switch (type) {
        case RenderBackendType.Auto:
        case RenderBackendType.VTE3:
            return new VTE3RenderBackend();
        case RenderBackendType.OpenGL:
            return new OpenGLRenderBackend();
    }
}
```

**File: source/gx/tilix/terminal/terminal.d**

Terminal class **never imports backend module**:
```d
// Lines 117-120: Direct VTE imports
import vte.Pty;
import vte.Regex : VRegex = Regex;
import vte.Terminal : VTE = Terminal;
import vtec.vtetypes;

// BUT NOT:
// import gx.tilix.backend;  // NEVER IMPORTED
```

Terminal creates VTE directly:
```d
// Line 214: Direct VTE reference
class Terminal : EventBox, ITerminal {
    private:
        ExtendedVTE vte;  // NOT IRenderBackend

    // Line 897: Hard-coded VTE creation
    Widget createVTE() {
        vte = new ExtendedVTE();  // Direct instantiation
        // Hundreds of vte.method() calls follow
    }
}
```

### Search Results Proving Dead Code

```bash
$ grep -r "createRenderBackend" source/ --include="*.d"
source/gx/tilix/backend/render.d:161:IRenderBackend createRenderBackend(...)

# ZERO call sites - function is never invoked
```

```bash
$ grep -r "import.*backend" source/gx/tilix/terminal/ --include="*.d"
# ZERO results - terminal module never imports backend
```

### Root Cause

The backend abstraction was designed as part of Phase 0-4 work but Terminal.d was never refactored to use it. The rendering backend system is a **complete non-functional scaffold**.

### Impact

- OpenGL backend cannot be activated (no code path reaches it)
- VTE 40 FPS limitation cannot be bypassed
- Testing requires X11 and running VTE widget (no mocking)
- Backend switching impossible without code recompile
- All 4,677 lines of terminal.d tightly coupled to VTE

### Resolution Strategy

**Phase 0.1: Create IRenderingContainer** (3-4 days)

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

class VTE3Container : IRenderingContainer {
    private ExtendedVTE _vte;
    private VTE3RenderBackend _backend;

    this() {
        _vte = new ExtendedVTE();
        _backend = new VTE3RenderBackend(_vte);
    }

    Widget asWidget() { return cast(Widget)_vte; }
    void applyFont(PgFontDescription fd) { _vte.setFont(fd); }
    // ... delegate to VTE
}

class OpenGLContainer : IRenderingContainer {
    private DrawingArea _area;
    private OpenGLRenderBackend _backend;

    this() {
        _area = new DrawingArea();
        _backend = new OpenGLRenderBackend();
    }

    Widget asWidget() { return cast(Widget)_area; }
    void applyFont(PgFontDescription fd) { _backend.updateFont(fd); }
    // ... delegate to OpenGL backend
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

    void applyFont() {
        PgFontDescription fd = buildFontDescription();
        _renderContainer.applyFont(fd);  // Abstracted
    }
}
```

3. Move backend selection to Window/Session level:
```d
// appwindow.d
void createNewSession() {
    RenderBackendType backendType = readBackendPreference();
    Session session = new Session(backendType);
}

// session.d
void addTerminal() {
    Terminal term = new Terminal(_backendType);
}
```

### Verification Checklist

- [ ] Terminal.d does NOT import `vte.Terminal`
- [ ] Terminal.d does NOT contain `ExtendedVTE vte` field
- [ ] Both VTE3 and OpenGL backends instantiable from same code path
- [ ] User can switch backend via gsettings without recompile
- [ ] Terminal compiles with `-w` (warnings as errors)

---

## ISSUE 2: IOTHREAD INFRASTRUCTURE NEVER INSTANTIATED - CRITICAL

### Severity: CRITICAL (P0)

### The Problem

IOThreadManager is **fully implemented** with sophisticated multi-threading patterns (lock-free queues, double buffering, thread synchronization) but is **never instantiated anywhere in the codebase**.

### Evidence

**File: source/gx/tilix/terminal/iothread.d (lines 256-427)**

Complete, production-ready implementation:
```d
class IOThreadManager {
    private:
        Thread _ioThread;
        LockFreeQueue!IOMessage _controlQueue;      // Main → IO
        LockFreeQueue!IOMessage _eventQueue;        // IO → Main
        DoubleBuffer!TerminalBufferState _buffer;   // Lock-free swap
        Mutex _frameMutex;
        Condition _frameCondition;
        int _ptyFd;
        bool _stopRequested;

    void start() {
        _ioThread = new Thread(&ioLoop);
        _ioThread.start();
    }

    void ioLoop() {
        while (!_stopRequested) {
            // Check control queue for commands
            processControlMessages();

            // Read from PTY (non-blocking)
            readPTYData();

            // Parse VT sequences
            updateBuffer();

            // Swap buffers
            _buffer.swap();

            // Signal frame ready
            notifyFrameReady();
        }
    }
}
```

**File: source/gx/tilix/terminal/terminal.d**

Terminal.d has **NO IOThreadManager**:
```d
// Search result:
$ grep -r "IOThreadManager\|iothread\|IOThread" source/gx/tilix/terminal/terminal.d
# ZERO results
```

Instead, Terminal uses synchronous GTK signal handlers:
```d
// Lines 952-1002: Blocking VTE queries in GTK main thread
vteHandlers ~= vte.addOnContentsChanged(delegate(VTE) {
    if (vte is null) return;

    // Line 966-969: SYNCHRONOUS VTE query (BLOCKS UI)
    glong cursorCol, cursorRow;
    vte.getCursorPosition(cursorCol, cursorRow);  // BLOCKING

    // Line 988: SYNCHRONOUS text extraction (BLOCKS UI)
    ArrayG attr = new ArrayG(false, false, 16);
    string text = vte.getTextRange(cursorRow, 0, cursorRow, 128, null, null, attr);
    // BLOCKS until VTE returns text

    // All happens in GTK main thread while PTY delivers data
});
```

### Root Cause

IOThreadManager was designed and implemented but Terminal.d was never refactored to use it. All terminal I/O still happens synchronously on GTK main thread.

### Impact

- UI can freeze during high-bandwidth I/O (file transfers, large git diffs)
- VTE 40 FPS limit cannot be bypassed (no async buffer swapping)
- OpenGL backend cannot achieve 144+ Hz rendering
- No frame pacing control
- Synchronous VTE queries block event loop

### Current Behavior vs Intended Design

**Current Reality**:
```
PTY data arrives → VTE processes → VTE fires signal → GTK main thread
  ↓
Terminal signal handler executes (BLOCKS UI)
  ↓
Synchronous vte.getCursorPosition() (BLOCKS)
  ↓
Synchronous vte.getTextRange() (BLOCKS)
  ↓
UI updates

Result: UI thread blocked during I/O processing
```

**Intended Design** (IOThreadManager):
```
IO Thread                           GTK Main Thread
─────────────────                   ───────────────

PTY data arrives
  ↓
Read (non-blocking)
  ↓
Parse VT sequences
  ↓
Update DoubleBuffer.back
  ↓
Swap buffers (lock-free)          ← Read DoubleBuffer.front (no locks)
  ↓                                   ↓
Signal via queue                    Update UI from buffer
                                      ↓
                                    Present frame

Result: UI thread never blocks, smooth rendering
```

### Resolution Strategy

**Phase 0.2: Integrate IOThreadManager** (4-5 days)

1. Terminal acquires IOThreadManager:
```d
class Terminal : EventBox, ITerminal {
private:
    IRenderingContainer _renderContainer;
    IOThreadManager _ioThread;
    TerminalStateManager _state;

    void initialize() {
        // Create IO thread
        _ioThread = new IOThreadManager();
        _ioThread.onFrameReady.connect(&handleFrameReady);
        _ioThread.start();

        // Open PTY and pass FD to IO thread
        Pty pty = createPty();
        _ioThread.attachPTY(pty.getFd());
    }

    void handleFrameReady(ref TerminalBufferState buffer) {
        // This executes in GTK main thread via idle callback
        // Buffer is lock-free snapshot from IO thread

        // Update state
        _state.update((ref s) {
            s.cursorCol = buffer.cursorCol;
            s.cursorRow = buffer.cursorRow;
            // ... copy buffer data
        });

        // Render
        RenderModel model = _state.current.toRenderModel();
        _renderContainer.backend.prepareFrame(model);
        _renderContainer.backend.present();
    }
}
```

2. Remove synchronous VTE queries:
```d
// REMOVE ALL OF THIS:
vteHandlers ~= vte.addOnContentsChanged(delegate(VTE) {
    glong cursorCol, cursorRow;
    vte.getCursorPosition(cursorCol, cursorRow);  // DELETE
    string text = vte.getTextRange(...);          // DELETE
});

// REPLACE WITH:
// IO thread delivers frames, main thread reads from lock-free buffer
```

3. Verify non-blocking PTY reads are active (implemented in `iothread.d:399-439`) and wire IOThreadManager into Terminal.

### Dependencies

- Requires **Issue 1 resolved** (IRenderingContainer must accept RenderModel)
- Requires **Issue 3 resolved** (UnifiedTerminalState as single source of truth)

### Verification Checklist

- [ ] IOThreadManager._ioThread running for each Terminal instance
- [ ] No synchronous VTE queries in signal handlers
- [ ] PTY reads happen in IO thread, not GTK main thread
- [ ] DoubleBuffer swap rate matches configured refresh rate (60/144/240 Hz)
- [ ] UI remains responsive during `cat large_file.txt`
- [ ] Thread Sanitizer passes (no race conditions)

---

## ISSUE 3: STATE MANAGEMENT FRAGMENTATION - HIGH

### Severity: HIGH (P1)

### The Problem

Terminal state tracked in **5+ separate locations** with no synchronization, no versioning, and no atomic updates. Different subsystems read different state sources leading to potential inconsistencies.

### Evidence

**Location 1: GlobalTerminalState (terminal.d:4503-4656)**
```d
class GlobalTerminalState {
    TerminalState local;
    TerminalState remote;
    string _localHostname;
    string _initialCWD;
    bool _initialized = false;

    // Tracks: hostname, directory, username
}
```

**Location 2: Terminal private fields (terminal.d:200-310)**
```d
private:
    string _activeProfileUUID;
    string _defaultProfileUUID;
    size_t _terminalID;
    immutable string _terminalUUID;
    string _overrideTitle;
    string _overrideCommand;
    string _overrideBadge;
    bool _synchronizeInput;
    bool _synchronizeInputOverride;
    gulong _commitHandlerId;
    bool _isSingleTerminal = true;
    string _cachedBadge;
    string lastTitle;
    bool unsafePasteIgnored;
    long bellStart = 0;
    long lastActivity;
    long silenceThreshold;
    bool monitorSilence = false;
    bool scrollOnOutput = true;
    string activeProcessName = "Unknown";
    // ... 30+ more fields
```

**Location 3: TerminalBufferState (iothread.d:198-245)**
```d
struct TerminalBufferState {
    dchar[] cells;
    ushort cols;
    ushort rows;
    ushort cursorCol;
    ushort cursorRow;
    bool cursorVisible;
    ulong version_;
}
```

**Location 4: RenderModel (render.d:62-70)**
```d
struct RenderModel {
    uint cols;
    uint rows;
    CursorState cursor;
    RGBA[16] palette;
    RGBA defaultFg;
    RGBA defaultBg;
    Cell[] cells;
}
```

**Location 5: VTE's internal state (inaccessible)**
```d
// VTE widget maintains its own:
// - Cell buffer (inaccessible to D code)
// - Cursor position
// - Palette
// - Scrollback history

// Terminal queries VTE at signal time:
// Line 985:
glong cursorCol, cursorRow;
vte.getCursorPosition(cursorCol, cursorRow);  // Query VTE state
```

### Synchronization Issues

**Divergence Example 1: Dimensions**
```d
// GlobalTerminalState.local.cols = 80
// RenderModel.cols = 80
// TerminalBufferState.cols = 80
// VTE internal cols = 79 (just resized, not yet synchronized)

// Which is correct? All four sources disagree after resize.
```

**Divergence Example 2: Cursor Position**
```d
// TerminalBufferState.cursorRow = 24 (IO thread last update)
// VTE cursor row = 25 (VTE advanced cursor)
// RenderModel.cursor.row = 24 (stale from last frame)

// UI renders cursor at wrong position
```

**Where State Updates Happen**:
```d
// GlobalTerminalState updated at lines: 923, 939, 4511-4541
gst.updateState();

// Terminal fields scattered across file:
// Line 1205: _overrideTitle = title;
// Line 1542: activeProcessName = proc.name;
// Line 2156: _cachedBadge = badge;
// ... no central update point

// VTE state changes via signals:
vte.addOnWindowTitleChanged(...);  // Async update
vte.addOnCurrentDirectoryUriChanged(...);  // Async update
vte.addOnCursorPositionChanged(...);  // Async update
```

### Root Cause

No architectural plan for state management. State grew organically as features were added, with each subsystem creating its own state storage.

### Impact

- Race conditions between state sources
- Stale data rendered to screen
- State changes lost during rapid updates
- No way to atomically snapshot terminal state
- Session serialization unreliable (which state source to trust?)

### Resolution Strategy

**Phase 0.3: Consolidate State** (3-4 days)

1. Create `source/gx/tilix/terminal/state_manager.d`:
```d
struct UnifiedTerminalState {
    // Dimensions (source of truth)
    ushort cols;
    ushort rows;

    // Cursor (source of truth)
    ushort cursorCol;
    ushort cursorRow;
    bool cursorVisible;
    CursorShape cursorShape;

    // Colors (source of truth)
    RGBA[16] palette;
    RGBA defaultFg;
    RGBA defaultBg;

    // Profile (source of truth)
    string activeProfileUUID;
    string defaultProfileUUID;

    // Process (source of truth)
    string currentDirectory;
    string activeProcessName;
    bool isRemote;
    bool isSuperuser;

    // UI state (source of truth)
    string title;
    string badge;
    bool synchronizeInput;

    // Versioning for consistency
    ulong version_;
}

class TerminalStateManager {
    private:
        UnifiedTerminalState _current;
        Mutex _mutex;

    @property UnifiedTerminalState current() {
        synchronized(_mutex) {
            return _current;  // Return copy
        }
    }

    void update(scope void delegate(ref UnifiedTerminalState) updater) {
        synchronized(_mutex) {
            updater(_current);
            _current.version_++;
        }
    }

    RenderModel toRenderModel() const {
        synchronized(_mutex) {
            return RenderModel(
                _current.cols,
                _current.rows,
                CursorState(_current.cursorCol, _current.cursorRow, _current.cursorVisible),
                _current.palette,
                _current.defaultFg,
                _current.defaultBg,
                [] // Cells from buffer
            );
        }
    }
}
```

2. Migrate all state access:
```d
class Terminal {
private:
    TerminalStateManager _state;

    void onTitleChanged(string newTitle) {
        _state.update((ref s) {
            s.title = newTitle;
        });
        updateUI();
    }

    void onCursorMoved(ushort col, ushort row) {
        _state.update((ref s) {
            s.cursorCol = col;
            s.cursorRow = row;
        });
    }

    void render() {
        RenderModel model = _state.toRenderModel();
        _renderContainer.backend.prepareFrame(model);
        _renderContainer.backend.present();
    }
}
```

3. Remove fragmented state:
```d
// DELETE GlobalTerminalState
// DELETE Terminal scattered fields
// DELETE direct VTE state queries

// REPLACE with:
_state.current.cursorCol  // Single source of truth
```

### Verification Checklist

- [ ] Single TerminalStateManager per Terminal
- [ ] No direct field access to state variables outside TerminalStateManager
- [ ] All state updates go through `.update()` with version increment
- [ ] RenderModel generated atomically from UnifiedTerminalState
- [ ] No race conditions (verified with Thread Sanitizer)
- [ ] Session serialization uses UnifiedTerminalState only

---

## ISSUE 4: ABSTRACTION LEAKAGE - HIGH

### Severity: HIGH (P1)

### The Problem

Terminal class is supposedly backend-agnostic (implements ITerminal interface) but contains **hundreds of VTE-specific method calls** throughout its 4,677 lines.

### Evidence

**File: terminal.d (lines 117-120)**
```d
// Direct VTE imports
import vte.Pty;
import vte.Regex : VRegex = Regex;
import vte.Terminal : VTE = Terminal;
import vtec.vtetypes;
```

**VTE-specific calls throughout:**
```d
// Line 214: VTE field
ExtendedVTE vte;

// Line 444-796: VTE method calls
void applyFont() {
    PgFontDescription fd = new PgFontDescription();
    fd.setFamily(gsProfile.getString(SETTINGS_PROFILE_FONT_KEY));
    vte.setFont(fd);  // VTE-specific
}

void applyColors() {
    RGBA fg, bg;
    RGBA[] palette = new RGBA[16];
    vte.setColors(fg, bg, palette);  // VTE-specific
}

void feedChild(string data) {
    vte.feedChild(data);  // VTE-specific
}

void copyClipboard() {
    vte.copyClipboard();  // VTE-specific
}

void pasteClipboard() {
    vte.pasteClipboard();  // VTE-specific
}

void reset() {
    vte.reset(true, true);  // VTE-specific
}

void search(string pattern) {
    GRegex regex = compileGRegex(pattern);
    vte.searchSetRegex(regex, 0);  // VTE-specific
}

// ... 100+ more VTE method calls
```

### Expected Pattern

Backend-agnostic code should use interfaces:
```d
// NOT THIS:
void applyFont() {
    vte.setFont(fd);  // VTE-specific
}

// THIS:
void applyFont() {
    if (_renderContainer !is null) {
        _renderContainer.applyFont(fd);  // Interface call
    }
}
```

### Root Cause

Terminal was originally VTE-only. Backend abstraction was added later but Terminal was never refactored to use it.

### Impact

- Cannot swap to OpenGL backend without rewriting hundreds of call sites
- Testing requires X11 + VTE widget (no mocking possible)
- Tight coupling prevents alternative terminal implementations
- Code assumes VTE behavior and limitations

### Resolution Strategy

**Phase 1.1: Remove VTE Imports** (2-3 days)

1. Replace all VTE method calls with IRenderingContainer interface calls
2. Remove VTE imports from terminal.d
3. Verify compilation with both backends

**Verification**:
```bash
$ grep -r "import vte" source/gx/tilix/terminal/terminal.d
# Should return ZERO results
```

---

## ISSUE 5: RESOURCE OWNERSHIP CONFLICTS - MEDIUM

### Severity: MEDIUM (P2)

### The Problem

Unclear widget ownership and lifecycle management. Signal handlers stored but never disconnected, potentially causing use-after-free crashes.

### Evidence

**File: terminal.d (lines 214-218, 907-1008)**
```d
class Terminal : EventBox, ITerminal {
private:
    ExtendedVTE vte;              // Who owns this?
    Overlay terminalOverlay;      // Who owns this?
    ScrolledWindow sw;            // Who owns this?
    Scrollbar sb;                 // Who owns this?
    gulong[] vteHandlers;         // Signal handler IDs

    Widget createVTE() {
        vte = new ExtendedVTE();          // Line 897
        sw = new ScrolledWindow();
        terminalOverlay = new Overlay();

        // Hierarchy:
        terminalOverlay.add(sw);
        sw.add(vte);
        box.add(terminalOverlay);

        // Connect many signals:
        vteHandlers ~= vte.addOnChildExited(&onTerminalChildExited);
        vteHandlers ~= vte.addOnBell(...);
        vteHandlers ~= vte.addOnWindowTitleChanged(...);
        vteHandlers ~= vte.addOnContentsChanged(...);
        vteHandlers ~= vte.addOnKeyPress(...);
        // ... 20+ signal connections

        // BUT WHERE ARE THESE DISCONNECTED?
    }

    // NO DESTRUCTOR
    // NO DISPOSE METHOD
}
```

### Questions

1. When Terminal is destroyed, does GtkD properly release vte?
2. Are all signal handlers disconnected before widget destruction?
3. Do signal closures keep Terminal alive after UI deletion?
4. What happens if Terminal is destroyed while PTY is still active?

### Resolution Strategy

**Phase 1.3: Proper Cleanup** (1 day)

```d
class Terminal {
private:
    gulong[] vteHandlers;
    bool _disposed = false;

    ~this() {
        dispose();
    }

    void dispose() {
        if (_disposed) return;
        _disposed = true;

        // Stop IO thread
        if (_ioThread !is null) {
            _ioThread.stop();
            _ioThread = null;
        }

        // Disconnect all signal handlers
        if (_renderContainer !is null) {
            Widget widget = _renderContainer.asWidget();

            foreach (handlerId; vteHandlers) {
                widget.handlerDisconnect(handlerId);
            }
            vteHandlers = [];

            _renderContainer = null;
        }

        // Close PTY
        if (_pty !is null) {
            _pty.close();
            _pty = null;
        }
    }
}
```

### Verification

- [ ] Valgrind shows no handler-related leaks
- [ ] Closing terminal doesn't crash
- [ ] No GTK critical warnings on destruction
- [ ] All threads joined cleanly

---

## ISSUE 6: SYNCHRONOUS UI BLOCKING - MEDIUM

### Severity: MEDIUM (P2)

### The Problem

Synchronous VTE queries in signal handlers can **block GTK main thread** during high-bandwidth terminal I/O.

### Evidence

**File: terminal.d (lines 952-1002)**
```d
vteHandlers ~= vte.addOnContentsChanged(delegate(VTE) {
    if (vte is null) return;

    // SYNCHRONOUS QUERY 1: Cursor position (BLOCKS)
    glong cursorCol, cursorRow;
    vte.getCursorPosition(cursorCol, cursorRow);

    // SYNCHRONOUS QUERY 2: Text extraction (BLOCKS)
    ArrayG attr = new ArrayG(false, false, 16);
    string text = vte.getTextRange(cursorRow, 0, cursorRow, 128, null, null, attr);

    // SYNCHRONOUS QUERY 3: State update (BLOCKS)
    gst.updateState();

    // All this happens in GTK main thread while PTY delivers data
});
```

### Impact

During high-bandwidth operations:
- `cat 100MB_file.txt` → UI freezes intermittently
- `git diff large_repo` → UI stutters
- `npm install` → Progress bar jumps instead of smooth update

### Resolution Strategy

**Phase 0.2 (IOThread integration) fixes this**

IO thread reads PTY asynchronously, main thread reads from lock-free buffer without blocking.

---

## ISSUE 7: EMPTY INTERFACE IMPLEMENTATION - MEDIUM

### Severity: MEDIUM (P2)

### The Problem

ITerminal interface is too minimal to enforce backend abstraction. Only exposes UI interactions, not rendering or state.

### Evidence

**File: common.d (lines 266-303)**
```d
interface ITerminal : IIdentifiable {
    void toggleFind();
    bool isFindToggled();
    void focusTerminal();
    @property string currentLocalDirectory();
    @property string activeProfileUUID();
    @property string defaultProfileUUID();
}
```

### Missing

- Backend access (`@property IRenderBackend backend()`)
- State access (`@property UnifiedTerminalState state()`)
- Buffer access (`@property TerminalBufferState buffer()`)
- Dimensions (`@property uint columns/rows()`)
- Backend switching (`void applyRenderBackend(IRenderBackend)`)

### Resolution Strategy

**Phase 1.4: Expand ITerminal** (1 day)

```d
interface ITerminal : IIdentifiable {
    // Existing...
    void toggleFind();
    void focusTerminal();

    // NEW: Backend abstraction
    @property IRenderBackend renderBackend();
    void applyRenderBackend(IRenderBackend backend);

    // NEW: State access
    @property UnifiedTerminalState state() const;

    // NEW: Dimensions
    @property uint columns() const;
    @property uint rows() const;

    // NEW: Rendering
    void queueRender();
}
```

---

## ISSUE 8: PROFILE/THEME APPLICATION ASSUMES VTE - MEDIUM

### Severity: MEDIUM (P2)

### The Problem

Font and color application methods assume VTE widget exists and has specific methods.

### Evidence

**File: terminal.d (lines 444-796)**
```d
void applyFont() {
    PgFontDescription fd = new PgFontDescription();
    fd.setFamily(gsProfile.getString(SETTINGS_PROFILE_FONT_KEY));
    vte.setFont(fd);  // Assumes VTE exists
}

void applyColors() {
    RGBA fg, bg;
    RGBA[] palette = new RGBA[16];
    vte.setColors(fg, bg, palette);  // Assumes VTE exists
}
```

### Resolution Strategy

**Phase 1.4: Backend Delegation** (2-3 days)

```d
void applyFont() {
    PgFontDescription fd = buildFontDescription();
    _renderContainer.applyFont(fd);  // Delegate to backend
}

void applyColors() {
    RGBA fg, bg;
    RGBA[] palette = buildPalette();
    _renderContainer.applyColors(fg, bg, palette);  // Delegate to backend
}
```

---

## PRIORITY MATRIX

| Issue | Severity | Blocks | Effort | Phase |
|-------|----------|--------|--------|-------|
| 1. Backend Abstraction | CRITICAL | All features | 3-4 days | 0.1 |
| 2. IOThread Integration | CRITICAL | High refresh | 4-5 days | 0.2 |
| 3. State Consolidation | HIGH | Backend switch | 3-4 days | 0.3 |
| 4. Abstraction Leakage | HIGH | Testing | 2-3 days | 1.1 |
| 5. Resource Ownership | MEDIUM | Stability | 1 day | 1.3 |
| 6. UI Blocking | MEDIUM | Performance | Solved by #2 | 0.2 |
| 7. Empty Interface | MEDIUM | Architecture | 1 day | 1.4 |
| 8. VTE Assumption | MEDIUM | Backend switch | 2-3 days | 1.4 |

---

## RESOLUTION TIMELINE

**Week 1-2**: Issues 1, 2, 3 (Critical blockers)
**Week 3**: Issue 4 (Remove VTE leakage)
**Week 4**: Issues 5, 7, 8 (Resource cleanup, interface expansion, backend delegation)

**Total Estimated Effort**: 3-4 weeks full-time

---

## SUCCESS CRITERIA

### Phase 0 Complete
- [ ] Both VTE3 and OpenGL backends instantiable
- [ ] IOThread running for each terminal
- [ ] No synchronous VTE queries
- [ ] Single state source of truth

### Phase 1 Complete
- [ ] Terminal.d does NOT import vte.*
- [ ] Backend switchable via preference
- [ ] No valgrind leaks
- [ ] ITerminal interface comprehensive

### Verification Commands

```bash
# No VTE imports in terminal.d
grep -r "import vte" source/gx/tilix/terminal/terminal.d && echo "FAIL: VTE import found" || echo "PASS: No VTE imports"

# Backend factory called
grep -r "createRenderBackend" source/gx/tilix --include="*.d" | grep -v "^source/gx/tilix/backend/render.d" && echo "PASS: Factory used" || echo "FAIL: Factory not called"

# IOThread instantiated
grep -r "new IOThreadManager\|IOThreadManager()" source/gx/tilix --include="*.d" && echo "PASS: IOThread used" || echo "FAIL: IOThread never created"

# State manager used
grep -r "new TerminalStateManager\|TerminalStateManager()" source/gx/tilix --include="*.d" && echo "PASS: StateManager used" || echo "FAIL: StateManager never created"
```

---

## REFERENCES

- Technical Debt Audit: `docs/audits/TECH_DEBT_AUDIT.md`
- Comprehensive Roadmap: `docs/roadmaps/COMPREHENSIVE_ROADMAP.md`
- Backend Interface Map: `docs/architecture/backend-interface-map.md`
- TODO List: `docs/roadmaps/TODO.md`
- TODO/FIXME Audit: `docs/audits/TODO-FIXME-AUDIT.md`

---

**Audit Generated**: 2026-01-05
**Auditor**: Architectural Analysis Agent (a80f61d)
**Files Analyzed**: 15+ source files, ~10,000 lines examined
**Status**: REQUIRES IMMEDIATE ACTION
