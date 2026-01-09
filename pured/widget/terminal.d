/**
 * Terminal Widget
 *
 * High-performance terminal widget integrating:
 * - arsd.terminalemulator for VT parsing
 * - OpenGL rendering via font atlas
 * - Input handling with mouse/selection support
 * - Scrollback navigation
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.terminal;

version (PURE_D_BACKEND):

import bindbc.glfw;
import pured.widget.base;
import pured.widget.events;
import pured.util.signal;
import pured.platform.input;
import pured.platform.input_types : MouseMode;
import pured.terminal.selection;
import pured.terminal.scrollback : ScrollbackViewport, calculateScrollbar;
import pured.config : ResolvedTheme, defaultResolvedTheme;
import pured.emulator : PureDEmulator, attributesToColors;
import pured.fontatlas : FontAtlas;
import pured.renderer : CellRenderer;
import arsd.terminalemulator : TerminalEmulator;

import std.algorithm : min, max, clamp;

// Re-export SelectionType from selection module
public import pured.terminal.selection : SelectionType;

/**
 * Terminal cursor styles.
 */
enum CursorStyle {
    block,
    underline,
    bar,
}

/**
 * Terminal widget for rendering terminal content.
 *
 * Combines the emulator, renderer, and input handling into
 * a single widget that can be placed in the UI hierarchy.
 */
class TerminalWidget : Widget {
private:
    // Terminal emulation
    PureDEmulator _emulator;
    int _cols;
    int _rows;

    // Rendering
    FontAtlas _fontAtlas;
    CellRenderer _renderer;
    int _cellWidth;
    int _cellHeight;

    // Input
    InputHandler _inputHandler;
    Selection _selection;
    ScrollbackViewport _scrollback;
    ClickDetector _clickDetector;
    bool _mouseButtonPressed;  // Track mouse button state

    // State
    bool _cursorVisible = true;
    bool _cursorBlink = true;
    CursorStyle _cursorStyle = CursorStyle.block;
    long _lastBlinkTime;
    bool _cursorBlinkState = true;
    int _blinkIntervalMs = 530;

    // Colors (ARGB)
    uint _foregroundColor = 0xFFFFFFFF;
    uint _backgroundColor = 0xFF000000;
    uint _selectionColor = 0x80FFFFFF;
    uint _selectionTextColor = 0x00000000;
    bool _selectionTextOverride;
    uint _cursorColor = 0xFFFFFFFF;

    // Callbacks for PTY communication
    void delegate(const(ubyte)[]) _onOutput;

public:
    // === Signals ===

    Signal!(string) titleChanged;
    Signal!(int, int) sizeChanged;
    Signal!() bellRang;
    Signal!(string) hyperlinkActivated;
    Signal!(int, int) contextMenuRequested;  // Screen coordinates for context menu

    // === Construction ===

    this(FontAtlas fontAtlas, CellRenderer renderer) {
        _fontAtlas = fontAtlas;
        _renderer = renderer;
        _cellWidth = fontAtlas.cellWidth;
        _cellHeight = fontAtlas.cellHeight;

        _inputHandler = new InputHandler();
        _selection = new Selection(&getCharAt);
        _scrollback = new ScrollbackViewport(24, 10000);  // 24 rows, 10k scrollback
        // _clickDetector is a struct, initialized by default

        // Default size
        _cols = 80;
        _rows = 24;
    }

    // === Properties ===

    /// Terminal columns
    @property int columns() const { return _cols; }

    /// Terminal rows
    @property int rows() const { return _rows; }

    /// Cell width in pixels
    @property int cellWidth() const { return _cellWidth; }

    /// Cell height in pixels
    @property int cellHeight() const { return _cellHeight; }

    /// Cursor visibility
    @property bool cursorVisible() const { return _cursorVisible; }
    @property void cursorVisible(bool value) {
        _cursorVisible = value;
        invalidateVisual();
    }

    /// Cursor blink enabled
    @property bool cursorBlink() const { return _cursorBlink; }
    @property void cursorBlink(bool value) {
        _cursorBlink = value;
        _cursorBlinkState = true;
        invalidateVisual();
    }

    /// Cursor style
    @property CursorStyle cursorStyle() const { return _cursorStyle; }
    @property void cursorStyle(CursorStyle value) {
        _cursorStyle = value;
        invalidateVisual();
    }

    /// Foreground color
    @property uint foregroundColor() const { return _foregroundColor; }
    @property void foregroundColor(uint value) {
        _foregroundColor = value;
        invalidateVisual();
    }

    /// Background color
    @property uint backgroundColor() const { return _backgroundColor; }
    @property void backgroundColor(uint value) {
        _backgroundColor = value;
        invalidateVisual();
    }

    /// Selection highlight color (ARGB)
    @property uint selectionColor() const { return _selectionColor; }
    @property void selectionColor(uint value) {
        _selectionColor = value;
        invalidateVisual();
    }

    /// Selection text override color (ARGB)
    @property bool selectionTextOverride() const { return _selectionTextOverride; }
    @property uint selectionTextColor() const { return _selectionTextColor; }
    @property void selectionTextColor(uint value) {
        _selectionTextColor = value;
        _selectionTextOverride = true;
        invalidateVisual();
    }

    void clearSelectionTextColor() {
        _selectionTextOverride = false;
        invalidateVisual();
    }

    /**
     * Set selection colors from RGBA floats (0..1).
     * If selectionFg is omitted or invalid, selection uses existing fg.
     */
    void setSelectionColors(const(float)[] selectionBg,
                            const(float)[] selectionFg = null) {
        if (selectionBg.length == 4) {
            _selectionColor = rgbaToArgb([selectionBg[0], selectionBg[1],
                                          selectionBg[2], selectionBg[3]]);
        }
        if (selectionFg.length == 4) {
            _selectionTextColor = rgbaToArgb([selectionFg[0], selectionFg[1],
                                              selectionFg[2], selectionFg[3]]);
            _selectionTextOverride = true;
        } else {
            _selectionTextOverride = false;
        }
        invalidateVisual();
    }

    /// Selection handler
    @property Selection selection() { return _selection; }

    /// Scrollback viewport
    @property ScrollbackViewport scrollback() { return _scrollback; }

    /// Input handler
    @property InputHandler inputHandler() { return _inputHandler; }

    // === Terminal Operations ===

    /**
     * Set output callback for PTY data.
     */
    void setOutputCallback(void delegate(const(ubyte)[]) callback) {
        _onOutput = callback;
    }

    /**
     * Process data from PTY.
     */
    void feedData(const(ubyte)[] data) {
        if (_emulator !is null) {
            _emulator.feedData(data);
            invalidateVisual();
        }
    }

    /**
     * Resize terminal to new dimensions.
     */
    void resize(int cols, int rows) {
        if (_cols != cols || _rows != rows) {
            _cols = cols;
            _rows = rows;

            if (_emulator !is null) {
                _emulator.resize(cols, rows);
            }

            _scrollback.resize(rows);
            sizeChanged.emit(cols, rows);
            invalidateVisual();
        }
    }

    /**
     * Resize based on pixel dimensions.
     */
    void resizeToPixels(int width, int height) {
        int cols = max(1, width / _cellWidth);
        int rows = max(1, height / _cellHeight);
        resize(cols, rows);
    }

    /**
     * Get selected text.
     */
    string getSelectedText() {
        if (!_selection.hasSelection) return "";
        return _selection.getSelectedText(&getCharAt, _cols);
    }

    /**
     * Copy selection to clipboard.
     */
    void copySelection() {
        string text = getSelectedText();
        if (text.length > 0) {
            // Platform-specific clipboard handling
            // Will be implemented in clipboard.d
        }
    }

    /**
     * Paste from clipboard.
     */
    void paste(string text) {
        if (_onOutput !is null && text.length > 0) {
            // Send bracketed paste if mode is enabled
            auto start = _inputHandler.bracketedPasteStart();
            if (start !is null) {
                _onOutput(start);
            }
            _onOutput(cast(const(ubyte)[])text);
            auto end = _inputHandler.bracketedPasteEnd();
            if (end !is null) {
                _onOutput(end);
            }
        }
    }

    /**
     * Send text to PTY.
     */
    void sendText(string text) {
        if (_onOutput !is null) {
            _onOutput(cast(const(ubyte)[])text);
        }
    }

    /**
     * Send key to PTY.
     */
    void sendKey(int key, int scancode, int action, int mods) {
        _inputHandler.updateKeyState(scancode, action);
        auto seq = _inputHandler.translateKey(key, scancode, action, mods);
        if (seq.length > 0 && _onOutput !is null) {
            _onOutput(seq);
        } else if ((action == GLFW_PRESS || action == GLFW_REPEAT) &&
            key == GLFW_KEY_UNKNOWN) {
            auto fallback = _inputHandler.translateUnknownKey(scancode, mods);
            if (fallback.length > 0 && _onOutput !is null) {
                _onOutput(fallback);
            }
        }
    }

    /**
     * Send character to PTY.
     */
    void sendChar(dchar codepoint, int mods) {
        auto seq = _inputHandler.translateChar(codepoint, mods);
        if (seq.length > 0 && _onOutput !is null) {
            _onOutput(seq);
        }
    }

    // === Mouse Handling ===

    /**
     * Handle mouse button event.
     */
    void handleMouseButton(int button, int action, int mods, double xpos, double ypos) {
        int col = cast(int)(xpos / _cellWidth);
        int row = cast(int)(ypos / _cellHeight);

        // Adjust for scrollback
        row += _scrollback.offset;

        if (action == 1) {  // Press
            _mouseButtonPressed = true;

            if (button == 0) {  // Left button
                if (mods & 0x1) {  // Shift - extend selection
                    _selection.extend(col, row);
                } else {
                    // Register click and get click count (1, 2, or 3)
                    _clickDetector.click(col, row);
                    // Selection.start() handles word/line expansion internally
                    _selection.start(col, row, _clickDetector.selectionType());
                }
                invalidateVisual();
            } else if (button == 1) {  // Right button - context menu
                // Request context menu at screen position
                contextMenuRequested.emit(cast(int)xpos, cast(int)ypos);
            }

            // Send to terminal if mouse reporting enabled
            if (_inputHandler.mouseMode != MouseMode.none) {
                auto seq = _inputHandler.translateMouseButton(
                    button, true, col, row, mods);
                if (seq.length > 0 && _onOutput !is null) {
                    _onOutput(seq);
                }
            }
        } else if (action == 0) {  // Release
            _mouseButtonPressed = false;

            if (button == 0) {
                _selection.finish();
            }

            if (_inputHandler.mouseMode != MouseMode.none) {
                auto seq = _inputHandler.translateMouseButton(
                    button, false, col, row, mods);
                if (seq.length > 0 && _onOutput !is null) {
                    _onOutput(seq);
                }
            }
        }
    }

    /**
     * Handle mouse motion.
     */
    void handleMouseMove(double xpos, double ypos, int mods) {
        int col = cast(int)(xpos / _cellWidth);
        int row = cast(int)(ypos / _cellHeight);
        row += _scrollback.offset;

        // Extend selection if dragging
        if (_selection.active) {
            _selection.update(col, row);
            invalidateVisual();
        }

        // Mouse motion reporting
        if (_inputHandler.mouseMode == MouseMode.anyEvent ||
            (_inputHandler.mouseMode == MouseMode.buttonEvent && _mouseButtonPressed)) {
            // Send motion event
        }
    }

    /**
     * Handle scroll event.
     */
    void handleScroll(double xoffset, double yoffset, int mods, int x, int y) {
        if (mods & 0x1) {  // Shift - horizontal scroll (not typical for terminals)
            return;
        }

        // Alt+scroll or Shift+scroll for scrollback
        if ((mods & 0x4) || _inputHandler.mouseMode == MouseMode.none) {
            int lines = cast(int)(yoffset * 3);  // 3 lines per scroll notch
            _scrollback.scroll(lines);
            invalidateVisual();
            return;
        }

        // Send to application
        auto seq = _inputHandler.translateScroll(xoffset, yoffset, mods, x, y);
        if (seq.length > 0 && _onOutput !is null) {
            _onOutput(seq);
        }
    }

    // === Update ===

    /**
     * Update cursor blink state.
     */
    void updateBlink(long currentTimeMs) {
        if (!_cursorBlink) return;

        if (currentTimeMs - _lastBlinkTime >= _blinkIntervalMs) {
            _cursorBlinkState = !_cursorBlinkState;
            _lastBlinkTime = currentTimeMs;
            invalidateVisual();
        }
    }

protected:
    // === Layout ===

    override Size measureOverride(Size availableSize) {
        // Desired size based on columns/rows
        return Size(_cols * _cellWidth, _rows * _cellHeight);
    }

    override void arrangeOverride(Size finalSize) {
        // Resize terminal to fit bounds
        resizeToPixels(finalSize.width, finalSize.height);
    }

    // === Rendering ===

    override void renderOverride(RenderContext ctx) {
        if (_renderer is null) return;

        // Clear background
        ctx.fillRect(Rect(0, 0, _bounds.width, _bounds.height), _backgroundColor);

        // Get visible range accounting for scrollback
        int startRow = _scrollback.offset;
        int endRow = startRow + _rows;

        ResolvedTheme theme = *defaultResolvedTheme();
        theme.foreground = argbToRgba(_foregroundColor);
        theme.background = argbToRgba(_backgroundColor);

        // Render cells
        foreach (row; startRow .. endRow) {
            int screenY = (row - startRow) * _cellHeight;

            foreach (col; 0 .. _cols) {
                int screenX = col * _cellWidth;
                Rect cellRect = Rect(screenX, screenY, _cellWidth, _cellHeight);

                // Get cell content from emulator
                dchar ch;
                uint fg = _foregroundColor;
                uint bg = _backgroundColor;

                if (_emulator !is null) {
                    auto cell = _emulator.getCell(col, row);
                    ch = cell.ch;
                    float[4] fgRgba;
                    float[4] bgRgba;
                    attributesToColors(cell.attributes, fgRgba, bgRgba, &theme);
                    fg = rgbaToArgb(fgRgba);
                    bg = rgbaToArgb(bgRgba);
                } else {
                    ch = ' ';
                }

                // Selection highlight
                if (_selection.isSelected(col, row)) {
                    bg = blendColors(bg, _selectionColor);
                    if (_selectionTextOverride) {
                        fg = _selectionTextColor;
                    }
                }

                // Render cell background
                if (bg != _backgroundColor) {
                    ctx.fillRect(cellRect, bg);
                }

                // Render character
                if (ch > ' ') {
                    ctx.drawText([cast(char)ch], Point(screenX, screenY), fg);
                }
            }
        }

        // Render cursor
        if (_cursorVisible && (_cursorBlinkState || !_cursorBlink)) {
            int cursorCol, cursorRow;
            if (_emulator !is null) {
                cursorCol = _emulator.cursorCol;
                cursorRow = _emulator.cursorRow;
            } else {
                cursorCol = 0;
                cursorRow = 0;
            }

            // Only show if cursor is in visible area
            if (cursorRow >= startRow && cursorRow < endRow) {
                int screenX = cursorCol * _cellWidth;
                int screenY = (cursorRow - startRow) * _cellHeight;

                final switch (_cursorStyle) {
                    case CursorStyle.block:
                        ctx.fillRect(Rect(screenX, screenY, _cellWidth, _cellHeight), _cursorColor);
                        break;
                    case CursorStyle.underline:
                        ctx.fillRect(Rect(screenX, screenY + _cellHeight - 2, _cellWidth, 2), _cursorColor);
                        break;
                    case CursorStyle.bar:
                        ctx.fillRect(Rect(screenX, screenY, 2, _cellHeight), _cursorColor);
                        break;
                }
            }
        }

        // Render scrollbar if needed
        if (_scrollback.scrollbackLines > 0) {
            renderScrollbar(ctx);
        }
    }

private:
    dchar getCharAt(int col, int row) {
        if (_emulator !is null) {
            auto cell = _emulator.getCell(col, row);
            return cell.ch;
        }
        return ' ';
    }

    bool isWordChar(dchar c) {
        import std.uni : isAlphaNum;
        return isAlphaNum(c) || c == '_' || c == '-' || c == '.';
    }

    uint blendColors(uint base, uint overlay) {
        uint ba = (base >> 24) & 0xFF;
        uint br = (base >> 16) & 0xFF;
        uint bg = (base >> 8) & 0xFF;
        uint bb = base & 0xFF;

        uint oa = (overlay >> 24) & 0xFF;
        uint or_ = (overlay >> 16) & 0xFF;
        uint og = (overlay >> 8) & 0xFF;
        uint ob = overlay & 0xFF;

        float alpha = oa / 255.0f;
        uint r = cast(uint)(or_ * alpha + br * (1 - alpha));
        uint g = cast(uint)(og * alpha + bg * (1 - alpha));
        uint b = cast(uint)(ob * alpha + bb * (1 - alpha));

        return (0xFF << 24) | (r << 16) | (g << 8) | b;
    }

    float[4] argbToRgba(uint color) {
        float a = ((color >> 24) & 0xFF) / 255.0f;
        float r = ((color >> 16) & 0xFF) / 255.0f;
        float g = ((color >> 8) & 0xFF) / 255.0f;
        float b = (color & 0xFF) / 255.0f;
        return [r, g, b, a];
    }

    uint rgbaToArgb(in float[4] color) {
        uint a = cast(uint)clamp(color[3] * 255.0f, 0.0f, 255.0f);
        uint r = cast(uint)clamp(color[0] * 255.0f, 0.0f, 255.0f);
        uint g = cast(uint)clamp(color[1] * 255.0f, 0.0f, 255.0f);
        uint b = cast(uint)clamp(color[2] * 255.0f, 0.0f, 255.0f);
        return (a << 24) | (r << 16) | (g << 8) | b;
    }

    void renderScrollbar(RenderContext ctx) {
        // Scrollbar dimensions
        int scrollbarWidth = 12;
        int scrollbarX = _bounds.width - scrollbarWidth;
        int scrollbarHeight = _bounds.height;

        // Track
        ctx.fillRect(Rect(scrollbarX, 0, scrollbarWidth, scrollbarHeight), 0xFF202020);

        // Thumb
        auto state = calculateScrollbar(_scrollback);
        if (!state.visible) return;

        int thumbY = cast(int)(state.thumbPosition * (scrollbarHeight - state.thumbSize * scrollbarHeight));
        int thumbHeight = cast(int)(state.thumbSize * scrollbarHeight);
        thumbHeight = max(thumbHeight, 20);  // Minimum thumb size

        ctx.fillRect(Rect(scrollbarX + 2, thumbY, scrollbarWidth - 4, thumbHeight), 0xFF606060);
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

unittest {
    // Basic terminal widget creation (without renderer)
    // Just verify the class compiles
    static assert(__traits(compiles, {
        TerminalWidget tw;
    }));
}
