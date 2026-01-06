/**
 * Terminal Emulator Adapter
 *
 * Bridges arsd.terminalemulator to the Pure D rendering backend.
 * Subclasses TerminalEmulator to implement required callbacks and
 * provides access to screen state for OpenGL rendering.
 *
 * Key features:
 * - VT100/ANSI escape sequence parsing via arsd
 * - Screen cell access for rendering
 * - Cursor position tracking
 * - Window title change notifications
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.emulator;

version (PURE_D_BACKEND):

import arsd.terminalemulator;
import pured.platform.input : MouseMode, MouseEncoding;
import arsd.color : Color, IndexedImage;
import pured.config : ResolvedTheme, defaultResolvedTheme;
import std.stdio : stderr, writefln;

/**
 * Callback interface for terminal events.
 *
 * Implement this to receive notifications from the emulator.
 */
interface ITerminalCallbacks {
    /// Called when the window title changes
    void onTitleChanged(string title);

    /// Called when data should be sent to the PTY
    void onSendToApplication(scope const(void)[] data);

    /// Called when the bell should sound
    void onBell();

    /// Called when the application requests exit
    void onRequestExit();

    /// Called when cursor style changes
    void onCursorStyleChanged(TerminalEmulator.CursorStyle style);

    /// Called when emulator wants to set clipboard text
    void onCopyToClipboard(string text);

    /// Called when emulator wants to set PRIMARY selection text
    void onCopyToPrimary(string text);

    /// Called when emulator requests clipboard contents
    string onPasteFromClipboard();

    /// Called when emulator requests PRIMARY selection contents
    string onPasteFromPrimary();
}

/**
 * Terminal emulator adapter for Pure D backend.
 *
 * Wraps arsd.terminalemulator and provides:
 * - PTY data input via feedData()
 * - Screen cell access via getCell()
 * - Cursor position via cursorX/cursorY
 */
class PureDEmulator : TerminalEmulator {
private:
    ITerminalCallbacks _callbacks;
    string _windowTitle;
    string _iconTitle;
    CursorStyle _cursorStyle;

public:
    /**
     * Create a new terminal emulator.
     *
     * Params:
     *   cols = Terminal width in columns
     *   rows = Terminal height in rows
     *   callbacks = Optional callback interface for events
     */
    this(int cols, int rows, ITerminalCallbacks callbacks = null) {
        // Call parent constructor which initializes the terminal
        super(cols, rows);

        _callbacks = callbacks;
        _windowTitle = "Terminal";
        _iconTitle = "Terminal";
        _cursorStyle = CursorStyle.block;
    }

    /**
     * Feed raw PTY data to the emulator.
     *
     * This processes escape sequences and updates the screen buffer.
     *
     * Params:
     *   data = Raw bytes from PTY
     */
    void feedData(const(ubyte)[] data) {
        sendRawInput(data);
    }

    /**
     * Resize the terminal.
     *
     * Params:
     *   cols = New width in columns
     *   rows = New height in rows
     */
    void resize(int cols, int rows) {
        resizeTerminal(cols, rows);
    }

    /**
     * Get a cell from the current screen buffer.
     *
     * Params:
     *   x = Column (0-based)
     *   y = Row (0-based)
     *
     * Returns: The terminal cell at (x, y)
     */
    TerminalCell getCell(int x, int y) {
        if (x < 0 || x >= screenWidth || y < 0 || y >= screenHeight) {
            TerminalCell empty;
            return empty;
        }

        auto screen = alternateScreenActive ? alternateScreen : normalScreen;
        auto idx = y * screenWidth + x;

        if (idx >= 0 && idx < screen.length) {
            return screen[idx];
        }

        TerminalCell empty;
        return empty;
    }

    /**
     * Get the current screen buffer directly.
     *
     * Returns: Array of terminal cells for the visible screen
     */
    TerminalCell[] getScreenBuffer() {
        return alternateScreenActive ? alternateScreen : normalScreen;
    }

    /**
     * Scrollback line count.
     */
    size_t scrollbackLineCount() {
        return scrollbackBuffer.length();
    }

    /**
     * Scrollback ring start index.
     */
    int scrollbackStartIndex() {
        return scrollbackBuffer.start;
    }

    /**
     * Fetch a scrollback line by index (0 = oldest).
     */
    TerminalCell[] scrollbackLine(size_t index) {
        return scrollbackBuffer[cast(int)index];
    }

    @property bool applicationCursorMode() const {
        return applicationCursorKeys;
    }

    @property MouseMode mouseMode() {
        if (mouseMotionTracking) {
            return MouseMode.anyEvent;
        }
        if (mouseButtonMotionTracking) {
            return MouseMode.buttonEvent;
        }
        if (selectiveMouseTracking) {
            return MouseMode.highlight;
        }
        if (mouseButtonTracking || mouseButtonReleaseTracking) {
            return MouseMode.normal;
        }
        return MouseMode.none;
    }

    @property MouseEncoding mouseEncoding() {
        if (sgrMouseMode) {
            return MouseEncoding.sgr;
        }
        if (urxvtMouseMode) {
            return MouseEncoding.urxvt;
        }
        if (utf8MouseMode) {
            return MouseEncoding.utf8;
        }
        return MouseEncoding.x10;
    }

    @property bool bracketedPasteModeEnabled() {
        return bracketedPasteMode;
    }

    @property bool focusReportingEnabled() {
        return sendFocusEvents;
    }

    /**
     * Check if alternate screen (used by vim, etc.) is active.
     */
    @property bool isAlternateScreen() const {
        return alternateScreenActive;
    }

    /// Terminal width in columns
    @property int cols() const {
        return screenWidth;
    }

    /// Terminal height in rows
    @property int rows() const {
        return screenHeight;
    }

    /// Current cursor X position (column)
    @property int cursorCol() {
        return cursorX;
    }

    /// Current cursor Y position (row)
    @property int cursorRow() {
        return cursorY;
    }

    /// Current window title
    @property string windowTitle() const {
        return _windowTitle;
    }

    /// Current cursor style
    @property CursorStyle cursorStyle() const {
        return _cursorStyle;
    }

    /// Set callback interface
    void setCallbacks(ITerminalCallbacks callbacks) {
        _callbacks = callbacks;
    }

protected:
    // === Abstract method implementations ===

    override void changeWindowTitle(string title) {
        _windowTitle = title;
        if (_callbacks !is null) {
            _callbacks.onTitleChanged(title);
        }
    }

    override void changeIconTitle(string title) {
        _iconTitle = title;
    }

    override void changeWindowIcon(IndexedImage icon) {
        // Not implemented - GLFW handles window icon differently
    }

    override void changeCursorStyle(CursorStyle style) {
        _cursorStyle = style;
        if (_callbacks !is null) {
            _callbacks.onCursorStyleChanged(style);
        }
    }

    override void changeTextAttributes(TextAttributes attrs) {
        // Text attributes are tracked internally by the emulator
        // We read them from cells during rendering
    }

    override void soundBell() {
        if (_callbacks !is null) {
            _callbacks.onBell();
        }
    }

    override void sendToApplication(scope const(void)[] data) {
        if (_callbacks !is null) {
            _callbacks.onSendToApplication(data);
        }
    }

    override void copyToClipboard(string text) {
        if (_callbacks !is null) {
            _callbacks.onCopyToClipboard(text);
        }
    }

    override void pasteFromClipboard(void delegate(in char[]) callback) {
        if (callback !is null) {
            if (_callbacks is null) {
                callback("");
                return;
            }
            auto text = _callbacks.onPasteFromClipboard();
            callback(text);
        }
    }

    override void copyToPrimary(string text) {
        if (_callbacks !is null) {
            _callbacks.onCopyToPrimary(text);
        }
    }

    override void pasteFromPrimary(void delegate(in char[]) callback) {
        if (callback !is null) {
            if (_callbacks is null) {
                callback("");
                return;
            }
            auto text = _callbacks.onPasteFromPrimary();
            callback(text);
        }
    }

    override void requestExit() {
        if (_callbacks !is null) {
            _callbacks.onRequestExit();
        }
    }
}

/**
 * Convert arsd TextAttributes to RGBA colors.
 *
 * Params:
 *   attrs = Text attributes from terminal cell
 *   fg = Output foreground color (r, g, b, a as 0.0-1.0)
 *   bg = Output background color (r, g, b, a as 0.0-1.0)
 */
void attributesToColors(ref TerminalEmulator.TextAttributes attrs,
                        out float[4] fg, out float[4] bg,
                        const(ResolvedTheme)* theme = null) {
    const(ResolvedTheme)* resolved = theme is null ? defaultResolvedTheme() : theme;
    fg = resolved.foreground;
    bg = resolved.background;

    bool directFg = false;
    bool directBg = false;

    version (with_24_bit_color) {
        if (!attrs.foregroundIsDefault) {
            fg = colorToRgba(attrs.foreground);
            directFg = true;
        }
        if (!attrs.backgroundIsDefault) {
            bg = colorToRgba(attrs.background);
            directBg = true;
        }
    }

    // Get foreground color
    auto fgIdx = attrs.foregroundIndex;
    if (!directFg) {
        if (!attrs.foregroundIsDefault && fgIdx < 16) {
            fg = resolved.palette[fgIdx];
        } else if (!attrs.foregroundIsDefault && fgIdx < 256) {
            // Extended 256-color palette - convert to RGB
            fg = index256ToRgba(fgIdx);
        }
    }

    // Get background color
    auto bgIdx = attrs.backgroundIndex;
    if (!directBg) {
        if (!attrs.backgroundIsDefault && bgIdx < 16) {
            bg = resolved.palette[bgIdx];
        } else if (!attrs.backgroundIsDefault && bgIdx < 256) {
            bg = index256ToRgba(bgIdx);
        }
    }

    // Handle inverse video
    if (attrs.inverse) {
        auto tmp = fg;
        fg = bg;
        bg = tmp;
    }

    // Handle bold (brighten foreground)
    if (!directFg && attrs.bold && !attrs.foregroundIsDefault) {
        fg[0] = fg[0] * 1.3f > 1.0f ? 1.0f : fg[0] * 1.3f;
        fg[1] = fg[1] * 1.3f > 1.0f ? 1.0f : fg[1] * 1.3f;
        fg[2] = fg[2] * 1.3f > 1.0f ? 1.0f : fg[2] * 1.3f;
    }

    // Handle faint (dim foreground)
    if (attrs.faint) {
        fg[0] *= 0.7f;
        fg[1] *= 0.7f;
        fg[2] *= 0.7f;
    }
}

/**
 * Convert 256-color index to RGBA.
 *
 * Indices 0-15: Standard colors
 * Indices 16-231: 6x6x6 color cube
 * Indices 232-255: Grayscale ramp
 */
private float[4] index256ToRgba(int idx) @nogc nothrow {
    if (idx < 16) {
        // Standard colors handled elsewhere
        return [0.5f, 0.5f, 0.5f, 1.0f];
    } else if (idx < 232) {
        // 6x6x6 color cube
        idx -= 16;
        int r = idx / 36;
        int g = (idx % 36) / 6;
        int b = idx % 6;
        return [
            r > 0 ? (r * 40 + 55) / 255.0f : 0.0f,
            g > 0 ? (g * 40 + 55) / 255.0f : 0.0f,
            b > 0 ? (b * 40 + 55) / 255.0f : 0.0f,
            1.0f
        ];
    } else {
        // Grayscale ramp (232-255)
        int gray = (idx - 232) * 10 + 8;
        float v = gray / 255.0f;
        return [v, v, v, 1.0f];
    }
}

unittest {
    auto emu = new PureDEmulator(10, 2);
    emu.feedData(cast(const(ubyte)[])"hello");
    assert(emu.getCell(0, 0).ch == 'h');
    assert(emu.getCell(4, 0).ch == 'o');

    emu.feedData(cast(const(ubyte)[])"\r\nworld");
    assert(emu.getCell(0, 1).ch == 'w');
    assert(emu.getCell(4, 1).ch == 'd');
}

private float[4] colorToRgba(Color color) @nogc nothrow {
    return [
        color.r / 255.0f,
        color.g / 255.0f,
        color.b / 255.0f,
        color.a / 255.0f
    ];
}
