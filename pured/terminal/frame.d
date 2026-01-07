/**
 * Terminal frame snapshot.
 *
 * Captures the visible screen state for renderer handoff.
 */
module pured.terminal.frame;

version (PURE_D_BACKEND):

import arsd.terminalemulator : TerminalEmulator;
import core.time : MonoTime;
import pured.platform.input_types : MouseMode, MouseEncoding;
import mir.ndslice : Slice, sliced;

alias TerminalCell = TerminalEmulator.TerminalCell;

struct TerminalFrame {
    TerminalCell[] cells;
    int cols;
    int rows;
    int cursorCol;
    int cursorRow;
    bool alternateScreen;
    bool applicationCursorMode;
    MouseMode mouseMode;
    MouseEncoding mouseEncoding;
    bool bracketedPasteMode;
    bool focusReporting;
    MonoTime publishTime;
    ulong sequence;

    @property auto grid() {
        return cells.sliced(rows, cols);
    }

    void ensureSize(int cols, int rows) {
        this.cols = cols;
        this.rows = rows;
        auto len = cols * rows;
        if (cells.length != len) {
            cells.length = len;
        }
    }

    void updateFromCells(const(TerminalCell)[] src,
                         int cols,
                         int rows,
                         int cursorCol,
                         int cursorRow,
                         bool alternateScreen,
                         bool applicationCursorMode,
                         MouseMode mouseMode,
                         MouseEncoding mouseEncoding,
                         bool bracketedPasteMode,
                         bool focusReporting) {
        ensureSize(cols, rows);
        size_t len = cells.length;
        if (src.length >= len) {
            foreach (i; 0 .. len) {
                cells[i] = cast(TerminalCell)src[i];
            }
        } else {
            foreach (i; 0 .. src.length) {
                cells[i] = cast(TerminalCell)src[i];
            }
            foreach (i; src.length .. len) {
                cells[i] = TerminalCell.init;
            }
        }
        this.cursorCol = cursorCol;
        this.cursorRow = cursorRow;
        this.alternateScreen = alternateScreen;
        this.applicationCursorMode = applicationCursorMode;
        this.mouseMode = mouseMode;
        this.mouseEncoding = mouseEncoding;
        this.bracketedPasteMode = bracketedPasteMode;
        this.focusReporting = focusReporting;
    }
}
