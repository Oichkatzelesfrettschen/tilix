/**
 * Accessibility Text Extraction
 *
 * Provides text extraction from terminal for screen readers.
 * Converts terminal grid content to accessible text with
 * semantic information.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.accessibility.text;

version (PURE_D_BACKEND):

import std.array : appender, Appender;
import std.range : iota;
import std.algorithm : min;

/**
 * Cursor position in accessible text.
 */
struct AccessibleCursor {
    int row;
    int col;
    int characterOffset;  // Offset into extracted text
}

/**
 * Text range for selection or region.
 */
struct AccessibleRange {
    int startRow;
    int startCol;
    int endRow;
    int endCol;
    int startOffset;  // Offset in extracted text
    int endOffset;
}

/**
 * Extracted accessible text with metadata.
 */
struct AccessibleText {
    string text;
    AccessibleCursor cursor;
    AccessibleRange[] selections;
    int totalRows;
    int totalCols;
    bool hasScrollback;
    int scrollbackLines;
}

/**
 * Interface for terminal text extraction.
 * Implemented by terminal pane to provide text content.
 */
interface IAccessibleTerminal {
    /// Get terminal dimensions
    void getSize(out int cols, out int rows);

    /// Get character at position (0-based)
    dchar getChar(int row, int col);

    /// Get cursor position
    void getCursor(out int row, out int col);

    /// Check if position is in selection
    bool isSelected(int row, int col);

    /// Get scrollback line count
    int scrollbackLines();

    /// Get scrollback character
    dchar getScrollbackChar(int line, int col);
}

/**
 * Text extractor for accessibility.
 *
 * Converts terminal content to accessible text format
 * suitable for screen readers.
 */
class AccessibilityTextExtractor {
private:
    IAccessibleTerminal _terminal;

public:
    this(IAccessibleTerminal terminal) {
        _terminal = terminal;
    }

    /**
     * Extract all visible text.
     */
    AccessibleText extractVisible() {
        if (_terminal is null) {
            return AccessibleText.init;
        }

        int cols, rows;
        _terminal.getSize(cols, rows);

        auto builder = appender!string();
        AccessibleRange[] selections;
        int cursorRow, cursorCol;
        _terminal.getCursor(cursorRow, cursorCol);

        int charOffset = 0;
        int cursorOffset = -1;
        int selStart = -1;
        int selStartRow = -1, selStartCol = -1;

        foreach (row; 0 .. rows) {
            foreach (col; 0 .. cols) {
                dchar ch = _terminal.getChar(row, col);
                bool selected = _terminal.isSelected(row, col);

                // Track cursor position
                if (row == cursorRow && col == cursorCol) {
                    cursorOffset = charOffset;
                }

                // Track selection ranges
                if (selected && selStart < 0) {
                    selStart = charOffset;
                    selStartRow = row;
                    selStartCol = col;
                } else if (!selected && selStart >= 0) {
                    AccessibleRange range;
                    range.startRow = selStartRow;
                    range.startCol = selStartCol;
                    range.endRow = row;
                    range.endCol = col > 0 ? col - 1 : 0;
                    range.startOffset = selStart;
                    range.endOffset = charOffset;
                    selections ~= range;
                    selStart = -1;
                }

                builder.put(ch == 0 ? ' ' : ch);
                charOffset++;
            }
            builder.put('\n');
            charOffset++;
        }

        // Close any open selection at end
        if (selStart >= 0) {
            AccessibleRange range;
            range.startRow = selStartRow;
            range.startCol = selStartCol;
            range.endRow = rows - 1;
            range.endCol = cols - 1;
            range.startOffset = selStart;
            range.endOffset = charOffset;
            selections ~= range;
        }

        AccessibleText result;
        result.text = builder.data;
        result.cursor.row = cursorRow;
        result.cursor.col = cursorCol;
        result.cursor.characterOffset = cursorOffset >= 0 ? cursorOffset : 0;
        result.selections = selections;
        result.totalRows = rows;
        result.totalCols = cols;
        result.hasScrollback = _terminal.scrollbackLines() > 0;
        result.scrollbackLines = _terminal.scrollbackLines();

        return result;
    }

    /**
     * Extract text for a specific row range.
     */
    string extractRows(int startRow, int endRow) {
        if (_terminal is null) {
            return "";
        }

        int cols, rows;
        _terminal.getSize(cols, rows);

        startRow = min(startRow, rows - 1);
        endRow = min(endRow, rows - 1);
        if (startRow < 0) startRow = 0;
        if (endRow < startRow) endRow = startRow;

        auto builder = appender!string();
        foreach (row; startRow .. endRow + 1) {
            foreach (col; 0 .. cols) {
                dchar ch = _terminal.getChar(row, col);
                builder.put(ch == 0 ? ' ' : ch);
            }
            if (row < endRow) {
                builder.put('\n');
            }
        }

        return builder.data;
    }

    /**
     * Extract current line with cursor.
     */
    string extractCurrentLine() {
        if (_terminal is null) {
            return "";
        }

        int cursorRow, cursorCol;
        _terminal.getCursor(cursorRow, cursorCol);

        return extractRows(cursorRow, cursorRow);
    }

    /**
     * Get word at cursor position.
     */
    string getWordAtCursor() {
        if (_terminal is null) {
            return "";
        }

        int cols, rows;
        _terminal.getSize(cols, rows);

        int cursorRow, cursorCol;
        _terminal.getCursor(cursorRow, cursorCol);

        // Find word boundaries
        int wordStart = cursorCol;
        int wordEnd = cursorCol;

        // Search backward for word start
        while (wordStart > 0) {
            dchar ch = _terminal.getChar(cursorRow, wordStart - 1);
            if (!isWordChar(ch)) break;
            wordStart--;
        }

        // Search forward for word end
        while (wordEnd < cols - 1) {
            dchar ch = _terminal.getChar(cursorRow, wordEnd + 1);
            if (!isWordChar(ch)) break;
            wordEnd++;
        }

        // Extract word
        auto builder = appender!string();
        foreach (col; wordStart .. wordEnd + 1) {
            dchar ch = _terminal.getChar(cursorRow, col);
            if (ch != 0) builder.put(ch);
        }

        return builder.data;
    }

    /**
     * Extract scrollback text.
     */
    string extractScrollback(int startLine, int lineCount) {
        if (_terminal is null) {
            return "";
        }

        int cols, rows;
        _terminal.getSize(cols, rows);

        int scrollback = _terminal.scrollbackLines();
        if (scrollback == 0) {
            return "";
        }

        startLine = min(startLine, scrollback - 1);
        if (startLine < 0) startLine = 0;

        int endLine = min(startLine + lineCount, scrollback);

        auto builder = appender!string();
        foreach (line; startLine .. endLine) {
            foreach (col; 0 .. cols) {
                dchar ch = _terminal.getScrollbackChar(line, col);
                builder.put(ch == 0 ? ' ' : ch);
            }
            if (line < endLine - 1) {
                builder.put('\n');
            }
        }

        return builder.data;
    }

private:
    bool isWordChar(dchar ch) {
        if (ch >= 'a' && ch <= 'z') return true;
        if (ch >= 'A' && ch <= 'Z') return true;
        if (ch >= '0' && ch <= '9') return true;
        if (ch == '_' || ch == '-' || ch == '.') return true;
        return false;
    }
}

// Unit tests
unittest {
    // Test AccessibleCursor initialization
    AccessibleCursor cursor;
    assert(cursor.row == 0);
    assert(cursor.col == 0);
}

unittest {
    // Test AccessibleRange initialization
    AccessibleRange range;
    assert(range.startRow == 0);
    assert(range.endRow == 0);
}
