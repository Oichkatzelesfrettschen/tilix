/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.terminal.iothread;

import core.atomic : atomicOp, atomicLoad, atomicStore, MemoryOrder;
import core.sync.condition : Condition;
import core.sync.mutex : Mutex;
import core.thread : Thread;
import core.time : dur;
import std.algorithm : min;
import std.experimental.logger;

// POSIX select for non-blocking PTY reads
import core.sys.posix.sys.select;
import core.sys.posix.unistd : read;
import core.sys.posix.sys.time : timeval;
import core.stdc.errno;

import gx.tilix.terminal.vtparser;

/**
 * Message types for IO thread communication.
 * Uses tagged union pattern for type-safe message passing.
 */
enum IOMessageType {
    Data,       // PTY output data
    Resize,     // Terminal resize event
    Close,      // Shutdown signal
    Bell,       // Bell/alert from terminal
    Title       // Title change from terminal
}

/**
 * IO message for thread communication.
 * Carries payload appropriate to message type.
 */
struct IOMessage {
    IOMessageType type;

    union {
        // Data payload
        struct {
            ubyte[] data;
        }
        // Resize payload
        struct {
            ushort cols;
            ushort rows;
        }
        // Title payload
        struct {
            string title;
        }
    }

    static IOMessage makeData(ubyte[] bytes) {
        IOMessage msg;
        msg.type = IOMessageType.Data;
        msg.data = bytes.dup;  // Copy to avoid races
        return msg;
    }

    static IOMessage makeResize(ushort cols, ushort rows) {
        IOMessage msg;
        msg.type = IOMessageType.Resize;
        msg.cols = cols;
        msg.rows = rows;
        return msg;
    }

    static IOMessage makeClose() {
        IOMessage msg;
        msg.type = IOMessageType.Close;
        return msg;
    }

    static IOMessage makeBell() {
        IOMessage msg;
        msg.type = IOMessageType.Bell;
        return msg;
    }

    static IOMessage makeTitle(string t) {
        IOMessage msg;
        msg.type = IOMessageType.Title;
        msg.title = t;
        return msg;
    }
}

/**
 * Lock-free single-producer single-consumer queue.
 * Uses atomic operations for thread-safe access without locks.
 *
 * Based on Ghostty's IO queue pattern for minimal latency.
 */
struct LockFreeQueue(T, size_t Capacity = 4096) {
private:
    T[Capacity] _buffer;
    shared size_t _head;  // Write position (producer)
    shared size_t _tail;  // Read position (consumer)

public:
    /**
     * Push item to queue (producer side).
     * Returns true if successful, false if queue is full.
     */
    bool push(T item) nothrow @nogc {
        auto head = atomicLoad!(MemoryOrder.acq)(_head);
        auto tail = atomicLoad!(MemoryOrder.acq)(_tail);

        auto nextHead = (head + 1) % Capacity;
        if (nextHead == tail) {
            return false;  // Queue full
        }

        _buffer[head] = item;
        atomicStore!(MemoryOrder.rel)(_head, nextHead);
        return true;
    }

    /**
     * Pop item from queue (consumer side).
     * Returns true if item was available, false if queue empty.
     */
    bool pop(ref T item) nothrow @nogc {
        auto head = atomicLoad!(MemoryOrder.acq)(_head);
        auto tail = atomicLoad!(MemoryOrder.acq)(_tail);

        if (head == tail) {
            return false;  // Queue empty
        }

        item = _buffer[tail];
        atomicStore!(MemoryOrder.rel)(_tail, (tail + 1) % Capacity);
        return true;
    }

    /**
     * Check if queue is empty.
     */
    @property bool empty() const nothrow @nogc {
        return atomicLoad!(MemoryOrder.acq)(_head) ==
               atomicLoad!(MemoryOrder.acq)(_tail);
    }

    /**
     * Get approximate queue size.
     */
    @property size_t length() const nothrow @nogc {
        auto head = atomicLoad!(MemoryOrder.acq)(_head);
        auto tail = atomicLoad!(MemoryOrder.acq)(_tail);
        return (head >= tail) ? (head - tail) : (Capacity - tail + head);
    }

    /**
     * Clear the queue.
     */
    void clear() nothrow @nogc {
        atomicStore!(MemoryOrder.rel)(_head, cast(size_t)0);
        atomicStore!(MemoryOrder.rel)(_tail, cast(size_t)0);
    }
}

/**
 * Double buffer for terminal content.
 * Allows IO thread to write while renderer reads.
 */
struct DoubleBuffer(T) {
private:
    T[2] _buffers;
    shared size_t _writeIndex;  // 0 or 1

public:
    /**
     * Get buffer for writing (IO thread).
     */
    ref T writeBuffer() nothrow @nogc {
        return _buffers[atomicLoad!(MemoryOrder.acq)(_writeIndex)];
    }

    /**
     * Get buffer for reading (render thread).
     */
    ref const(T) readBuffer() const nothrow @nogc {
        return _buffers[1 - atomicLoad!(MemoryOrder.acq)(_writeIndex)];
    }

    /**
     * Swap buffers atomically.
     * Called after IO thread completes a batch of updates.
     */
    void swap() nothrow @nogc {
        auto current = atomicLoad!(MemoryOrder.acq)(_writeIndex);
        atomicStore!(MemoryOrder.rel)(_writeIndex, 1 - current);
    }
}

/**
 * Terminal buffer state for double-buffering.
 * Contains cell grid and metadata for rendering.
 */
struct TerminalBufferState {
    // Cell content (codepoints)
    dchar[] cells;

    // Dimensions
    ushort cols;
    ushort rows;

    // Cursor position
    ushort cursorCol;
    ushort cursorRow;
    bool cursorVisible;

    // Version for change detection
    ulong version_;

    /**
     * Resize the buffer.
     */
    void resize(ushort newCols, ushort newRows) {
        if (newCols == cols && newRows == rows) return;

        cols = newCols;
        rows = newRows;
        cells.length = cols * rows;
        cells[] = ' ';  // Clear with spaces
        version_++;
    }

    /**
     * Set cell at position.
     */
    void setCell(ushort col, ushort row, dchar ch) nothrow @nogc {
        if (col < cols && row < rows) {
            cells[row * cols + col] = ch;
        }
    }

    /**
     * Get cell at position.
     */
    dchar getCell(ushort col, ushort row) const nothrow @nogc {
        if (col < cols && row < rows) {
            return cells[row * cols + col];
        }
        return ' ';
    }
}

/**
 * IO thread manager for terminal PTY communication.
 *
 * Separates PTY IO from rendering thread following Ghostty pattern:
 * - IO thread reads from PTY, parses VT sequences, updates buffer
 * - Render thread reads from buffer, draws to screen
 * - Lock-free queue for control messages
 * - Double buffer for frame data
 */
class IOThreadManager {
private:
    Thread _ioThread;
    shared bool _running;

    // Message queue for control (main -> IO)
    LockFreeQueue!IOMessage _controlQueue;

    // Message queue for events (IO -> main)
    LockFreeQueue!IOMessage _eventQueue;

    // Double-buffered terminal state
    DoubleBuffer!TerminalBufferState _buffer;

    // Synchronization for frame completion
    Mutex _frameMutex;
    Condition _frameCondition;
    shared bool _frameReady;

    // PTY file descriptor (set externally)
    int _ptyFd = -1;

    // VT parser for escape sequence processing
    VTParser _vtParser;

public:
    this() {
        _frameMutex = new Mutex();
        _frameCondition = new Condition(_frameMutex);
        _running = false;
        _frameReady = false;
        _vtParser = new VTParser();
    }

    /**
     * Set PTY file descriptor for reading.
     */
    void setPtyFd(int fd) {
        _ptyFd = fd;
    }

    /**
     * Start the IO thread.
     */
    void start() {
        if (atomicLoad(_running)) return;

        atomicStore(_running, true);
        _ioThread = new Thread(&ioLoop);
        _ioThread.start();
        trace("IOThreadManager started");
    }

    /**
     * Stop the IO thread.
     */
    void stop() {
        if (!atomicLoad(_running)) return;

        // Send close message
        _controlQueue.push(IOMessage.makeClose());
        atomicStore(_running, false);

        // Wake up thread if waiting
        synchronized (_frameMutex) {
            _frameCondition.notifyAll();
        }

        if (_ioThread !is null) {
            _ioThread.join();
            _ioThread = null;
        }
        trace("IOThreadManager stopped");
    }

    /**
     * Send resize event to IO thread.
     */
    void resize(ushort cols, ushort rows) {
        _controlQueue.push(IOMessage.makeResize(cols, rows));
    }

    /**
     * Get the current read buffer for rendering.
     */
    ref const(TerminalBufferState) getReadBuffer() const {
        return _buffer.readBuffer();
    }

    /**
     * Check if a new frame is ready.
     */
    bool isFrameReady() const {
        return atomicLoad!(MemoryOrder.acq)(_frameReady);
    }

    /**
     * Acknowledge frame consumption (renderer calls this).
     */
    void acknowledgeFrame() {
        atomicStore!(MemoryOrder.rel)(_frameReady, false);
    }

    /**
     * Poll for events from IO thread.
     * Returns true if event was available.
     */
    bool pollEvent(ref IOMessage msg) {
        return _eventQueue.pop(msg);
    }

    /**
     * Check if IO thread is running.
     */
    @property bool running() const {
        return atomicLoad(_running);
    }

private:
    void ioLoop() {
        trace("IO thread started");

        ubyte[4096] readBuffer;

        while (atomicLoad(_running)) {
            // Process control messages
            IOMessage ctrlMsg;
            while (_controlQueue.pop(ctrlMsg)) {
                handleControlMessage(ctrlMsg);
                if (ctrlMsg.type == IOMessageType.Close) {
                    trace("IO thread received close signal");
                    return;
                }
            }

            // Read from PTY using select for non-blocking IO
            bool hasData = false;
            if (_ptyFd >= 0) {
                fd_set readfds;
                FD_ZERO(&readfds);
                FD_SET(_ptyFd, &readfds);

                // Timeout: 1ms to balance responsiveness vs CPU usage
                timeval timeout;
                timeout.tv_sec = 0;
                timeout.tv_usec = 1000;  // 1ms

                int result = select(_ptyFd + 1, &readfds, null, null, &timeout);

                if (result > 0 && FD_ISSET(_ptyFd, &readfds)) {
                    // Data available, read from PTY
                    auto bytesRead = read(_ptyFd, readBuffer.ptr, readBuffer.length);

                    if (bytesRead > 0) {
                        // Parse PTY data through VT parser
                        VTEvent[] events;
                        _vtParser.parse(readBuffer[0..bytesRead], events);

                        // Process parsed events and update buffer
                        processVTEvents(events);
                        hasData = true;
                    } else if (bytesRead == 0) {
                        // PTY closed (EOF)
                        _eventQueue.push(IOMessage.makeClose());
                        tracef("PTY closed (EOF)");
                    } else if (bytesRead < 0) {
                        import core.stdc.errno : errno, EAGAIN, EINTR;
                        if (errno != EAGAIN && errno != EINTR) {
                            // Real error, not just temporary
                            errorf("PTY read error: errno=%d", errno);
                        }
                    }
                } else if (result < 0) {
                    import core.stdc.errno : errno, EINTR;
                    if (errno != EINTR) {
                        errorf("select() error: errno=%d", errno);
                    }
                }
            }

            // Signal frame ready only if we have updates
            if (hasData) {
                signalFrameReady();
            }
        }

        trace("IO thread exiting");
    }

    void handleControlMessage(ref IOMessage msg) {
        switch (msg.type) {
            case IOMessageType.Resize:
                _buffer.writeBuffer.resize(msg.cols, msg.rows);
                tracef("IO thread: resize to %dx%d", msg.cols, msg.rows);
                break;
            default:
                break;
        }
    }

    void processVTEvents(VTEvent[] events) {
        foreach (ref event; events) {
            final switch (event.type) {
                case VTEvent.Type.Text:
                    // Insert character at current cursor position
                    // For now, delegate to VTE (full implementation requires buffer state)
                    break;

                case VTEvent.Type.SGR:
                    // Set graphics rendition (colors, bold, etc.)
                    // Delegate to VTE for now
                    break;

                case VTEvent.Type.CursorMove:
                    // Move cursor to position
                    // Delegate to VTE for now
                    break;

                case VTEvent.Type.EraseDisplay:
                case VTEvent.Type.EraseLine:
                case VTEvent.Type.InsertChars:
                case VTEvent.Type.DeleteChars:
                case VTEvent.Type.ScrollUp:
                case VTEvent.Type.ScrollDown:
                case VTEvent.Type.SetMode:
                case VTEvent.Type.ResetMode:
                    // All complex operations delegate to VTE for now
                    break;

                case VTEvent.Type.DelegateToVTE:
                    // Send raw escape sequence to VTE for processing
                    // This requires wiring back to main thread
                    if (event.rawDataLength > 0) {
                        IOMessage msg = IOMessage.makeData(
                            event.rawData[0..event.rawDataLength].dup
                        );
                        _eventQueue.push(msg);
                    }
                    break;

                case VTEvent.Type.BEL:
                    _eventQueue.push(IOMessage.makeBell());
                    break;

                case VTEvent.Type.BS:
                case VTEvent.Type.HT:
                case VTEvent.Type.LF:
                case VTEvent.Type.CR:
                    // Basic control characters - delegate to VTE for now
                    // Full implementation requires cursor state management
                    break;
            }
        }
    }

    void signalFrameReady() {
        // Swap buffers
        _buffer.swap();
        _buffer.writeBuffer.version_++;

        // Signal frame ready
        atomicStore!(MemoryOrder.rel)(_frameReady, true);

        synchronized (_frameMutex) {
            _frameCondition.notifyAll();
        }
    }
}

@system
unittest {
    // Test LockFreeQueue
    LockFreeQueue!(int, 16) queue;
    assert(queue.empty);
    assert(queue.length == 0);

    assert(queue.push(42));
    assert(!queue.empty);
    assert(queue.length == 1);

    int val;
    assert(queue.pop(val));
    assert(val == 42);
    assert(queue.empty);

    // Fill queue
    foreach (i; 0 .. 15) {
        assert(queue.push(cast(int)i));
    }
    assert(!queue.push(999));  // Should fail, queue full

    queue.clear();
    assert(queue.empty);

    // Test IOMessage creation
    auto dataMsg = IOMessage.makeData([1, 2, 3]);
    assert(dataMsg.type == IOMessageType.Data);

    auto resizeMsg = IOMessage.makeResize(80, 24);
    assert(resizeMsg.type == IOMessageType.Resize);
    assert(resizeMsg.cols == 80);
    assert(resizeMsg.rows == 24);

    // Test DoubleBuffer
    DoubleBuffer!int dbuf;
    dbuf.writeBuffer = 1;
    dbuf.swap();
    assert(dbuf.readBuffer == 1);
    dbuf.writeBuffer = 2;
    assert(dbuf.readBuffer == 1);  // Still old value
    dbuf.swap();
    assert(dbuf.readBuffer == 2);

    // Test TerminalBufferState
    TerminalBufferState state;
    state.resize(80, 24);
    assert(state.cols == 80);
    assert(state.rows == 24);
    assert(state.cells.length == 80 * 24);

    state.setCell(0, 0, 'A');
    assert(state.getCell(0, 0) == 'A');
}
