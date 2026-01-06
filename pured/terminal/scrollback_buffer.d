/**
 * Scrollback Buffer (mmap-backed).
 *
 * Stores a fixed number of lines as TerminalCell rows in a ring buffer.
 */
module pured.terminal.scrollback_buffer;

version (PURE_D_BACKEND):

import arsd.terminalemulator : TerminalEmulator;
import core.sys.posix.sys.mman : mmap, munmap, PROT_READ, PROT_WRITE, MAP_ANON, MAP_PRIVATE, MAP_FAILED;
import core.stdc.errno : errno;
import core.stdc.string : strerror;
import std.algorithm : min, max;
import std.stdio : stderr, writefln;

alias TerminalCell = TerminalEmulator.TerminalCell;

class ScrollbackBuffer {
private:
    TerminalCell* _cells;
    size_t _mappedBytes;
    size_t _cols;
    size_t _maxLines;
    size_t _count;
    size_t _headLine;

public:
    this() {
    }

    bool initialize(size_t cols, size_t maxLines) {
        terminate();

        if (cols == 0 || maxLines == 0) {
            return false;
        }

        _cols = cols;
        _maxLines = maxLines;
        _count = 0;
        _headLine = 0;

        size_t bytesPerLine = _cols * TerminalCell.sizeof;
        if (bytesPerLine == 0 || maxLines > size_t.max / bytesPerLine) {
            return false;
        }

        _mappedBytes = bytesPerLine * maxLines;
        auto ptr = mmap(null, _mappedBytes, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
        if (ptr == MAP_FAILED) {
            stderr.writefln("Scrollback mmap failed: %s", strerror(errno));
            _mappedBytes = 0;
            return false;
        }

        _cells = cast(TerminalCell*)ptr;
        clear();
        return true;
    }

    void terminate() {
        if (_cells !is null && _mappedBytes > 0) {
            munmap(_cells, _mappedBytes);
        }
        _cells = null;
        _mappedBytes = 0;
        _cols = 0;
        _maxLines = 0;
        _count = 0;
        _headLine = 0;
    }

    void clear() {
        if (_cells is null) {
            return;
        }
        size_t totalCells = _cols * _maxLines;
        foreach (i; 0 .. totalCells) {
            _cells[i] = TerminalCell.init;
        }
        _count = 0;
        _headLine = 0;
    }

    void pushLine(const(TerminalCell)[] line) {
        if (_cells is null || _cols == 0 || _maxLines == 0) {
            return;
        }

        size_t lineIndex = _headLine % _maxLines;
        auto dest = _cells + (lineIndex * _cols);
        size_t copyLen = min(line.length, _cols);

        foreach (i; 0 .. copyLen) {
            dest[i] = cast(TerminalCell)line[i];
        }
        foreach (i; copyLen .. _cols) {
            dest[i] = TerminalCell.init;
        }

        _headLine = (_headLine + 1) % _maxLines;
        if (_count < _maxLines) {
            _count++;
        }
    }

    TerminalCell[] lineView(size_t indexFromOldest) {
        if (_cells is null || indexFromOldest >= _count) {
            return null;
        }

        size_t oldest = (_headLine + _maxLines - _count) % _maxLines;
        size_t lineIndex = (oldest + indexFromOldest) % _maxLines;
        auto start = _cells + (lineIndex * _cols);
        return start[0 .. _cols];
    }

    bool copyLine(size_t indexFromOldest, ref TerminalCell[] outLine) {
        auto view = lineView(indexFromOldest);
        if (view is null) {
            return false;
        }
        if (outLine.length != _cols) {
            outLine.length = _cols;
        }
        foreach (i; 0 .. _cols) {
            outLine[i] = view[i];
        }
        return true;
    }

    @property size_t lineCount() const {
        return _count;
    }

    @property size_t maxLines() const {
        return _maxLines;
    }

    @property size_t cols() const {
        return _cols;
    }
}

unittest {
    auto sb = new ScrollbackBuffer();
    assert(sb.initialize(4, 3));

    TerminalCell[] line;
    line.length = 4;
    foreach (i; 0 .. 4) {
        line[i] = TerminalCell.init;
    }

    line[0].ch = 'A';
    sb.pushLine(line);
    line[0].ch = 'B';
    sb.pushLine(line);
    line[0].ch = 'C';
    sb.pushLine(line);
    assert(sb.lineCount == 3);
    assert(sb.lineView(0)[0].ch == 'A');
    assert(sb.lineView(2)[0].ch == 'C');

    line[0].ch = 'D';
    sb.pushLine(line);
    assert(sb.lineCount == 3);
    assert(sb.lineView(0)[0].ch == 'B');
    assert(sb.lineView(2)[0].ch == 'D');

    sb.terminate();
}
