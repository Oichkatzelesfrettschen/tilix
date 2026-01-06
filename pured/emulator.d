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
import arsd.color : Color, IndexedImage;
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
        // TODO: Implement clipboard via GLFW
    }

    override void pasteFromClipboard(void delegate(in char[]) callback) {
        // TODO: Implement clipboard via GLFW
        // For now, just call with empty string
        if (callback !is null) {
            callback("");
        }
    }

    override void copyToPrimary(string text) {
        // TODO: Implement X11 PRIMARY selection
    }

    override void pasteFromPrimary(void delegate(in char[]) callback) {
        // TODO: Implement X11 PRIMARY selection
        if (callback !is null) {
            callback("");
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
                        out float[4] fg, out float[4] bg) {
    // Default colors (white on black)
    fg = [0.9f, 0.9f, 0.9f, 1.0f];
    bg = [0.1f, 0.1f, 0.15f, 1.0f];

    // Standard 16-color palette (approximate xterm colors)
    static immutable float[4][16] palette = [
        [0.0f, 0.0f, 0.0f, 1.0f],       // 0: Black
        [0.8f, 0.0f, 0.0f, 1.0f],       // 1: Red
        [0.0f, 0.8f, 0.0f, 1.0f],       // 2: Green
        [0.8f, 0.8f, 0.0f, 1.0f],       // 3: Yellow
        [0.0f, 0.0f, 0.8f, 1.0f],       // 4: Blue
        [0.8f, 0.0f, 0.8f, 1.0f],       // 5: Magenta
        [0.0f, 0.8f, 0.8f, 1.0f],       // 6: Cyan
        [0.75f, 0.75f, 0.75f, 1.0f],    // 7: White
        [0.5f, 0.5f, 0.5f, 1.0f],       // 8: Bright Black
        [1.0f, 0.0f, 0.0f, 1.0f],       // 9: Bright Red
        [0.0f, 1.0f, 0.0f, 1.0f],       // 10: Bright Green
        [1.0f, 1.0f, 0.0f, 1.0f],       // 11: Bright Yellow
        [0.0f, 0.0f, 1.0f, 1.0f],       // 12: Bright Blue
        [1.0f, 0.0f, 1.0f, 1.0f],       // 13: Bright Magenta
        [0.0f, 1.0f, 1.0f, 1.0f],       // 14: Bright Cyan
        [1.0f, 1.0f, 1.0f, 1.0f],       // 15: Bright White
    ];

    // Get foreground color
    auto fgIdx = attrs.foregroundIndex;
    if (!attrs.foregroundIsDefault && fgIdx < 16) {
        fg = palette[fgIdx];
    } else if (!attrs.foregroundIsDefault && fgIdx < 256) {
        // Extended 256-color palette - convert to RGB
        fg = index256ToRgba(fgIdx);
    }

    // Get background color
    auto bgIdx = attrs.backgroundIndex;
    if (!attrs.backgroundIsDefault && bgIdx < 16) {
        bg = palette[bgIdx];
    } else if (!attrs.backgroundIsDefault && bgIdx < 256) {
        bg = index256ToRgba(bgIdx);
    }

    // Handle inverse video
    if (attrs.inverse) {
        auto tmp = fg;
        fg = bg;
        bg = tmp;
    }

    // Handle bold (brighten foreground)
    if (attrs.bold && !attrs.foregroundIsDefault) {
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
private float[4] index256ToRgba(int idx) {
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
