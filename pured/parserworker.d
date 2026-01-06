/**
 * Emulator parser worker thread.
 *
 * Consumes byte chunks, feeds the emulator, and publishes frames.
 */
module pured.parserworker;

version (PURE_D_BACKEND):

import core.atomic : atomicLoad, atomicStore, atomicOp, MemoryOrder;
import core.sync.condition : Condition;
import core.sync.mutex : Mutex;
import core.thread : Thread;
import core.time : MonoTime;
import pured.emulator : PureDEmulator;
import pured.terminal.frame : TerminalFrame;
import pured.terminal.scrollback_buffer : ScrollbackBuffer;
import pured.util.byte_ring : ByteRing;
import pured.util.delimiter_scan : findDelimiter;
import pured.util.triplebuffer : TripleBuffer;

class ParserWorker {
private:
    PureDEmulator _emulator;
    TripleBuffer!TerminalFrame* _frames;
    ScrollbackBuffer _scrollbackBuffer;
    Mutex _scrollbackMutex;
    size_t _scrollbackLen;
    int _scrollbackStart;
    size_t _scrollbackMaxLines;
    ByteRing _ring;
    Mutex _ringMutex;
    Condition _ringNotEmpty;
    Condition _ringNotFull;
    Thread _thread;
    Mutex _emulatorMutex;
    shared bool _running;
    size_t _ringCapacity = 1 << 20;
    ubyte[] _chunkBuffer;
    ulong _frameSequence;
    shared size_t _bytesProcessed;

public:
    this(PureDEmulator emulator,
         ref TripleBuffer!TerminalFrame frames,
         ScrollbackBuffer scrollbackBuffer,
         Mutex scrollbackMutex,
         size_t scrollbackMaxLines) {
        _emulator = emulator;
        _frames = &frames;
        _scrollbackBuffer = scrollbackBuffer;
        _scrollbackMutex = scrollbackMutex;
        _scrollbackMaxLines = scrollbackMaxLines;
        _ring = ByteRing(_ringCapacity);
        _ringMutex = new Mutex();
        _ringNotEmpty = new Condition(_ringMutex);
        _ringNotFull = new Condition(_ringMutex);
        _emulatorMutex = new Mutex();
        _chunkBuffer.length = 16 * 1024;
    }

    void start() {
        if (isRunning) {
            return;
        }
        atomicStore!(MemoryOrder.raw)(_running, true);
        _thread = new Thread(&runLoop);
        _thread.isDaemon = true;
        _thread.start();
    }

    void stop() {
        if (!isRunning) {
            return;
        }
        atomicStore!(MemoryOrder.raw)(_running, false);
        _ringMutex.lock();
        _ringNotEmpty.notifyAll();
        _ringNotFull.notifyAll();
        _ringMutex.unlock();
        if (_thread !is null) {
            _thread.join();
            _thread = null;
        }
    }

    @property bool isRunning() const {
        return atomicLoad!(MemoryOrder.raw)(_running);
    }

    void enqueue(const(ubyte)[] data) {
        if (!isRunning || data.length == 0) {
            return;
        }
        size_t offset = 0;
        _ringMutex.lock();
        scope(exit) _ringMutex.unlock();

        while (offset < data.length && atomicLoad!(MemoryOrder.raw)(_running)) {
            while (_ring.available == 0 && atomicLoad!(MemoryOrder.raw)(_running)) {
                _ringNotFull.wait();
            }
            if (!atomicLoad!(MemoryOrder.raw)(_running)) {
                break;
            }
            auto written = _ring.write(data[offset .. $]);
            if (written == 0) {
                continue;
            }
            offset += written;
            _ringNotEmpty.notify();
        }
    }

    void resize(int cols, int rows) {
        if (_emulator is null) {
            return;
        }
        _emulatorMutex.lock();
        scope(exit) _emulatorMutex.unlock();
        _emulator.resize(cols, rows);
        syncScrollbackLocked();
        publishFrameLocked();
    }

    void setScrollbackMaxLines(size_t maxLines) {
        if (maxLines == 0) {
            return;
        }
        _scrollbackMutex.lock();
        scope(exit) _scrollbackMutex.unlock();
        _scrollbackMaxLines = maxLines;
    }

    @property size_t totalBytesProcessed() const {
        return atomicLoad!(MemoryOrder.acq)(_bytesProcessed);
    }

private:
    void runLoop() {
        while (atomicLoad!(MemoryOrder.raw)(_running)) {
            size_t readCount = 0;

            _ringMutex.lock();
            while (_ring.isEmpty && atomicLoad!(MemoryOrder.raw)(_running)) {
                _ringNotEmpty.wait();
            }
            if (!atomicLoad!(MemoryOrder.raw)(_running)) {
                _ringMutex.unlock();
                break;
            }
            readCount = _ring.read(_chunkBuffer);
            if (readCount > 0) {
                _ringNotFull.notify();
            }
            _ringMutex.unlock();

            if (readCount == 0) {
                continue;
            }

            _emulatorMutex.lock();
            scope(exit) _emulatorMutex.unlock();
            feedChunk(_chunkBuffer[0 .. readCount]);
        }
    }

    void publishFrameLocked() {
        if (_emulator is null || _frames is null) {
            return;
        }
        auto screen = _emulator.getScreenBuffer();
        auto ref back = (*_frames).writeBuffer;
        back.updateFromCells(
            screen,
            _emulator.cols,
            _emulator.rows,
            _emulator.cursorCol,
            _emulator.cursorRow,
            _emulator.isAlternateScreen,
            _emulator.applicationCursorMode,
            _emulator.mouseMode,
            _emulator.mouseEncoding,
            _emulator.bracketedPasteModeEnabled,
            _emulator.focusReportingEnabled
        );
        back.publishTime = MonoTime.currTime;
        back.sequence = ++_frameSequence;
        (*_frames).publish();
    }

    void feedChunk(const(ubyte)[] chunk) {
        atomicOp!"+="(_bytesProcessed, chunk.length);
        size_t offset = 0;
        while (offset < chunk.length) {
            size_t hit = findDelimiter(chunk[offset .. $], cast(ubyte)'\n', cast(ubyte)'\x1b');
            if (hit == size_t.max) {
                _emulator.feedData(chunk[offset .. $]);
                syncScrollbackLocked();
                publishFrameLocked();
                break;
            }
            size_t end = offset + hit + 1;
            _emulator.feedData(chunk[offset .. end]);
            syncScrollbackLocked();
            publishFrameLocked();
            offset = end;
        }
    }

    void syncScrollbackLocked() {
        if (_scrollbackBuffer is null) {
            return;
        }

        int currentStart = _emulator.scrollbackStartIndex();
        size_t currentLen = _emulator.scrollbackLineCount();

        _scrollbackMutex.lock();
        scope(exit) _scrollbackMutex.unlock();

        if (_scrollbackBuffer.cols != cast(size_t)_emulator.cols ||
            _scrollbackBuffer.maxLines != _scrollbackMaxLines) {
            _scrollbackBuffer.initialize(_emulator.cols, _scrollbackMaxLines);
            _scrollbackLen = 0;
            _scrollbackStart = currentStart;
        }

        if (currentLen == 0) {
            _scrollbackBuffer.clear();
            _scrollbackLen = 0;
            _scrollbackStart = currentStart;
            return;
        }

        if (currentLen < _scrollbackLen ||
            (currentLen == _scrollbackLen && currentStart != _scrollbackStart)) {
            _scrollbackBuffer.clear();
            foreach (i; 0 .. currentLen) {
                _scrollbackBuffer.pushLine(_emulator.scrollbackLine(i));
            }
        } else if (currentLen > _scrollbackLen) {
            foreach (i; _scrollbackLen .. currentLen) {
                _scrollbackBuffer.pushLine(_emulator.scrollbackLine(i));
            }
        }

        _scrollbackLen = currentLen;
        _scrollbackStart = currentStart;
    }
}
