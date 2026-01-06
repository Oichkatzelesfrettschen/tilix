/**
 * Pure D Terminal Entry Point
 *
 * Main application entry for the Pure D terminal backend using GLFW/OpenGL.
 * Integrates PTY management and terminal emulation for Super Phase 6.1.
 *
 * Build: dub build --config=pure-d
 * Run: ./build/pure/tilix-pure
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.main;

version (PURE_D_BACKEND):

import pured.window;
import pured.context;
import pured.pty;
import pured.emulator;
import pured.renderer;
import pured.platform.input;
import pured.terminal.selection;
import pured.terminal.scrollback;
import arsd.terminalemulator : TerminalEmulator;
import std.stdio : stderr, writefln, writeln;
import core.time : MonoTime, Duration, dur;
import bindbc.glfw;

/**
 * Pure D Terminal Application
 *
 * Main class coordinating window, rendering, PTY, and terminal emulation.
 */
class PureDTerminal : ITerminalCallbacks {
private:
    GLFWWindow _window;
    GLContext _glContext;
    PTY _pty;
    PureDEmulator _emulator;
    CellRenderer _renderer;

    // Input handling
    InputHandler _inputHandler;
    Selection _selection;
    ScrollbackViewport _scrollback;
    ClickDetector _clickDetector;

    // Mouse state
    double _mouseX = 0;
    double _mouseY = 0;
    int _mouseButtons = 0;

    // Frame timing
    MonoTime _lastFrameTime;
    long _frameCount;
    long _totalFrameCount;
    double _fps;
    double _frameTimeAccum;

    // Terminal state
    int _cols = 80;
    int _rows = 24;
    int _cellWidth = 10;
    int _cellHeight = 20;

    // PTY read buffer
    ubyte[16384] _readBuffer;

    // Window title from shell
    string _shellTitle;

public:
    /**
     * Initialize the terminal application.
     *
     * Returns: true if initialization succeeded
     */
    bool initialize() {
        // Create window
        _window = new GLFWWindow();
        if (!_window.initialize(1280, 720, "Tilix Pure D - Super Phase 6.1")) {
            stderr.writefln("Error: Failed to initialize window");
            return false;
        }

        // Initialize OpenGL context
        _glContext = new GLContext();
        if (!_glContext.initialize()) {
            stderr.writefln("Error: Failed to initialize GL context");
            _window.terminate();
            return false;
        }

        // Initialize cell renderer (includes font atlas)
        _renderer = new CellRenderer();
        if (!_renderer.initialize()) {
            stderr.writefln("Error: Failed to initialize cell renderer");
            _glContext.terminate();
            _window.terminate();
            return false;
        }

        // Get cell dimensions from font atlas
        _cellWidth = _renderer.cellWidth;
        _cellHeight = _renderer.cellHeight;

        // Set initial viewport and calculate terminal size
        int width, height;
        _window.getFramebufferSize(width, height);
        _glContext.setViewport(width, height);
        _renderer.setViewport(width, height);
        _cols = width / _cellWidth;
        _rows = height / _cellHeight;

        // Create terminal emulator
        _emulator = new PureDEmulator(_cols, _rows, this);

        // Create input handling
        _inputHandler = new InputHandler();
        _scrollback = new ScrollbackViewport(_rows);
        _selection = new Selection((col, row) => getCharAt(col, row));

        // Create and spawn PTY
        _pty = new PTY();
        if (!_pty.spawn(cast(ushort)_cols, cast(ushort)_rows)) {
            stderr.writefln("Error: Failed to spawn PTY");
            _window.terminate();
            return false;
        }

        // Set up callbacks
        _window.onResize(&onResize);
        _window.onKey(&onKey);
        _window.onChar(&onChar);
        _window.onMouseButton(&onMouseButton);
        _window.onScroll(&onScroll);
        _window.onCursorPos(&onCursorPos);

        // Initialize timing
        _lastFrameTime = MonoTime.currTime;
        _frameCount = 0;
        _totalFrameCount = 0;
        _fps = 0.0;
        _frameTimeAccum = 0.0;
        _shellTitle = "";

        writeln("Tilix Pure D Backend initialized successfully");
        writefln("  Target: 320Hz+ framerate, <1ms input latency");
        writefln("  Window: %dx%d", width, height);
        writefln("  Terminal: %dx%d cells", _cols, _rows);
        writefln("  PTY: master fd=%d", _pty.masterFd);

        return true;
    }

    /**
     * Run the main loop.
     */
    void run() {
        while (!_window.shouldClose) {
            // Calculate frame timing
            auto now = MonoTime.currTime;
            auto deltaTime = (now - _lastFrameTime).total!"usecs" / 1_000_000.0;
            _lastFrameTime = now;

            // Update FPS counter
            updateFPS(deltaTime);

            // Poll input events
            _window.pollEvents();

            // Read PTY output and feed to emulator
            processPtyOutput();

            // Render frame
            render();

            // Swap buffers
            _window.swapBuffers();

            _frameCount++;
            _totalFrameCount++;
        }
    }

    /**
     * Cleanup and terminate.
     */
    void terminate() {
        writefln("Shutting down... (rendered %d frames)", _totalFrameCount);

        if (_pty !is null) {
            _pty.close();
            _pty = null;
        }
        if (_renderer !is null) {
            _renderer.terminate();
            _renderer = null;
        }
        if (_glContext !is null) {
            _glContext.terminate();
            _glContext = null;
        }
        if (_window !is null) {
            _window.terminate();
            _window = null;
        }
    }

    // === ITerminalCallbacks implementation ===

    void onTitleChanged(string title) {
        _shellTitle = title;
    }

    void onSendToApplication(scope const(void)[] data) {
        // This is called when the emulator wants to send data to the PTY
        // (e.g., response to terminal queries)
        if (_pty !is null && _pty.isOpen) {
            _pty.write(cast(const(ubyte)[])data);
        }
    }

    void onBell() {
        // TODO: Implement visual/audio bell
        writeln("BELL");
    }

    void onRequestExit() {
        _window.close();
    }

    void onCursorStyleChanged(TerminalEmulator.CursorStyle style) {
        // TODO: Update cursor rendering style
    }

private:
    /**
     * Read available PTY output and feed to emulator.
     */
    void processPtyOutput() {
        if (_pty is null || !_pty.isOpen) return;

        // Check if child exited
        if (_pty.checkChild()) {
            writefln("Shell exited with status %d", _pty.exitStatus);
            _window.close();
            return;
        }

        // Non-blocking read from PTY
        auto data = _pty.read(_readBuffer);
        if (data !is null && data.length > 0) {
            // Feed to terminal emulator for parsing
            _emulator.feedData(data);
        }
    }

    /**
     * Render a frame.
     */
    void render() {
        // Clear framebuffer
        _glContext.setClearColor(0.1f, 0.1f, 0.15f, 1.0f);  // Dark terminal background
        _glContext.clear();

        // Render terminal cells using the cell renderer
        if (_renderer !is null && _emulator !is null) {
            _renderer.render(_emulator, true);  // true = show cursor
        }

        // Update window title with stats periodically
        if (_frameCount % 60 == 0) {
            import std.format : format;
            string title;
            if (_shellTitle.length > 0) {
                title = format("%s - %.1f FPS", _shellTitle, _fps);
            } else {
                title = format("Tilix Pure D - %.1f FPS (%.2f ms)", _fps, 1000.0 / _fps);
            }
            _window.setTitle(title);
        }

        // Debug: print first line of terminal every second
        debug {
            static int debugCounter = 0;
            debugCounter++;
            if (debugCounter >= 60) {
                debugCounter = 0;
                printDebugLine();
            }
        }
    }

    debug void printDebugLine() {
        import std.array : appender;
        auto line = appender!string();
        foreach (x; 0 .. _emulator.cols) {
            auto cell = _emulator.getCell(x, 0);
            if (!cell.hasNonCharacterData) {
                auto ch = cell.ch;
                if (ch >= 32 && ch < 127) {
                    line ~= cast(char)ch;
                } else if (ch == 0 || ch == ' ') {
                    line ~= ' ';
                } else {
                    line ~= '?';
                }
            } else {
                line ~= '@';
            }
        }
        writefln("Line 0: [%s]", line.data);
    }

    /**
     * Update FPS counter.
     */
    void updateFPS(double deltaTime) {
        _frameTimeAccum += deltaTime;

        // Update FPS every second
        if (_frameTimeAccum >= 1.0) {
            _fps = _frameCount / _frameTimeAccum;
            _frameCount = 0;
            _frameTimeAccum = 0.0;
        }
    }

    /**
     * Handle window resize.
     */
    void onResize(int width, int height) {
        _glContext.setViewport(width, height);
        if (_renderer !is null) {
            _renderer.setViewport(width, height);
        }

        // Recalculate terminal dimensions
        int newCols = width / _cellWidth;
        int newRows = height / _cellHeight;

        if (newCols != _cols || newRows != _rows) {
            _cols = newCols;
            _rows = newRows;

            // Resize PTY
            if (_pty !is null && _pty.isOpen) {
                _pty.resize(cast(ushort)_cols, cast(ushort)_rows);
            }

            // Resize emulator
            if (_emulator !is null) {
                _emulator.resize(_cols, _rows);
            }

            writefln("Window resized: %dx%d (terminal: %dx%d)", width, height, _cols, _rows);
        }
    }

    /**
     * Handle key press.
     */
    void onKey(int key, int scancode, int action, int mods) {
        // Close on Ctrl+Q (keep as hardcoded shortcut)
        if (action == GLFW_PRESS && key == GLFW_KEY_Q && (mods & GLFW_MOD_CONTROL)) {
            _window.close();
            return;
        }

        // Handle scrollback navigation (Shift+PageUp/PageDown)
        if (action == GLFW_PRESS || action == GLFW_REPEAT) {
            if (mods & GLFW_MOD_SHIFT) {
                if (key == GLFW_KEY_PAGE_UP) {
                    _scrollback.scrollPages(1);
                    return;
                } else if (key == GLFW_KEY_PAGE_DOWN) {
                    _scrollback.scrollPages(-1);
                    return;
                } else if (key == GLFW_KEY_HOME) {
                    _scrollback.scrollToTop();
                    return;
                } else if (key == GLFW_KEY_END) {
                    _scrollback.scrollToBottom();
                    return;
                }
            }
        }

        // Handle special keys via InputHandler
        if (action == GLFW_PRESS || action == GLFW_REPEAT) {
            auto escSeq = _inputHandler.translateKey(key, scancode, action, mods);
            if (escSeq !is null) {
                sendToPty(escSeq);
            }
        }
    }

    /**
     * Handle character input (Unicode).
     */
    void onChar(uint codepoint) {
        if (_pty is null || !_pty.isOpen) return;

        // Use InputHandler for Alt+key handling
        int mods = 0;  // GLFW doesn't provide mods in char callback
        auto data = _inputHandler.translateChar(codepoint, mods);
        if (data !is null) {
            sendToPty(data);
        }
    }

    /**
     * Handle mouse button events.
     */
    void onMouseButton(int button, int action, int mods) {
        int col = cast(int)(_mouseX / _cellWidth);
        int row = cast(int)(_mouseY / _cellHeight);

        // Clamp to valid range
        col = col < 0 ? 0 : (col >= _cols ? _cols - 1 : col);
        row = row < 0 ? 0 : (row >= _rows ? _rows - 1 : row);

        // Convert to buffer coordinates (account for scrollback)
        int bufferRow = _scrollback.bufferRow(row);

        if (action == GLFW_PRESS) {
            // Track button state
            _mouseButtons |= (1 << button);

            // Check for selection (left button without mouse mode)
            if (button == GLFW_MOUSE_BUTTON_LEFT && _inputHandler.mouseMode == MouseMode.none) {
                // Detect click count for word/line selection
                int clickCount = _clickDetector.click(col, bufferRow);
                auto selType = _clickDetector.selectionType();

                if (mods & GLFW_MOD_SHIFT) {
                    // Shift+click extends selection
                    _selection.extend(col, bufferRow);
                } else {
                    // Start new selection
                    _selection.start(col, bufferRow, selType);
                }
            } else {
                // Send to application if mouse mode enabled
                auto data = _inputHandler.translateMouseButton(button, action, mods, col, row);
                if (data !is null) {
                    sendToPty(data);
                }
            }
        } else if (action == GLFW_RELEASE) {
            _mouseButtons &= ~(1 << button);

            if (button == GLFW_MOUSE_BUTTON_LEFT && _selection.active) {
                _selection.finish();
            } else {
                auto data = _inputHandler.translateMouseButton(button, action, mods, col, row);
                if (data !is null) {
                    sendToPty(data);
                }
            }
        }
    }

    /**
     * Handle scroll wheel events.
     */
    void onScroll(double xoffset, double yoffset) {
        int col = cast(int)(_mouseX / _cellWidth);
        int row = cast(int)(_mouseY / _cellHeight);

        // If mouse mode is active, send to application
        if (_inputHandler.mouseMode != MouseMode.none) {
            auto data = _inputHandler.translateScroll(xoffset, yoffset, 0, col, row);
            if (data !is null) {
                sendToPty(data);
            }
        } else {
            // Otherwise, scroll the viewport
            _scrollback.handleScrollWheel(yoffset);
        }
    }

    /**
     * Handle mouse cursor position updates.
     */
    void onCursorPos(double xpos, double ypos) {
        _mouseX = xpos;
        _mouseY = ypos;

        int col = cast(int)(xpos / _cellWidth);
        int row = cast(int)(ypos / _cellHeight);

        // Clamp to valid range
        col = col < 0 ? 0 : (col >= _cols ? _cols - 1 : col);
        row = row < 0 ? 0 : (row >= _rows ? _rows - 1 : row);

        int bufferRow = _scrollback.bufferRow(row);

        // Update selection if dragging
        if (_selection.active && (_mouseButtons & 1)) {
            _selection.update(col, bufferRow);
        }

        // Send motion to application if mouse tracking enabled
        if (_inputHandler.mouseMode == MouseMode.buttonEvent ||
            _inputHandler.mouseMode == MouseMode.anyEvent) {
            auto data = _inputHandler.translateMouseMotion(_mouseButtons, 0, col, row);
            if (data !is null) {
                sendToPty(data);
            }
        }
    }

    /**
     * Helper to send data to PTY.
     */
    void sendToPty(const(ubyte)[] data) {
        if (_pty !is null && _pty.isOpen && data.length > 0) {
            _pty.write(data);
        }
    }

    /**
     * Get character at buffer position (for selection word detection).
     */
    dchar getCharAt(int col, int row) {
        if (_emulator is null) return ' ';
        if (col < 0 || col >= _cols) return ' ';

        // For now, only support visible area
        // TODO: Access scrollback buffer when implemented
        if (row < 0 || row >= _rows) return ' ';

        auto cell = _emulator.getCell(col, row);
        if (cell.hasNonCharacterData) return ' ';
        return cell.ch == 0 ? ' ' : cell.ch;
    }
}

/**
 * Encode a Unicode codepoint to UTF-8.
 *
 * Returns: Number of bytes written (1-4), or 0 on error
 */
size_t encodeUtf8(dchar codepoint, ref char[4] buffer) {
    if (codepoint < 0x80) {
        buffer[0] = cast(char)codepoint;
        return 1;
    } else if (codepoint < 0x800) {
        buffer[0] = cast(char)(0xC0 | (codepoint >> 6));
        buffer[1] = cast(char)(0x80 | (codepoint & 0x3F));
        return 2;
    } else if (codepoint < 0x10000) {
        buffer[0] = cast(char)(0xE0 | (codepoint >> 12));
        buffer[1] = cast(char)(0x80 | ((codepoint >> 6) & 0x3F));
        buffer[2] = cast(char)(0x80 | (codepoint & 0x3F));
        return 3;
    } else if (codepoint < 0x110000) {
        buffer[0] = cast(char)(0xF0 | (codepoint >> 18));
        buffer[1] = cast(char)(0x80 | ((codepoint >> 12) & 0x3F));
        buffer[2] = cast(char)(0x80 | ((codepoint >> 6) & 0x3F));
        buffer[3] = cast(char)(0x80 | (codepoint & 0x3F));
        return 4;
    }
    return 0;  // Invalid codepoint
}

/**
 * Convert GLFW key code to terminal escape sequence.
 *
 * Params:
 *   key = GLFW key code
 *   mods = Modifier keys (Ctrl, Alt, Shift)
 *
 * Returns: Escape sequence string, or null if not a special key
 */
const(ubyte)[] keyToEscapeSequence(int key, int mods) {
    import bindbc.glfw;

    // Application cursor key mode sequences (CSI sequences)
    // These are the default for most terminals
    switch (key) {
        // Arrow keys
        case GLFW_KEY_UP:    return cast(const(ubyte)[])"\x1b[A";
        case GLFW_KEY_DOWN:  return cast(const(ubyte)[])"\x1b[B";
        case GLFW_KEY_RIGHT: return cast(const(ubyte)[])"\x1b[C";
        case GLFW_KEY_LEFT:  return cast(const(ubyte)[])"\x1b[D";

        // Navigation keys
        case GLFW_KEY_HOME:      return cast(const(ubyte)[])"\x1b[H";
        case GLFW_KEY_END:       return cast(const(ubyte)[])"\x1b[F";
        case GLFW_KEY_INSERT:    return cast(const(ubyte)[])"\x1b[2~";
        case GLFW_KEY_DELETE:    return cast(const(ubyte)[])"\x1b[3~";
        case GLFW_KEY_PAGE_UP:   return cast(const(ubyte)[])"\x1b[5~";
        case GLFW_KEY_PAGE_DOWN: return cast(const(ubyte)[])"\x1b[6~";

        // Function keys F1-F12
        case GLFW_KEY_F1:  return cast(const(ubyte)[])"\x1bOP";
        case GLFW_KEY_F2:  return cast(const(ubyte)[])"\x1bOQ";
        case GLFW_KEY_F3:  return cast(const(ubyte)[])"\x1bOR";
        case GLFW_KEY_F4:  return cast(const(ubyte)[])"\x1bOS";
        case GLFW_KEY_F5:  return cast(const(ubyte)[])"\x1b[15~";
        case GLFW_KEY_F6:  return cast(const(ubyte)[])"\x1b[17~";
        case GLFW_KEY_F7:  return cast(const(ubyte)[])"\x1b[18~";
        case GLFW_KEY_F8:  return cast(const(ubyte)[])"\x1b[19~";
        case GLFW_KEY_F9:  return cast(const(ubyte)[])"\x1b[20~";
        case GLFW_KEY_F10: return cast(const(ubyte)[])"\x1b[21~";
        case GLFW_KEY_F11: return cast(const(ubyte)[])"\x1b[23~";
        case GLFW_KEY_F12: return cast(const(ubyte)[])"\x1b[24~";

        // Special keys
        case GLFW_KEY_BACKSPACE: return cast(const(ubyte)[])"\x7f";  // DEL character
        case GLFW_KEY_TAB:       return cast(const(ubyte)[])"\t";
        case GLFW_KEY_ENTER:     return cast(const(ubyte)[])"\r";

        default:
            break;
    }

    // Handle Ctrl+letter combinations
    if (mods & GLFW_MOD_CONTROL) {
        // Ctrl+A through Ctrl+Z generate ASCII 1-26
        if (key >= GLFW_KEY_A && key <= GLFW_KEY_Z) {
            static ubyte[1] ctrlChar;
            ctrlChar[0] = cast(ubyte)(key - GLFW_KEY_A + 1);
            return ctrlChar[];
        }
        // Ctrl+[ is ESC (27)
        if (key == GLFW_KEY_LEFT_BRACKET) {
            return cast(const(ubyte)[])"\x1b";
        }
        // Ctrl+\ is FS (28)
        if (key == GLFW_KEY_BACKSLASH) {
            static ubyte[1] fs = [28];
            return fs[];
        }
        // Ctrl+] is GS (29)
        if (key == GLFW_KEY_RIGHT_BRACKET) {
            static ubyte[1] gs = [29];
            return gs[];
        }
    }

    return null;  // Not a special key
}

/**
 * Main entry point for Pure D backend.
 */
void main() {
    writeln("=== Tilix Pure D Terminal ===");
    writeln("Super Phase 6.1: PTY + Emulator Integration");
    writeln("");

    auto app = new PureDTerminal();

    if (!app.initialize()) {
        stderr.writefln("Fatal: Failed to initialize application");
        return;
    }

    scope(exit) app.terminate();

    app.run();

    writeln("Goodbye!");
}
