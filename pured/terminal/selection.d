/**
 * Terminal Selection System
 *
 * Handles text selection, word/line boundaries, and clipboard integration.
 * Supports drag selection, double-click word select, triple-click line select.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.terminal.selection;

version (PURE_D_BACKEND):

import std.algorithm : min, max, canFind;
import std.array : array, appender;
import std.uni : isWhite, isAlphaNum;

/**
 * A point in the terminal buffer.
 */
struct BufferPoint {
    int col;
    int row;  // Row in buffer (including scrollback)

    int opCmp(ref const BufferPoint other) const @nogc nothrow {
        if (row != other.row) return row - other.row;
        return col - other.col;
    }

    bool opEquals(ref const BufferPoint other) const @nogc nothrow {
        return col == other.col && row == other.row;
    }
}

/**
 * Selection type.
 */
enum SelectionType {
    none,       /// No selection
    character,  /// Character-level selection (drag)
    word,       /// Word selection (double-click)
    line,       /// Line selection (triple-click)
    block,      /// Rectangular/block selection (Alt+drag)
}

/**
 * Selection state and operations.
 *
 * Manages the current selection, provides methods for selection manipulation,
 * and handles coordinate translation between screen and buffer.
 */
class Selection {
private:
    BufferPoint _anchor;     // Where selection started
    BufferPoint _cursor;     // Current end of selection
    SelectionType _type = SelectionType.none;
    bool _active;            // Currently dragging

    // For word boundaries
    dchar delegate(int col, int row) _getChar;

public:
    /**
     * Create selection manager.
     *
     * Params:
     *   getChar = Delegate to get character at buffer position
     */
    this(dchar delegate(int col, int row) getChar) {
        _getChar = getChar;
    }

    /**
     * Start a new selection.
     *
     * Params:
     *   col = Column position
     *   row = Row in buffer
     *   type = Type of selection (character, word, line)
     */
    void start(int col, int row, SelectionType type = SelectionType.character) {
        _anchor = BufferPoint(col, row);
        _cursor = _anchor;
        _type = type;
        _active = true;

        // Expand to word/line if needed
        if (type == SelectionType.word) {
            expandToWord(_anchor);
        } else if (type == SelectionType.line) {
            expandToLine(_anchor);
        }
    }

    /**
     * Update selection during drag.
     */
    void update(int col, int row) {
        if (!_active) return;

        _cursor = BufferPoint(col, row);

        // Word/line selection expands from anchor
        if (_type == SelectionType.word) {
            // Keep anchor word, expand cursor to word boundary
            if (_cursor < _anchor) {
                _cursor = wordStart(_cursor.col, _cursor.row);
            } else {
                _cursor = wordEnd(_cursor.col, _cursor.row);
            }
        } else if (_type == SelectionType.line) {
            // Whole line selection
            _cursor.col = _cursor < _anchor ? 0 : int.max;
        }
    }

    /**
     * Finish selection.
     */
    void finish() {
        _active = false;
        // Keep selection visible until cleared
    }

    /**
     * Clear selection.
     */
    void clear() {
        _type = SelectionType.none;
        _active = false;
    }

    /**
     * Extend selection to new position (Shift+click).
     */
    void extend(int col, int row) {
        if (_type == SelectionType.none) {
            start(col, row);
            return;
        }

        _cursor = BufferPoint(col, row);
        _active = true;
    }

    /**
     * Check if a cell is within the selection.
     */
    bool isSelected(int col, int row) const @nogc nothrow {
        if (_type == SelectionType.none)
            return false;

        auto p = BufferPoint(col, row);
        auto start = selectionStart;
        auto end = selectionEnd;

        if (_type == SelectionType.block) {
            // Block selection: rectangular region
            int startCol = min(_anchor.col, _cursor.col);
            int endCol = max(_anchor.col, _cursor.col);
            int startRow = min(_anchor.row, _cursor.row);
            int endRow = max(_anchor.row, _cursor.row);
            return col >= startCol && col <= endCol &&
                   row >= startRow && row <= endRow;
        }

        // Linear selection
        if (row < start.row || row > end.row)
            return false;

        if (row == start.row && row == end.row)
            return col >= start.col && col < end.col;

        if (row == start.row)
            return col >= start.col;

        if (row == end.row)
            return col < end.col;

        return true;  // Middle row
    }

    /**
     * Get selected text.
     *
     * Params:
     *   getCellText = Delegate to get text at position
     *   maxCols = Maximum columns per line
     *
     * Returns: Selected text with newlines between rows
     */
    string getSelectedText(dchar delegate(int col, int row) getCellText, int maxCols) const {
        if (_type == SelectionType.none)
            return "";

        auto result = appender!string();
        auto start = selectionStart;
        auto end = selectionEnd;

        foreach (row; start.row .. end.row + 1) {
            int startCol = (row == start.row) ? start.col : 0;
            int endCol = (row == end.row) ? end.col : maxCols;

            // Trim trailing spaces
            int lastNonSpace = startCol;
            foreach (col; startCol .. endCol) {
                dchar ch = getCellText(col, row);
                if (ch != ' ' && ch != 0)
                    lastNonSpace = col + 1;
            }

            foreach (col; startCol .. lastNonSpace) {
                dchar ch = getCellText(col, row);
                if (ch == 0) ch = ' ';
                char[4] buf;
                auto len = encode(ch, buf);
                result ~= buf[0 .. len];
            }

            // Add newline between rows (not after last)
            if (row < end.row)
                result ~= '\n';
        }

        return result.data;
    }

    /// Get normalized start point (whichever is first)
    @property BufferPoint selectionStart() const @nogc nothrow {
        return _anchor < _cursor ? _anchor : _cursor;
    }

    /// Get normalized end point
    @property BufferPoint selectionEnd() const @nogc nothrow {
        return _anchor < _cursor ? _cursor : _anchor;
    }

    /// True if selection is active (dragging)
    @property bool active() const @nogc nothrow { return _active; }

    /// True if selection is active (non-empty)
    @property bool hasSelection() const @nogc nothrow { return _type != SelectionType.none; }

    /// Current selection type
    @property SelectionType type() const { return _type; }

private:
    /**
     * Expand anchor to full word.
     */
    void expandToWord(ref BufferPoint pt) {
        auto start = wordStart(pt.col, pt.row);
        auto end = wordEnd(pt.col, pt.row);
        _anchor = start;
        _cursor = end;
    }

    /**
     * Expand anchor to full line.
     */
    void expandToLine(ref BufferPoint pt) {
        _anchor = BufferPoint(0, pt.row);
        _cursor = BufferPoint(int.max, pt.row);  // Will be clamped
    }

    /**
     * Find start of word containing position.
     */
    BufferPoint wordStart(int col, int row) {
        if (_getChar is null)
            return BufferPoint(col, row);

        dchar ch = _getChar(col, row);
        bool isWord = isWordChar(ch);

        while (col > 0) {
            dchar prevCh = _getChar(col - 1, row);
            if (isWordChar(prevCh) != isWord)
                break;
            col--;
        }

        return BufferPoint(col, row);
    }

    /**
     * Find end of word containing position.
     */
    BufferPoint wordEnd(int col, int row) {
        if (_getChar is null)
            return BufferPoint(col + 1, row);

        dchar ch = _getChar(col, row);
        bool isWord = isWordChar(ch);

        // Arbitrary max to prevent infinite loop
        enum MAX_COL = 1000;
        while (col < MAX_COL) {
            dchar nextCh = _getChar(col + 1, row);
            if (nextCh == 0 || isWordChar(nextCh) != isWord)
                break;
            col++;
        }

        return BufferPoint(col + 1, row);
    }

    /**
     * Check if character is part of a word.
     */
    static bool isWordChar(dchar ch) {
        if (ch == 0 || ch == ' ')
            return false;
        // Consider alphanumeric and common programming chars as word chars
        return ch.isAlphaNum || ch == '_' || ch == '-';
    }

    /**
     * Encode single character to UTF-8.
     */
    static size_t encode(dchar c, ref char[4] buf) {
        if (c < 0x80) {
            buf[0] = cast(char)c;
            return 1;
        } else if (c < 0x800) {
            buf[0] = cast(char)(0xC0 | (c >> 6));
            buf[1] = cast(char)(0x80 | (c & 0x3F));
            return 2;
        } else if (c < 0x10000) {
            buf[0] = cast(char)(0xE0 | (c >> 12));
            buf[1] = cast(char)(0x80 | ((c >> 6) & 0x3F));
            buf[2] = cast(char)(0x80 | (c & 0x3F));
            return 3;
        } else {
            buf[0] = cast(char)(0xF0 | (c >> 18));
            buf[1] = cast(char)(0x80 | ((c >> 12) & 0x3F));
            buf[2] = cast(char)(0x80 | ((c >> 6) & 0x3F));
            buf[3] = cast(char)(0x80 | (c & 0x3F));
            return 4;
        }
    }
}

/**
 * Click counter for detecting double/triple clicks.
 */
struct ClickDetector {
    import core.time : MonoTime, Duration, dur;

    private {
        MonoTime _lastClickTime;
        BufferPoint _lastClickPos;
        int _clickCount;
        Duration _doubleClickThreshold = dur!"msecs"(500);
        int _positionThreshold = 3;  // Max distance for same-position click
    }

    /**
     * Register a click and return the click count (1, 2, or 3).
     */
    int click(int col, int row) {
        auto now = MonoTime.currTime;
        auto pos = BufferPoint(col, row);

        // Check if this is a continuation of previous clicks
        auto elapsed = now - _lastClickTime;
        int distance = abs(pos.col - _lastClickPos.col) + abs(pos.row - _lastClickPos.row);

        if (elapsed < _doubleClickThreshold && distance <= _positionThreshold) {
            _clickCount = (_clickCount % 3) + 1;  // Cycle 1 -> 2 -> 3 -> 1
        } else {
            _clickCount = 1;
        }

        _lastClickTime = now;
        _lastClickPos = pos;

        return _clickCount;
    }

    /**
     * Get selection type for current click count.
     */
    SelectionType selectionType() const {
        switch (_clickCount) {
            case 1: return SelectionType.character;
            case 2: return SelectionType.word;
            case 3: return SelectionType.line;
            default: return SelectionType.character;
        }
    }

    private static int abs(int x) {
        return x < 0 ? -x : x;
    }
}
