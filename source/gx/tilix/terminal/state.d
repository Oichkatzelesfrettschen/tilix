/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.terminal.state;

import core.atomic : atomicOp, atomicLoad, atomicStore, MemoryOrder;
import core.sync.condition : Condition;
import core.sync.mutex : Mutex;
import std.experimental.logger;

import gdk.RGBA;
import gtk.Widget;

import gx.tilix.backend.container : IRenderingContainer;
import gx.tilix.terminal.iothread : IOThreadManager, IOMessage, IOMessageType, LockFreeQueue, DoubleBuffer;

/**
 * Terminal cell attributes (colors, styles).
 *
 * Packed into single struct for efficient storage and cache locality.
 */
struct CellAttrs {
    RGBA fg;          // Foreground color
    RGBA bg;          // Background color
    ushort flags;     // Style flags

    enum : ushort {
        BOLD       = 0x0001,
        ITALIC     = 0x0002,
        UNDERLINE  = 0x0004,
        BLINK      = 0x0008,
        REVERSE    = 0x0010,
        STRIKETHROUGH = 0x0020,
        DIM        = 0x0040,
    }
}

/**
 * Single terminal cell.
 */
struct Cell {
    dchar codepoint;    // Unicode character
    CellAttrs attrs;    // Formatting attributes
}

/**
 * Complete terminal state snapshot.
 *
 * Represents the full visible terminal content at a point in time.
 * Used for double-buffering between IO thread and rendering thread.
 */
struct TerminalState {
    // Grid content
    Cell[] cells;           // Row-major: cells[row * cols + col]
    ushort cols;
    ushort rows;

    // Cursor state
    ushort cursorCol;
    ushort cursorRow;
    bool cursorVisible;
    ubyte cursorShape;      // VteCursorShape value

    // Scrollback
    size_t scrollbackLines;
    size_t scrollbackOffset;

    // Default attributes for new cells
    CellAttrs defaultAttrs;

    // Metadata
    ulong version_;         // Incremented on each change for change detection
    bool dirty;             // Whether state has been modified since last render

    /**
     * Initialize state with given dimensions.
     */
    void initialize(ushort newCols, ushort newRows) {
        cols = newCols;
        rows = newRows;
        cells.length = cols * rows;
        cells[] = Cell(' ', CellAttrs.init);

        cursorCol = 0;
        cursorRow = 0;
        cursorVisible = true;
        cursorShape = 0;

        scrollbackLines = 0;
        scrollbackOffset = 0;

        version_ = 0;
        dirty = true;
    }

    /**
     * Resize the terminal grid.
     */
    void resize(ushort newCols, ushort newRows) {
        if (newCols == cols && newRows == rows) return;

        cols = newCols;
        rows = newRows;
        cells.length = cols * rows;
        cells[] = Cell(' ', CellAttrs.init);

        // Clamp cursor position
        if (cursorCol >= cols) cursorCol = cast(ushort)(cols - 1);
        if (cursorRow >= rows) cursorRow = cast(ushort)(rows - 1);

        version_++;
        dirty = true;
    }

    /**
     * Get cell at position.
     */
    const(Cell) getCell(ushort col, ushort row) const nothrow @nogc {
        if (col < cols && row < rows) {
            return cells[row * cols + col];
        }
        return Cell(' ', CellAttrs.init);
    }

    /**
     * Set cell at position.
     */
    void setCell(ushort col, ushort row, dchar codepoint, CellAttrs attrs) nothrow @nogc {
        if (col < cols && row < rows) {
            cells[row * cols + col] = Cell(codepoint, attrs);
        }
    }

    /**
     * Mark state as modified.
     */
    void markDirty() nothrow @nogc {
        version_++;
        dirty = true;
    }
}

/**
 * Terminal state manager for coordinating IO and rendering threads.
 *
 * Purpose: Synchronize state updates between IO thread (reads PTY, parses VT)
 * and main thread (renders to screen, handles input).
 *
 * Design: Lock-free queues + double buffer for minimal latency.
 */
class TerminalStateManager {
private:
    IRenderingContainer _container;
    IOThreadManager _ioThreadManager;

    // State buffers (double buffered)
    DoubleBuffer!TerminalState _stateBuffer;
    TerminalState[2] _buffers;

    // Message queues (lock-free)
    LockFreeQueue!IOMessage _inputQueue;     // Main → IO thread
    LockFreeQueue!IOMessage _eventQueue;     // IO → Main thread

    // Synchronization
    Mutex _frameMutex;
    Condition _frameCondition;
    shared bool _frameReady;
    shared bool _running;

public:
    /**
     * Construct state manager for given container.
     */
    this(IRenderingContainer container) {
        _container = container;
        _ioThreadManager = new IOThreadManager();
        _frameMutex = new Mutex();
        _frameCondition = new Condition(_frameMutex);
        _frameReady = false;
        _running = false;

        // Initialize both buffer slots
        _buffers[0].initialize(cast(ushort)_container.columnCount, cast(ushort)_container.rowCount);
        _buffers[1].initialize(cast(ushort)_container.columnCount, cast(ushort)_container.rowCount);
    }

    /**
     * Start the state manager and IO thread.
     */
    void start() {
        if (atomicLoad(_running)) return;

        atomicStore(_running, true);
        _ioThreadManager.start();
        trace("TerminalStateManager started");
    }

    /**
     * Stop the state manager and IO thread.
     */
    void stop() {
        if (!atomicLoad(_running)) return;

        atomicStore(_running, false);
        _ioThreadManager.stop();

        synchronized (_frameMutex) {
            _frameCondition.notifyAll();
        }

        trace("TerminalStateManager stopped");
    }

    /**
     * Send input to IO thread.
     */
    void sendInput(string data) {
        _inputQueue.push(IOMessage.makeData(cast(ubyte[])data.dup));
    }

    /**
     * Request terminal resize.
     */
    void requestResize(ushort cols, ushort rows) {
        _inputQueue.push(IOMessage.makeResize(cols, rows));
    }

    /**
     * Poll for events from IO thread.
     */
    bool pollEvent(out IOMessage msg) {
        return _eventQueue.pop(msg);
    }

    /**
     * Get read-only reference to current state.
     */
    ref const(TerminalState) getReadState() const {
        return _stateBuffer.readBuffer();
    }

    /**
     * Check if new frame is ready for rendering.
     */
    @property bool isFrameReady() const {
        return atomicLoad!(MemoryOrder.acq)(_frameReady);
    }

    /**
     * Acknowledge that frame has been rendered.
     */
    void acknowledgeFrame() {
        atomicStore!(MemoryOrder.rel)(_frameReady, false);
    }

    /**
     * Delegate complex VT sequence to VTE for processing.
     * Used for OSC sequences, DEC modes, and other complex operations.
     */
    void delegateToVTE(ubyte[] rawData) {
        _container.feedChild(cast(string)rawData);
    }

    /**
     * Get underlying IO thread manager for configuration.
     */
    @property IOThreadManager ioThreadManager() {
        return _ioThreadManager;
    }

    /**
     * Check if state manager is running.
     */
    @property bool running() const {
        return atomicLoad(_running);
    }
}

/**
 * Helper function to compute cell index from row/column.
 */
pragma(inline)
size_t cellIndex(size_t col, size_t row, size_t cols) pure nothrow @nogc {
    return row * cols + col;
}

/**
 * Helper function to get row from cell index.
 */
pragma(inline)
size_t indexToRow(size_t index, size_t cols) pure nothrow @nogc {
    return index / cols;
}

/**
 * Helper function to get column from cell index.
 */
pragma(inline)
size_t indexToCol(size_t index, size_t cols) pure nothrow @nogc {
    return index % cols;
}

@system
unittest {
    // Test TerminalState initialization
    TerminalState state;
    state.initialize(80, 24);

    assert(state.cols == 80);
    assert(state.rows == 24);
    assert(state.cells.length == 80 * 24);
    assert(state.cursorCol == 0);
    assert(state.cursorRow == 0);
    assert(state.cursorVisible);
    assert(state.version_ == 0);

    // Test cell operations
    CellAttrs attrs;
    attrs.flags = CellAttrs.BOLD;
    state.setCell(5, 5, 'A', attrs);

    auto cell = state.getCell(5, 5);
    assert(cell.codepoint == 'A');
    assert(cell.attrs.flags == CellAttrs.BOLD);

    // Test resize
    state.resize(100, 30);
    assert(state.cols == 100);
    assert(state.rows == 30);
    assert(state.cells.length == 100 * 30);
    assert(state.version_ == 1);

    // Test dirty flag
    assert(state.dirty);
    state.markDirty();
    assert(state.version_ == 2);

    // Test index helpers
    assert(cellIndex(10, 5, 80) == 5 * 80 + 10);
    assert(indexToRow(410, 80) == 5);
    assert(indexToCol(410, 80) == 10);
}
