/**
 * Platform Input Handler
 *
 * Comprehensive GLFW input handling with terminal mode awareness.
 * Supports application cursor mode (DECCKM), keypad mode (DECKPAM),
 * Alt sends ESC, and mouse reporting modes.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.platform.input;

version (PURE_D_BACKEND):

import bindbc.glfw;
import std.stdio : stderr, writefln;

/**
 * Mouse reporting modes per ANSI/DEC standards.
 */
enum MouseMode {
    none = 0,       /// Mouse reporting disabled
    x10 = 9,        /// X10 compatibility mode (button press only)
    normal = 1000,  /// Normal tracking (press/release)
    highlight = 1001, /// Highlight tracking
    buttonEvent = 1002, /// Button-event tracking (motion while pressed)
    anyEvent = 1003,  /// Any-event tracking (all motion)
}

/**
 * Mouse coordinate encoding format.
 */
enum MouseEncoding {
    x10 = 0,        /// X10/normal: ESC [ M Cb Cx Cy (6 bytes, coords +32)
    utf8 = 1005,    /// UTF-8: coords as UTF-8 characters
    sgr = 1006,     /// SGR: ESC [ < Pb ; Px ; Py M/m (press/release)
    urxvt = 1015,   /// urxvt: ESC [ Pb ; Px ; Py M
}

/**
 * Terminal input handler with mode state.
 *
 * Manages keyboard and mouse input translation to terminal escape sequences,
 * respecting current terminal modes (cursor key mode, keypad mode, mouse mode).
 */
class InputHandler {
private:
    // Cursor key mode: false=CSI (normal), true=SS3 (application)
    bool _applicationCursorMode;

    // Keypad mode: false=numeric, true=application
    bool _applicationKeypadMode;

    // Alt key behavior: true=send ESC prefix
    bool _altSendsEscape = true;

    // Bracketed paste mode
    bool _bracketedPasteMode;

    // Mouse state
    MouseMode _mouseMode = MouseMode.none;
    MouseEncoding _mouseEncoding = MouseEncoding.x10;
    bool _focusReporting;

    // Static buffers for return values (avoid allocation)
    static ubyte[32] _keyBuffer;
    static ubyte[32] _mouseBuffer;

public:
    /**
     * Translate GLFW key event to terminal escape sequence.
     *
     * Params:
     *   key = GLFW key code
     *   scancode = Platform scancode (unused)
     *   action = GLFW_PRESS, GLFW_RELEASE, or GLFW_REPEAT
     *   mods = Modifier key flags
     *
     * Returns: Escape sequence bytes, or null if key should be ignored
     */
    const(ubyte)[] translateKey(int key, int scancode, int action, int mods) {
        // Only handle press and repeat
        if (action != GLFW_PRESS && action != GLFW_REPEAT)
            return null;

        // Check for special keys first
        auto special = translateSpecialKey(key, mods);
        if (special !is null)
            return special;

        // Handle Ctrl combinations
        if (mods & GLFW_MOD_CONTROL) {
            auto ctrl = translateCtrlKey(key);
            if (ctrl !is null)
                return ctrl;
        }

        return null;  // Let character callback handle normal keys
    }

    /**
     * Translate Unicode character input to terminal bytes.
     *
     * Params:
     *   codepoint = Unicode codepoint
     *   mods = Current modifier state
     *
     * Returns: UTF-8 encoded bytes with optional ESC prefix for Alt
     */
    const(ubyte)[] translateChar(dchar codepoint, int mods) {
        size_t offset = 0;

        // Alt sends ESC prefix
        if (_altSendsEscape && (mods & GLFW_MOD_ALT)) {
            _keyBuffer[offset++] = 0x1b;  // ESC
        }

        // Encode UTF-8
        size_t len = encodeUtf8(codepoint, _keyBuffer[offset .. $]);
        if (len == 0)
            return null;

        return _keyBuffer[0 .. offset + len];
    }

    /**
     * Translate mouse event to terminal escape sequence.
     *
     * Params:
     *   button = GLFW mouse button (0=left, 1=right, 2=middle)
     *   action = GLFW_PRESS or GLFW_RELEASE
     *   mods = Modifier key flags
     *   x = Column position (0-based)
     *   y = Row position (0-based)
     *
     * Returns: Mouse escape sequence, or null if mouse reporting disabled
     */
    const(ubyte)[] translateMouseButton(int button, int action, int mods, int x, int y) {
        if (_mouseMode == MouseMode.none)
            return null;

        // X10 mode only reports button press
        if (_mouseMode == MouseMode.x10 && action != GLFW_PRESS)
            return null;

        return encodeMouseEvent(button, action == GLFW_PRESS, mods, x, y);
    }

    /**
     * Translate mouse motion to terminal escape sequence.
     *
     * Params:
     *   buttons = Currently pressed button mask
     *   mods = Modifier key flags
     *   x = Column position (0-based)
     *   y = Row position (0-based)
     *
     * Returns: Mouse motion sequence, or null if motion reporting disabled
     */
    const(ubyte)[] translateMouseMotion(int buttons, int mods, int x, int y) {
        // Only buttonEvent and anyEvent modes report motion
        if (_mouseMode != MouseMode.buttonEvent && _mouseMode != MouseMode.anyEvent)
            return null;

        // buttonEvent only reports when a button is pressed
        if (_mouseMode == MouseMode.buttonEvent && buttons == 0)
            return null;

        // Motion is encoded as button 32 (no button change)
        return encodeMouseEvent(32, true, mods, x, y);
    }

    /**
     * Translate scroll wheel to terminal escape sequence.
     *
     * Params:
     *   xoffset = Horizontal scroll (unused by most terminals)
     *   yoffset = Vertical scroll (positive=up, negative=down)
     *   mods = Modifier key flags
     *   x = Column position
     *   y = Row position
     *
     * Returns: Scroll escape sequence, or null if mouse reporting disabled
     */
    const(ubyte)[] translateScroll(double xoffset, double yoffset, int mods, int x, int y) {
        if (_mouseMode == MouseMode.none)
            return null;

        // Scroll is encoded as button 64 (up) or 65 (down)
        int button = yoffset > 0 ? 64 : 65;
        return encodeMouseEvent(button, true, mods, x, y);
    }

    /**
     * Generate focus event sequence.
     *
     * Returns: Focus in/out sequence, or null if focus reporting disabled
     */
    const(ubyte)[] translateFocus(bool focused) {
        if (!_focusReporting)
            return null;

        if (focused) {
            _keyBuffer[0 .. 3] = [0x1b, '[', 'I'];  // CSI I
        } else {
            _keyBuffer[0 .. 3] = [0x1b, '[', 'O'];  // CSI O
        }
        return _keyBuffer[0 .. 3];
    }

    /**
     * Generate bracketed paste start/end sequence.
     */
    const(ubyte)[] bracketedPasteStart() {
        if (!_bracketedPasteMode)
            return null;
        _keyBuffer[0 .. 6] = [0x1b, '[', '2', '0', '0', '~'];
        return _keyBuffer[0 .. 6];
    }

    const(ubyte)[] bracketedPasteEnd() {
        if (!_bracketedPasteMode)
            return null;
        _keyBuffer[0 .. 6] = [0x1b, '[', '2', '0', '1', '~'];
        return _keyBuffer[0 .. 6];
    }

    // === Mode setters (called from emulator when escape sequences parsed) ===

    void setApplicationCursorMode(bool enabled) {
        _applicationCursorMode = enabled;
    }

    void setApplicationKeypadMode(bool enabled) {
        _applicationKeypadMode = enabled;
    }

    void setMouseMode(MouseMode mode) {
        _mouseMode = mode;
    }

    void setMouseEncoding(MouseEncoding encoding) {
        _mouseEncoding = encoding;
    }

    void setBracketedPasteMode(bool enabled) {
        _bracketedPasteMode = enabled;
    }

    void setFocusReporting(bool enabled) {
        _focusReporting = enabled;
    }

    void setAltSendsEscape(bool enabled) {
        _altSendsEscape = enabled;
    }

    // === Mode getters ===

    @property bool applicationCursorMode() const { return _applicationCursorMode; }
    @property bool applicationKeypadMode() const { return _applicationKeypadMode; }
    @property MouseMode mouseMode() const { return _mouseMode; }
    @property MouseEncoding mouseEncoding() const { return _mouseEncoding; }
    @property bool bracketedPasteMode() const { return _bracketedPasteMode; }
    @property bool focusReporting() const { return _focusReporting; }

private:
    /**
     * Translate special keys (arrows, function keys, etc.)
     */
    const(ubyte)[] translateSpecialKey(int key, int mods) {
        int modParam = modifierParam(mods);

        // Arrow keys depend on cursor mode
        switch (key) {
            case GLFW_KEY_UP:
                if (modParam > 1) {
                    return encodeCsiMod(1, modParam, 'A');
                }
                return _applicationCursorMode
                    ? cast(const(ubyte)[])"\x1bOA"   // SS3 A
                    : cast(const(ubyte)[])"\x1b[A";  // CSI A
            case GLFW_KEY_DOWN:
                if (modParam > 1) {
                    return encodeCsiMod(1, modParam, 'B');
                }
                return _applicationCursorMode
                    ? cast(const(ubyte)[])"\x1bOB"
                    : cast(const(ubyte)[])"\x1b[B";
            case GLFW_KEY_RIGHT:
                if (modParam > 1) {
                    return encodeCsiMod(1, modParam, 'C');
                }
                return _applicationCursorMode
                    ? cast(const(ubyte)[])"\x1bOC"
                    : cast(const(ubyte)[])"\x1b[C";
            case GLFW_KEY_LEFT:
                if (modParam > 1) {
                    return encodeCsiMod(1, modParam, 'D');
                }
                return _applicationCursorMode
                    ? cast(const(ubyte)[])"\x1bOD"
                    : cast(const(ubyte)[])"\x1b[D";

            // Navigation keys
            case GLFW_KEY_HOME:
                return modParam > 1 ? encodeCsiMod(1, modParam, 'H')
                                    : cast(const(ubyte)[])"\x1b[H";
            case GLFW_KEY_END:
                return modParam > 1 ? encodeCsiMod(1, modParam, 'F')
                                    : cast(const(ubyte)[])"\x1b[F";
            case GLFW_KEY_INSERT:
                return modParam > 1 ? encodeCsiMod(2, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[2~";
            case GLFW_KEY_DELETE:
                return modParam > 1 ? encodeCsiMod(3, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[3~";
            case GLFW_KEY_PAGE_UP:
                return modParam > 1 ? encodeCsiMod(5, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[5~";
            case GLFW_KEY_PAGE_DOWN:
                return modParam > 1 ? encodeCsiMod(6, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[6~";

            // Function keys (VT220 style)
            case GLFW_KEY_F1:
                return modParam > 1 ? encodeCsiMod(1, modParam, 'P')
                                    : cast(const(ubyte)[])"\x1bOP";
            case GLFW_KEY_F2:
                return modParam > 1 ? encodeCsiMod(1, modParam, 'Q')
                                    : cast(const(ubyte)[])"\x1bOQ";
            case GLFW_KEY_F3:
                return modParam > 1 ? encodeCsiMod(1, modParam, 'R')
                                    : cast(const(ubyte)[])"\x1bOR";
            case GLFW_KEY_F4:
                return modParam > 1 ? encodeCsiMod(1, modParam, 'S')
                                    : cast(const(ubyte)[])"\x1bOS";
            case GLFW_KEY_F5:
                return modParam > 1 ? encodeCsiMod(15, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[15~";
            case GLFW_KEY_F6:
                return modParam > 1 ? encodeCsiMod(17, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[17~";
            case GLFW_KEY_F7:
                return modParam > 1 ? encodeCsiMod(18, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[18~";
            case GLFW_KEY_F8:
                return modParam > 1 ? encodeCsiMod(19, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[19~";
            case GLFW_KEY_F9:
                return modParam > 1 ? encodeCsiMod(20, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[20~";
            case GLFW_KEY_F10:
                return modParam > 1 ? encodeCsiMod(21, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[21~";
            case GLFW_KEY_F11:
                return modParam > 1 ? encodeCsiMod(23, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[23~";
            case GLFW_KEY_F12:
                return modParam > 1 ? encodeCsiMod(24, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[24~";
            case GLFW_KEY_F13:
                return modParam > 1 ? encodeCsiMod(25, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[25~";
            case GLFW_KEY_F14:
                return modParam > 1 ? encodeCsiMod(26, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[26~";
            case GLFW_KEY_F15:
                return modParam > 1 ? encodeCsiMod(28, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[28~";
            case GLFW_KEY_F16:
                return modParam > 1 ? encodeCsiMod(29, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[29~";
            case GLFW_KEY_F17:
                return modParam > 1 ? encodeCsiMod(31, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[31~";
            case GLFW_KEY_F18:
                return modParam > 1 ? encodeCsiMod(32, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[32~";
            case GLFW_KEY_F19:
                return modParam > 1 ? encodeCsiMod(33, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[33~";
            case GLFW_KEY_F20:
                return modParam > 1 ? encodeCsiMod(34, modParam, '~')
                                    : cast(const(ubyte)[])"\x1b[34~";

            // Control keys
            case GLFW_KEY_BACKSPACE: return cast(const(ubyte)[])"\x7f";
            case GLFW_KEY_TAB:
                if (mods & GLFW_MOD_SHIFT)
                    return cast(const(ubyte)[])"\x1b[Z";  // Shift+Tab = CSI Z
                return cast(const(ubyte)[])"\t";
            case GLFW_KEY_ENTER:
                return cast(const(ubyte)[])"\r";
            case GLFW_KEY_ESCAPE:
                return cast(const(ubyte)[])"\x1b";

            // Keypad with application mode
            case GLFW_KEY_KP_ENTER:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOM"
                    : cast(const(ubyte)[])"\r";
            case GLFW_KEY_KP_0:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOp"
                    : cast(const(ubyte)[])("0");
            case GLFW_KEY_KP_1:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOq"
                    : cast(const(ubyte)[])("1");
            case GLFW_KEY_KP_2:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOr"
                    : cast(const(ubyte)[])("2");
            case GLFW_KEY_KP_3:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOs"
                    : cast(const(ubyte)[])("3");
            case GLFW_KEY_KP_4:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOt"
                    : cast(const(ubyte)[])("4");
            case GLFW_KEY_KP_5:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOu"
                    : cast(const(ubyte)[])("5");
            case GLFW_KEY_KP_6:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOv"
                    : cast(const(ubyte)[])("6");
            case GLFW_KEY_KP_7:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOw"
                    : cast(const(ubyte)[])("7");
            case GLFW_KEY_KP_8:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOx"
                    : cast(const(ubyte)[])("8");
            case GLFW_KEY_KP_9:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOy"
                    : cast(const(ubyte)[])("9");
            case GLFW_KEY_KP_DECIMAL:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOn"
                    : cast(const(ubyte)[])(".");
            case GLFW_KEY_KP_DIVIDE:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOo"
                    : cast(const(ubyte)[])("/");
            case GLFW_KEY_KP_MULTIPLY:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOj"
                    : cast(const(ubyte)[])("*");
            case GLFW_KEY_KP_SUBTRACT:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOm"
                    : cast(const(ubyte)[])("-");
            case GLFW_KEY_KP_ADD:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOk"
                    : cast(const(ubyte)[])("+");
            case GLFW_KEY_KP_EQUAL:
                return _applicationKeypadMode
                    ? cast(const(ubyte)[])"\x1bOX"
                    : cast(const(ubyte)[])("=");

            default:
                return null;
        }
    }

    /**
     * Translate Ctrl+key combinations.
     */
    const(ubyte)[] translateCtrlKey(int key) {
        // Ctrl+A through Ctrl+Z generate ASCII 1-26
        if (key >= GLFW_KEY_A && key <= GLFW_KEY_Z) {
            _keyBuffer[0] = cast(ubyte)(key - GLFW_KEY_A + 1);
            return _keyBuffer[0 .. 1];
        }

        // Special Ctrl combinations
        switch (key) {
            case GLFW_KEY_LEFT_BRACKET:  // Ctrl+[ = ESC
                _keyBuffer[0] = 0x1b;
                return _keyBuffer[0 .. 1];
            case GLFW_KEY_BACKSLASH:  // Ctrl+\ = FS (28)
                _keyBuffer[0] = 28;
                return _keyBuffer[0 .. 1];
            case GLFW_KEY_RIGHT_BRACKET:  // Ctrl+] = GS (29)
                _keyBuffer[0] = 29;
                return _keyBuffer[0 .. 1];
            case GLFW_KEY_6:  // Ctrl+6 = RS (30)
                _keyBuffer[0] = 30;
                return _keyBuffer[0 .. 1];
            case GLFW_KEY_MINUS:  // Ctrl+- = US (31)
                _keyBuffer[0] = 31;
                return _keyBuffer[0 .. 1];
            case GLFW_KEY_SPACE:  // Ctrl+Space = NUL (0)
                _keyBuffer[0] = 0;
                return _keyBuffer[0 .. 1];
            default:
                return null;
        }
    }

    int modifierParam(int mods) {
        int param = 1;
        if (mods & GLFW_MOD_SHIFT)   param += 1;
        if (mods & GLFW_MOD_ALT)     param += 2;
        if (mods & GLFW_MOD_CONTROL) param += 4;
        return param;
    }

    size_t appendNumber(ubyte[] buffer, size_t offset, int value) {
        if (value == 0) {
            buffer[offset++] = '0';
            return offset;
        }

        ubyte[10] digits;
        size_t len = 0;
        int v = value;
        while (v > 0 && len < digits.length) {
            digits[len++] = cast(ubyte)('0' + (v % 10));
            v /= 10;
        }
        foreach_reverse (i; 0 .. len) {
            buffer[offset++] = digits[i];
        }
        return offset;
    }

    const(ubyte)[] encodeCsiMod(int baseParam, int modParam, char finalChar) {
        size_t offset = 0;
        _keyBuffer[offset++] = 0x1b;
        _keyBuffer[offset++] = '[';
        offset = appendNumber(_keyBuffer[], offset, baseParam);
        _keyBuffer[offset++] = ';';
        offset = appendNumber(_keyBuffer[], offset, modParam);
        _keyBuffer[offset++] = cast(ubyte)finalChar;
        return _keyBuffer[0 .. offset];
    }

    /**
     * Encode mouse event in current format.
     */
    const(ubyte)[] encodeMouseEvent(int button, bool press, int mods, int x, int y) {
        // Build button byte with modifiers
        int cb = button;
        if (mods & GLFW_MOD_SHIFT)   cb |= 4;
        if (mods & GLFW_MOD_ALT)     cb |= 8;
        if (mods & GLFW_MOD_CONTROL) cb |= 16;

        final switch (_mouseEncoding) {
            case MouseEncoding.x10:
                return encodeMouseX10(cb, x, y);
            case MouseEncoding.utf8:
                return encodeMouseUtf8(cb, x, y);
            case MouseEncoding.sgr:
                return encodeMouseSgr(cb, press, x, y);
            case MouseEncoding.urxvt:
                return encodeMouseUrxvt(cb, x, y);
        }
    }

    /**
     * X10/normal encoding: ESC [ M Cb Cx Cy
     * Coordinates are 1-based + 32 (printable ASCII)
     */
    const(ubyte)[] encodeMouseX10(int cb, int x, int y) {
        _mouseBuffer[0] = 0x1b;
        _mouseBuffer[1] = '[';
        _mouseBuffer[2] = 'M';
        _mouseBuffer[3] = cast(ubyte)(cb + 32);
        _mouseBuffer[4] = cast(ubyte)((x + 1) + 32);
        _mouseBuffer[5] = cast(ubyte)((y + 1) + 32);
        return _mouseBuffer[0 .. 6];
    }

    /**
     * UTF-8 encoding: same as X10 but coordinates UTF-8 encoded.
     * Allows coordinates up to 2047.
     */
    const(ubyte)[] encodeMouseUtf8(int cb, int x, int y) {
        size_t offset = 0;
        _mouseBuffer[offset++] = 0x1b;
        _mouseBuffer[offset++] = '[';
        _mouseBuffer[offset++] = 'M';

        // Button byte (can be > 127)
        offset += encodeUtf8(cb + 32, _mouseBuffer[offset .. $]);
        offset += encodeUtf8((x + 1) + 32, _mouseBuffer[offset .. $]);
        offset += encodeUtf8((y + 1) + 32, _mouseBuffer[offset .. $]);

        return _mouseBuffer[0 .. offset];
    }

    /**
     * SGR encoding: ESC [ < Pb ; Px ; Py M/m
     * M = press, m = release. Coordinates are 1-based decimal.
     */
    const(ubyte)[] encodeMouseSgr(int cb, bool press, int x, int y) {
        import std.format : sformat;

        // Use char buffer for sformat, then cast
        static char[32] charBuf;
        auto result = sformat(charBuf[], "\x1b[<%d;%d;%d%c",
                              cb, x + 1, y + 1, press ? 'M' : 'm');
        // Copy to ubyte buffer
        _mouseBuffer[0 .. result.length] = cast(ubyte[])result;
        return _mouseBuffer[0 .. result.length];
    }

    /**
     * urxvt encoding: ESC [ Pb ; Px ; Py M
     * Coordinates are 1-based decimal.
     */
    const(ubyte)[] encodeMouseUrxvt(int cb, int x, int y) {
        import std.format : sformat;

        static char[32] charBuf;
        auto result = sformat(charBuf[], "\x1b[%d;%d;%dM",
                              cb + 32, x + 1, y + 1);
        _mouseBuffer[0 .. result.length] = cast(ubyte[])result;
        return _mouseBuffer[0 .. result.length];
    }
}

/**
 * Encode Unicode codepoint as UTF-8.
 *
 * Params:
 *   codepoint = Unicode codepoint to encode
 *   buffer = Output buffer (must have at least 4 bytes)
 *
 * Returns: Number of bytes written (1-4), or 0 on error
 */
size_t encodeUtf8(dchar codepoint, ubyte[] buffer) @nogc nothrow {
    if (buffer.length < 4)
        return 0;

    if (codepoint < 0x80) {
        buffer[0] = cast(ubyte)codepoint;
        return 1;
    } else if (codepoint < 0x800) {
        buffer[0] = cast(ubyte)(0xC0 | (codepoint >> 6));
        buffer[1] = cast(ubyte)(0x80 | (codepoint & 0x3F));
        return 2;
    } else if (codepoint < 0x10000) {
        buffer[0] = cast(ubyte)(0xE0 | (codepoint >> 12));
        buffer[1] = cast(ubyte)(0x80 | ((codepoint >> 6) & 0x3F));
        buffer[2] = cast(ubyte)(0x80 | (codepoint & 0x3F));
        return 3;
    } else if (codepoint < 0x110000) {
        buffer[0] = cast(ubyte)(0xF0 | (codepoint >> 18));
        buffer[1] = cast(ubyte)(0x80 | ((codepoint >> 12) & 0x3F));
        buffer[2] = cast(ubyte)(0x80 | ((codepoint >> 6) & 0x3F));
        buffer[3] = cast(ubyte)(0x80 | (codepoint & 0x3F));
        return 4;
    }
    return 0;  // Invalid codepoint
}
