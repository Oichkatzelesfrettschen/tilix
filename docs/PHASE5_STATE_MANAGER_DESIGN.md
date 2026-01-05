# Phase 5: TerminalStateManager Architecture Design

**Date**: 2026-01-05
**Phase**: 5 - IO Thread Integration
**Status**: Design Phase

## Goals

Separate PTY I/O from GTK main thread following Ghostty's architecture:
- **IO thread**: Non-blocking PTY reads, VT parsing, buffer updates
- **Main thread**: Rendering, user input, GTK event handling
- **Lock-free communication**: Minimize contention and latency

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         Main Thread                          │
│  ┌────────────┐      ┌──────────────┐      ┌─────────────┐ │
│  │ Terminal.d │─────▶│    VTE3      │─────▶│   X11/      │ │
│  │            │◀─────│  Container   │◀─────│  Wayland    │ │
│  └────────────┘      └──────────────┘      └─────────────┘ │
│         │                     │                             │
│         │ User Input          │ DelegateToVTE Events        │
│         ▼                     ▼                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │          TerminalStateManager                        │   │
│  │  ┌──────────────┐         ┌──────────────┐         │   │
│  │  │ Input Queue  │         │ Event Queue  │         │   │
│  │  │ (Main → IO)  │         │ (IO → Main)  │         │   │
│  │  └──────────────┘         └──────────────┘         │   │
│  │                                                      │   │
│  │  ┌────────────────────────────────────────────┐    │   │
│  │  │   DoubleBuffer<TerminalState>              │    │   │
│  │  │   ┌────────────┐      ┌────────────┐       │    │   │
│  │  │   │ Write Buf  │◀─────│ Read Buf   │       │    │   │
│  │  │   │ (IO thread)│ swap │(Main thread)│       │    │   │
│  │  │   └────────────┘      └────────────┘       │    │   │
│  │  └────────────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                          IO Thread                           │
│  ┌──────────────┐      ┌────────────┐      ┌────────────┐  │
│  │IOThreadManager│─────▶│  VTParser  │─────▶│TerminalBuf │  │
│  │              │      │            │      │   State    │  │
│  └──────────────┘      └────────────┘      └────────────┘  │
│         │                                                    │
│         │ select() / epoll()                                │
│         ▼                                                    │
│  ┌─────────────┐                                            │
│  │  PTY FD     │                                            │
│  │  (vte.getPty│                                            │
│  │  ().getFd())│                                            │
│  └─────────────┘                                            │
└─────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

### 1. TerminalStateManager
**Location**: `source/gx/tilix/terminal/state.d`
**Purpose**: Coordinate state updates between threads
**Responsibilities**:
- Manage double-buffered terminal state
- Route user input to IO thread
- Route IO events to main thread
- Synchronize state swaps
- Handle DelegateToVTE passthrough

**API**:
```d
class TerminalStateManager {
    // Lifecycle
    this(IRenderingContainer container);
    void start();
    void stop();

    // Input (Main → IO)
    void sendInput(string data);
    void requestResize(ushort cols, ushort rows);

    // Events (IO → Main)
    bool pollEvent(out IOMessage msg);

    // State access
    ref const(TerminalState) getReadState();
    void acknowledgeFrame();

    // Backend delegation
    void delegateToVTE(ubyte[] rawData);
}
```

### 2. TerminalState
**Purpose**: Complete terminal state snapshot
**Contents**:
```d
struct TerminalState {
    // Grid content
    Cell[] cells;
    ushort cols;
    ushort rows;

    // Cursor
    ushort cursorCol;
    ushort cursorRow;
    bool cursorVisible;
    CursorShape cursorShape;

    // Scrollback
    size_t scrollbackLines;
    size_t scrollbackOffset;

    // Attributes
    CellAttrs defaultAttrs;

    // Metadata
    ulong version_;
    bool dirty;
}

struct Cell {
    dchar codepoint;
    CellAttrs attrs;
}

struct CellAttrs {
    RGBA fg;
    RGBA bg;
    ushort flags;  // bold, italic, underline, blink, reverse, strikethrough
}
```

### 3. IOThreadManager (Already Exists)
**Location**: `source/gx/tilix/terminal/iothread.d`
**Current State**: Basic implementation with lock-free queues
**Enhancements Needed**:
- Wire PTY fd from container
- Implement VTParser event handling
- Support DelegateToVTE events

### 4. VTParser (Already Exists)
**Location**: `source/gx/tilix/terminal/vtparser.d`
**Current State**: Stub implementation
**Needs**: Full VT sequence parsing (CSI, OSC, DCS, etc.)

## Threading Model

### Main Thread (GTK)
```d
// Terminal.d
class Terminal {
    private TerminalStateManager _stateManager;
    private gulong _idleHandlerId;

    void initialize() {
        _stateManager = new TerminalStateManager(_container);
        _stateManager.start();

        // Install idle callback for frame updates
        _idleHandlerId = Idle.add(&onIdleFrameUpdate);
    }

    bool onIdleFrameUpdate() {
        // Poll for IO events
        IOMessage msg;
        while (_stateManager.pollEvent(msg)) {
            handleIOEvent(msg);
        }

        // Check for frame ready
        if (_stateManager.isFrameReady()) {
            _container.queueDraw();
            _stateManager.acknowledgeFrame();
        }

        return true;  // Keep callback active
    }

    void handleIOEvent(IOMessage msg) {
        switch (msg.type) {
            case IOMessageType.Bell:
                showBell();
                break;
            case IOMessageType.Title:
                updateDisplayText();
                break;
            case IOMessageType.Data:
                // DelegateToVTE: feed to VTE for processing
                _stateManager.delegateToVTE(msg.data);
                break;
            // ...
        }
    }

    // User input
    void onCommit(string text, uint length) {
        _stateManager.sendInput(text);
    }
}
```

### IO Thread (PTY I/O)
```d
// IOThreadManager.ioLoop()
void ioLoop() {
    while (running) {
        // Process control messages (resize, close)
        handleControlMessages();

        // Read from PTY (non-blocking)
        if (hasDataOnPty()) {
            ubyte[] data = readFromPty();
            VTEvent[] events = vtParser.parse(data);
            processVTEvents(events);
        }

        // Swap buffers and signal frame ready
        if (hasUpdates) {
            signalFrameReady();
        }
    }
}

void processVTEvents(VTEvent[] events) {
    foreach (event; events) {
        if (event.type == VTEvent.Type.DelegateToVTE) {
            // Complex sequence - send to main thread for VTE
            eventQueue.push(IOMessage.makeData(event.rawData));
        } else {
            // Simple sequence - update buffer directly
            updateTerminalState(event);
        }
    }
}
```

## VTE Delegation Strategy

### Problem
Some VT sequences are complex and should continue using VTE's implementation:
- OSC sequences (title, hyperlinks, notifications)
- Complex SGR modes
- DEC private modes
- Rarely-used features

### Solution: DelegateToVTE Events
1. VTParser identifies complex sequences → emits `DelegateToVTE` event
2. IO thread → Main thread via event queue
3. Main thread calls `_container.feedChild(rawData)`
4. VTE processes sequence and updates internal state

### Example Flow
```
User types: echo -e "\033]0;New Title\007"
                ↓
        [PTY fd has data]
                ↓
        [IO thread reads bytes]
                ↓
    [VTParser: OSC 0 → DelegateToVTE]
                ↓
  [IOMessage.makeData("\033]0;New Title\007")]
                ↓
     [Event queue → Main thread]
                ↓
   [onIdleFrameUpdate polls event]
                ↓
  [_container.feedChild(rawData)]
                ↓
   [VTE parses OSC, sets window title]
                ↓
  [VTE emits window-title-changed signal]
                ↓
    [Terminal.updateDisplayText()]
```

## State Synchronization

### Lock-Free Approach
- **Input queue** (Main → IO): Lock-free SPSC queue
- **Event queue** (IO → Main): Lock-free SPSC queue
- **Double buffer**: Atomic swap via atomicStore

### Synchronization Points
1. **Frame boundary**: IO thread swaps buffers after batch of updates
2. **Idle callback**: Main thread polls events and checks frame ready
3. **Resize**: Main thread sends resize → IO thread updates buffer dimensions

## Incremental Implementation

### Phase 5.1: State Manager Skeleton
1. Create `state.d` with TerminalStateManager class
2. Create TerminalState and Cell structs
3. Wire up double buffer (reuse from iothread.d)
4. Implement input/event queues

### Phase 5.2: Wire IO Thread
1. Instantiate IOThreadManager in Terminal constructor
2. Get PTY fd from container: `_container.getPty().getFd()`
3. Pass fd to IOThreadManager.setPtyFd()
4. Start IO thread

### Phase 5.3: Idle Callback
1. Install Idle.add() handler in Terminal.initialize()
2. Poll events via stateManager.pollEvent()
3. Handle DelegateToVTE, Bell, Title events
4. Queue draw on frame ready

### Phase 5.4: DelegateToVTE Handling
1. Add feedChild passthrough to Terminal
2. Route Data events to _container.feedChild()
3. Test with complex sequences (OSC, etc.)

### Phase 5.5: Full VTParser (Future)
1. Implement complete VT sequence parsing
2. Directly update TerminalState for simple sequences
3. Only delegate complex sequences to VTE

## Testing Strategy

### Unit Tests
- TerminalState serialization/deserialization
- Cell attribute packing/unpacking
- Queue operations (push/pop)
- Double buffer swap atomicity

### Integration Tests
1. **PTY Echo**: Type text → verify echoed back
2. **OSC Sequences**: Set title → verify title changed
3. **Resize**: Resize terminal → verify grid updated
4. **High throughput**: `cat large_file` → no dropped frames

### Performance Tests
- Latency: Time from PTY data → screen update
- Throughput: Bytes/second sustained
- Frame rate: Redraws/second under load

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Race conditions | Lock-free queues, atomic operations |
| Deadlock | No locks used, non-blocking design |
| Queue overflow | Bounded queues, backpressure handling |
| VTE state divergence | DelegateToVTE for complex sequences |
| Performance regression | Profile before/after, measure latency |

## Success Criteria

✅ Tilix launches with IO thread active
✅ Terminal responds to typed input
✅ OSC sequences work (title, notifications)
✅ Scrolling works smoothly
✅ No visual artifacts or tearing
✅ Performance >= current VTE3 implementation

## Files to Create/Modify

### New Files
- `source/gx/tilix/terminal/state.d` - TerminalStateManager

### Modified Files
- `source/gx/tilix/terminal/terminal.d` - Wire state manager, idle callback
- `source/gx/tilix/terminal/iothread.d` - Wire PTY fd, enhance event handling
- `source/gx/tilix/terminal/vtparser.d` - Implement full VT parsing (future)

## Dependencies

- Phase 1 ✅: IRenderingContainer abstraction (complete)
- Phase 5.1 ⏳: TerminalStateManager implementation (next)
- Phase 5.2-5.4 ⏳: IO thread wiring and callbacks
- Phase 5.5 🔮: Full VTParser (future enhancement)

## Next Steps

1. Create state.d with TerminalStateManager skeleton
2. Define TerminalState and Cell structs
3. Implement double buffer management
4. Wire up input/event queues
5. Add unit tests for state synchronization

---

**References**:
- `docs/TERMINAL_VTE_AUDIT.md` - Original VTE dependency audit
- `docs/PHASE1_COMPLETE.md` - Phase 1 completion summary
- `source/gx/tilix/terminal/iothread.d` - Existing IO thread implementation
- Ghostty source (inspiration for lock-free architecture)
