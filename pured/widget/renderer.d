/**
 * Widget Renderer
 *
 * OpenGL renderer for UI widgets, implementing the RenderContext interface.
 * Renders filled rectangles, outlined rectangles, text, and styled UI elements.
 *
 * Architecture:
 * - Uses OpenGL quad rendering (instanced or immediate mode)
 * - Shares FontAtlas with CellRenderer for consistent text rendering
 * - Implements clipping via rectangle intersection
 * - Maintains viewport and projection matrix for coordinate transforms
 * - Supports themed colors and UI styling
 *
 * Rendering Modes:
 * 1. Basic shapes (rectangles, lines)
 * 2. Styled containers (dialogs, menus) with borders and padding
 * 3. Buttons and interactive elements with hover/pressed states
 * 4. Text rendering via FontAtlas glyphs
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.renderer;

version (PURE_D_BACKEND):

import bindbc.opengl;
import pured.widget.base : RenderContext, Rect, Point;
import pured.fontatlas : FontAtlas, GlyphInfo;
import pured.text.shaper : TextShaper, ShapedGlyph;
import std.stdio : stderr, writefln;
import std.algorithm : min, max;
import std.conv : to;
import std.utf : decode;

/**
 * Theme colors for UI rendering.
 */
struct ThemeColors {
    // Window/dialog colors
    uint windowBg = 0xFF1E1E1E;        // Dark window background
    uint windowBorder = 0xFF666666;    // Window border
    uint titleBarBg = 0xFF007ACC;      // Title bar (blue)
    uint titleBarText = 0xFFFFFFFF;    // Title text (white)

    // Menu colors
    uint menuBg = 0xFF2B2B2B;          // Menu background
    uint menuBorder = 0xFF666666;      // Menu border
    uint menuItem = 0xFFE0E0E0;        // Menu item text
    uint menuItemBg = 0xFF2B2B2B;      // Menu item background
    uint menuItemHover = 0xFF404040;   // Menu item hover
    uint menuSeparator = 0xFF555555;   // Separator line

    // Button colors
    uint buttonBg = 0xFF0E639C;        // Button background
    uint buttonBgHover = 0xFF1177BB;   // Button hover
    uint buttonBgActive = 0xFF0D47A1;  // Button pressed
    uint buttonText = 0xFFFFFFFF;      // Button text
    uint buttonBorder = 0xFF555555;    // Button border

    // Text colors
    uint textPrimary = 0xFFE0E0E0;     // Primary text
    uint textSecondary = 0xFFA0A0A0;   // Secondary text
    uint textDisabled = 0xFF606060;    // Disabled text

    // Focus/selection
    uint focusBorder = 0xFF0E639C;     // Focus ring
    uint selectionBg = 0xFF094771;     // Selection background

    // Status colors
    uint success = 0xFF4EC9B0;         // Success (green)
    uint warning = 0xFFDCDC00;         // Warning (yellow)
    uint error = 0xFFF48771;           // Error (red)
}

/**
 * OpenGL widget renderer.
 *
 * Renders 2D UI elements (rectangles, text, styled containers) using OpenGL.
 * Shares FontAtlas with CellRenderer for text rendering consistency.
 * Supports themed colors and visual hierarchy.
 */
class WidgetRenderer : RenderContext {
private:
    int _viewportWidth;
    int _viewportHeight;
    FontAtlas _fontAtlas;  // Shared reference to CellRenderer's font atlas
    TextShaper _shaper;    // Text shaper for glyph layout
    GLuint _shaderProgram;
    GLuint _vao;
    GLuint _vbo;
    GLint _projectionLoc;
    GLint _colorLoc;
    GLint _positionLoc;
    GLint _texCoordLoc;
    GLint _fontTextureLoc;

    // Text shape buffers
    ShapedGlyph[] _shapeBuffer;
    dchar[] _textBuffer;

    // Clipping stack
    Rect[] _clipStack;

    // Theme
    ThemeColors _theme;

    bool _initialized = false;

public:
    /**
     * Initialize the widget renderer.
     *
     * Params:
     *   fontAtlas = Shared font atlas from CellRenderer
     *   viewportWidth = Initial viewport width in pixels
     *   viewportHeight = Initial viewport height in pixels
     *
     * Returns: true if initialization succeeds
     */
    bool initialize(FontAtlas fontAtlas, int viewportWidth, int viewportHeight) {
        if (fontAtlas is null) {
            stderr.writefln("Error: WidgetRenderer requires a FontAtlas");
            return false;
        }

        _fontAtlas = fontAtlas;
        _viewportWidth = viewportWidth;
        _viewportHeight = viewportHeight;
        _clipStack.length = 0;

        // Allocate text shape buffers
        _shapeBuffer.length = 512;  // Max glyphs per line
        _textBuffer.length = 512;   // Max characters per string

        // Initialize text shaper for text rendering
        _shaper = new TextShaper();
        if (!_shaper.initialize(fontAtlas.ftFace, fontAtlas.fontSize)) {
            stderr.writefln("Warning: Failed to initialize TextShaper for widget rendering");
            // Continue anyway - text rendering will be unavailable but shapes will work
            _shaper = null;
        }

        // Create shader program
        if (!createShaderProgram()) {
            stderr.writefln("Error: Failed to create widget shader program");
            return false;
        }

        // Create geometry buffers
        if (!createGeometryBuffers()) {
            stderr.writefln("Error: Failed to create widget geometry buffers");
            return false;
        }

        _initialized = true;
        return true;
    }

    /**
     * Update viewport when window is resized.
     */
    void setViewport(int width, int height) {
        _viewportWidth = width;
        _viewportHeight = height;
    }

    /**
     * Fill rectangle with solid color.
     */
    void fillRect(Rect rect, uint color) {
        if (!_initialized || rect.isEmpty) return;

        Rect clipped = applyClipping(rect);
        if (clipped.isEmpty) return;

        ubyte r = cast(ubyte)((color >> 16) & 0xFF);
        ubyte g = cast(ubyte)((color >> 8) & 0xFF);
        ubyte b = cast(ubyte)(color & 0xFF);
        ubyte a = cast(ubyte)((color >> 24) & 0xFF);
        if (a == 0) a = 0xFF;  // Default to opaque if alpha not specified

        float fr = r / 255.0f;
        float fg = g / 255.0f;
        float fb = b / 255.0f;
        float fa = a / 255.0f;

        drawQuad(clipped, fr, fg, fb, fa);
    }

    /**
     * Draw rectangle outline.
     */
    void drawRect(Rect rect, uint color, int lineWidth = 1) {
        if (!_initialized || rect.isEmpty) return;

        // For now, draw as 4 line segments (top, right, bottom, left)
        ubyte r = cast(ubyte)((color >> 16) & 0xFF);
        ubyte g = cast(ubyte)((color >> 8) & 0xFF);
        ubyte b = cast(ubyte)(color & 0xFF);
        ubyte a = cast(ubyte)((color >> 24) & 0xFF);
        if (a == 0) a = 0xFF;

        float fr = r / 255.0f;
        float fg = g / 255.0f;
        float fb = b / 255.0f;
        float fa = a / 255.0f;

        // Top line
        fillRect(Rect(rect.x, rect.y, rect.width, lineWidth), color);
        // Bottom line
        fillRect(Rect(rect.x, rect.y + rect.height - lineWidth, rect.width, lineWidth), color);
        // Left line
        fillRect(Rect(rect.x, rect.y, lineWidth, rect.height), color);
        // Right line
        fillRect(Rect(rect.x + rect.width - lineWidth, rect.y, lineWidth, rect.height), color);
    }

    /**
     * Draw text at position.
     *
     * Uses TextShaper for complex text layout and FontAtlas for glyph rendering.
     */
    void drawText(string text, Point pos, uint color) {
        if (!_initialized || text.length == 0) return;
        if (_fontAtlas is null) return;
        if (_shaper is null || !_shaper.available) return;

        // Extract color components (ARGB format)
        ubyte r = cast(ubyte)((color >> 16) & 0xFF);
        ubyte g = cast(ubyte)((color >> 8) & 0xFF);
        ubyte b = cast(ubyte)(color & 0xFF);
        ubyte a = cast(ubyte)((color >> 24) & 0xFF);
        if (a == 0) a = 0xFF;  // Default to opaque

        float fr = r / 255.0f;
        float fg = g / 255.0f;
        float fb = b / 255.0f;
        float fa = a / 255.0f;

        // Convert UTF-8 string to dchar array
        size_t bufIdx = 0;
        foreach (dchar ch; text) {
            if (bufIdx >= _textBuffer.length) break;
            _textBuffer[bufIdx++] = ch;
        }

        if (bufIdx == 0) return;

        // Shape the text
        uint shapedCount = 0;
        if (!_shaper.shapeLine(_textBuffer[0 .. bufIdx], _shapeBuffer, shapedCount)) {
            return;  // Shaping failed
        }

        if (shapedCount == 0) return;

        // Render each shaped glyph
        float penX = pos.x;
        float baselineY = pos.y + _fontAtlas.cellHeight;

        foreach (i; 0 .. shapedCount) {
            const ShapedGlyph glyph = _shapeBuffer[i];

            // Skip empty glyphs
            if (glyph.glyphIndex == 0) {
                penX += (glyph.xAdvance / 64.0f);
                continue;
            }

            // Get glyph info from atlas
            GlyphInfo glyphInfo = _fontAtlas.getGlyphByIndex(glyph.glyphIndex);
            if (!glyphInfo.valid || glyphInfo.width <= 0 || glyphInfo.height <= 0) {
                penX += (glyph.xAdvance / 64.0f);
                continue;
            }

            // Calculate glyph position with metrics
            float xOffset = glyph.xOffset / 64.0f;
            float yOffset = glyph.yOffset / 64.0f;
            float bearingX = glyphInfo.bearingX;
            float bearingY = glyphInfo.bearingY;
            float glyphW = glyphInfo.width;
            float glyphH = glyphInfo.height;

            float gx0 = penX + xOffset + bearingX;
            float gy0 = baselineY - bearingY - yOffset;

            // Draw the glyph
            Rect glyphRect = Rect(cast(int)gx0, cast(int)gy0, cast(int)glyphW, cast(int)glyphH);
            drawGlyph(glyphRect, glyphInfo, fr, fg, fb, fa);

            // Advance pen position
            penX += (glyph.xAdvance / 64.0f);
        }
    }

    /**
     * Push a clipping rectangle onto the stack.
     */
    void pushClip(Rect clip) {
        if (!_initialized) return;

        if (_clipStack.length == 0) {
            // First clip is against viewport
            Rect viewport = Rect(0, 0, _viewportWidth, _viewportHeight);
            _clipStack ~= clip.intersection(viewport);
        } else {
            // Subsequent clips intersect with current clip
            Rect current = _clipStack[$ - 1];
            _clipStack ~= clip.intersection(current);
        }
    }

    /**
     * Pop a clipping rectangle from the stack.
     */
    void popClip() {
        if (!_initialized || _clipStack.length == 0) return;
        _clipStack.length--;
    }

    /**
     * Get current clipping bounds.
     */
    Rect currentClip() {
        if (_clipStack.length == 0) {
            return Rect(0, 0, _viewportWidth, _viewportHeight);
        }
        return _clipStack[$ - 1];
    }

    /**
     * Reset renderer state (call at start of frame).
     */
    void reset() {
        _clipStack.length = 0;
    }

    // === Styled Rendering ===

    /**
     * Set theme colors.
     */
    void setTheme(ThemeColors theme) {
        _theme = theme;
    }

    /**
     * Get current theme.
     */
    @property ThemeColors theme() const { return _theme; }

    /**
     * Draw a styled button.
     *
     * Params:
     *   bounds = Button rectangle
     *   label = Button text (placeholder - requires text rendering)
     *   hovered = Whether button is hovered
     *   pressed = Whether button is pressed
     */
    void drawButton(Rect bounds, string label, bool hovered = false, bool pressed = false) {
        uint bgColor = pressed ? _theme.buttonBgActive :
                       hovered ? _theme.buttonBgHover : _theme.buttonBg;

        // Draw button background
        fillRect(bounds, bgColor);

        // Draw button border
        drawRect(bounds, _theme.buttonBorder, 1);

        // Draw text label (centered in button)
        if (label.length > 0) {
            // Center text horizontally and vertically
            int textX = bounds.x + 4;  // Left padding
            int textY = bounds.y + 2;  // Top padding
            drawText(label, Point(textX, textY), _theme.buttonText);
        }
    }

    /**
     * Draw a row of buttons (typically for dialog button bars).
     *
     * Params:
     *   bounds = Button bar bounds (height will be used for all buttons)
     *   labels = Array of button labels
     *   hoveredIndex = Index of hovered button (-1 for none)
     *   pressedIndex = Index of pressed button (-1 for none)
     *   rightAlign = Whether to right-align buttons (default true)
     *   spacing = Pixel spacing between buttons (default 4)
     *   buttonWidth = Width of each button (default 80)
     */
    void drawButtonBar(Rect bounds, string[] labels, int hoveredIndex = -1, int pressedIndex = -1,
                       bool rightAlign = true, int spacing = 4, int buttonWidth = 80) {
        if (labels.length == 0) return;

        // Calculate button positions
        int totalWidth = cast(int)labels.length * buttonWidth + (cast(int)labels.length - 1) * spacing;
        int startX = rightAlign ? (bounds.x + bounds.width - totalWidth - 8) : (bounds.x + 8);
        int buttonY = bounds.y + (bounds.height - 24) / 2;  // Center vertically
        int buttonHeight = 24;

        // Draw each button
        foreach (i, label; labels) {
            int buttonX = startX + cast(int)i * (buttonWidth + spacing);
            Rect buttonBounds = Rect(buttonX, buttonY, buttonWidth, buttonHeight);

            bool hovered = (cast(int)i == hoveredIndex);
            bool pressed = (cast(int)i == pressedIndex);

            drawButton(buttonBounds, label, hovered, pressed);
        }
    }

    /**
     * Draw a tab bar (E.5.2: Tab bar rendering).
     *
     * Renders a horizontal strip of tabs with active tab highlighting.
     *
     * Params:
     *   bounds = Tab bar bounds
     *   tabLabels = Array of tab names
     *   selectedIndex = Currently selected tab index
     */
    void drawTabBar(Rect bounds, string[] tabLabels, int selectedIndex = 0) {
        if (tabLabels.length == 0) return;

        // Draw tab bar background
        fillRect(bounds, _theme.windowBg);

        // Draw separator line below tab bar
        Rect separator = Rect(bounds.x, bounds.y + bounds.height - 1, bounds.width, 1);
        fillRect(separator, _theme.windowBorder);

        // Calculate tab width (distribute equally)
        int tabWidth = bounds.width / cast(int)tabLabels.length;
        int tabHeight = bounds.height;

        // Draw each tab
        foreach (i, label; tabLabels) {
            int tabX = bounds.x + cast(int)i * tabWidth;
            Rect tabRect = Rect(tabX, bounds.y, tabWidth, tabHeight);

            bool isSelected = (cast(int)i == selectedIndex);

            // Draw tab background
            uint bgColor = isSelected ? _theme.titleBarBg : _theme.windowBg;
            fillRect(tabRect, bgColor);

            // Draw tab border (left and right sides)
            if (i > 0) {
                Rect leftBorder = Rect(tabX, bounds.y, 1, tabHeight);
                fillRect(leftBorder, _theme.windowBorder);
            }

            // Draw active tab indicator (bottom border)
            if (isSelected) {
                Rect indicator = Rect(tabX, bounds.y + bounds.height - 2, tabWidth, 2);
                fillRect(indicator, _theme.focusBorder);
            }

            // Draw tab label
            if (label.length > 0) {
                int textX = tabX + 8;
                int textY = bounds.y + (bounds.height - 16) / 2;  // Center vertically
                uint textColor = isSelected ? _theme.titleBarText : _theme.textPrimary;
                drawText(label, Point(textX, textY), textColor);
            }
        }
    }

    /**
     * Draw a styled dialog/window with title bar.
     *
     * Params:
     *   bounds = Dialog bounds
     *   title = Window title
     *   hasFocus = Whether window has focus
     */
    void drawDialog(Rect bounds, string title, bool hasFocus = true) {
        const int titleBarHeight = 24;

        // Draw window background
        fillRect(bounds, _theme.windowBg);

        // Draw title bar
        Rect titleBar = Rect(bounds.x, bounds.y, bounds.width, titleBarHeight);
        fillRect(titleBar, hasFocus ? _theme.titleBarBg : 0xFF555555);

        // Draw window border
        uint borderColor = hasFocus ? _theme.focusBorder : _theme.windowBorder;
        drawRect(bounds, borderColor, 2);

        // Draw title text
        if (title.length > 0) {
            int titleX = bounds.x + 8;  // Left padding
            int titleY = bounds.y + 4;  // Top padding
            drawText(title, Point(titleX, titleY), _theme.titleBarText);
        }
    }

    /**
     * Draw a styled menu item.
     *
     * Params:
     *   bounds = Item rectangle
     *   label = Item text
     *   selected = Whether item is selected
     *   enabled = Whether item is enabled
     */
    void drawMenuItem(Rect bounds, string label, bool selected = false, bool enabled = true) {
        // Draw background
        uint bgColor = selected ? _theme.menuItemHover : _theme.menuItemBg;
        fillRect(bounds, bgColor);

        // Determine text color
        uint textColor = enabled ? (selected ? 0xFFFFFFFF : _theme.menuItem) : _theme.textDisabled;

        // Draw text label
        if (label.length > 0) {
            int textX = bounds.x + 4;  // Left padding
            int textY = bounds.y + 2;  // Top padding
            drawText(label, Point(textX, textY), textColor);
        }
    }

    /**
     * Draw a focus rectangle (keyboard focus indicator).
     *
     * Params:
     *   bounds = Element bounds
     *   thickness = Border thickness in pixels
     */
    void drawFocusRect(Rect bounds, int thickness = 2) {
        drawRect(bounds, _theme.focusBorder, thickness);
    }

    /**
     * Draw a focus ring (E.3.1: Focus Ring Rendering).
     *
     * Renders a colored rectangle outline around a focused widget.
     * No animation: solid outline only for simplicity.
     *
     * Params:
     *   bounds = Focused widget bounds
     *   thickness = Ring thickness in pixels (default 2)
     *   color = Ring color (default theme focus border color)
     */
    void drawFocusRing(Rect bounds, int thickness = 2, uint color = 0) {
        if (color == 0) {
            color = _theme.focusBorder;
        }
        drawRect(bounds, color, thickness);
    }

    /**
     * Draw a styled separator/divider.
     *
     * Params:
     *   x = Starting X coordinate
     *   y = Y coordinate
     *   width = Separator width
     *   thickness = Line thickness
     */
    void drawSeparator(int x, int y, int width, int thickness = 1) {
        Rect sep = Rect(x, y, width, thickness);
        fillRect(sep, _theme.menuSeparator);
    }

    /**
     * Draw a styled container (panel) with optional border.
     *
     * Params:
     *   bounds = Container bounds
     *   hasBorder = Whether to draw border
     */
    void drawContainer(Rect bounds, bool hasBorder = true) {
        fillRect(bounds, _theme.windowBg);

        if (hasBorder) {
            drawRect(bounds, _theme.windowBorder, 1);
        }
    }

    /**
     * Draw a tooltip/hint box.
     *
     * Params:
     *   bounds = Tooltip bounds
     *   text = Tooltip text
     */
    void drawTooltip(Rect bounds, string text) {
        // Draw background with slight transparency
        fillRect(bounds, 0xCC2B2B2B);

        // Draw border
        drawRect(bounds, _theme.windowBorder, 1);

        // Draw tooltip text
        if (text.length > 0) {
            int textX = bounds.x + 4;  // Left padding
            int textY = bounds.y + 2;  // Top padding
            drawText(text, Point(textX, textY), 0xFFE0E0E0);  // Light gray text
        }
    }

    /**
     * Draw a modal overlay (semi-transparent full-screen dimming).
     *
     * Disables clipping to ensure full-screen coverage.
     * Should be rendered BEFORE dialog frame for correct layering.
     *
     * Params:
     *   bounds = Screen bounds to cover (typically viewport-sized rectangle)
     *   alpha = Overlay opacity from 0.0 (transparent) to 1.0 (opaque), default 0.5f
     */
    void drawModalOverlay(Rect bounds, float alpha = 0.5f) {
        if (!_initialized) return;

        // Create overlay color: black with specified alpha
        ubyte a = cast(ubyte)(alpha * 255.0f);
        uint overlayColor = (a << 24) | 0x000000;

        // Save current clip state and disable clipping
        auto savedClipStack = _clipStack;
        _clipStack.length = 0;

        // Draw full-screen semi-transparent quad
        fillRect(bounds, overlayColor);

        // Restore clipping state
        _clipStack = savedClipStack;
    }

    /**
     * Draw a form label (E.5.3: Form widget rendering).
     *
     * Params:
     *   pos = Text position
     *   text = Label text
     */
    void drawLabel(Point pos, string text) {
        drawText(text, pos, _theme.textPrimary);
    }

    /**
     * Draw a text input field (E.5.3: Form widget rendering).
     *
     * Params:
     *   bounds = Input field bounds
     *   text = Current text content
     *   hasFocus = Whether field has focus
     *   cursorPos = Cursor position (optional, -1 = no cursor)
     */
    void drawTextInput(Rect bounds, string text, bool hasFocus = false, int cursorPos = -1) {
        // Draw background
        fillRect(bounds, _theme.windowBg);

        // Draw border
        uint borderColor = hasFocus ? _theme.focusBorder : _theme.windowBorder;
        drawRect(bounds, borderColor, 1);

        // Draw text
        if (text.length > 0) {
            int textX = bounds.x + 4;
            int textY = bounds.y + 2;
            drawText(text, Point(textX, textY), _theme.textPrimary);
        }

        // Draw cursor if focused
        if (hasFocus && cursorPos >= 0) {
            // Simple cursor: vertical line at end of text
            int cursorX = bounds.x + 4 + cast(int)text.length * 8;  // Rough estimate
            Rect cursor = Rect(cursorX, bounds.y + 2, 2, bounds.height - 4);
            fillRect(cursor, _theme.focusBorder);
        }
    }

    /**
     * Draw a checkbox control (E.5.3: Form widget rendering).
     *
     * Params:
     *   bounds = Checkbox bounds
     *   label = Checkbox label text
     *   checked = Whether checkbox is checked
     *   hasFocus = Whether control has focus
     */
    void drawCheckbox(Rect bounds, string label, bool checked = false, bool hasFocus = false) {
        // Draw checkbox box (12x12)
        Rect checkBox = Rect(bounds.x, bounds.y + (bounds.height - 12) / 2, 12, 12);
        fillRect(checkBox, _theme.windowBg);

        // Draw checkbox border
        uint borderColor = hasFocus ? _theme.focusBorder : _theme.windowBorder;
        drawRect(checkBox, borderColor, 1);

        // Draw checkmark if checked
        if (checked) {
            // Simple checkmark: two lines forming a check
            fillRect(Rect(checkBox.x + 3, checkBox.y + 6, 2, 3), _theme.success);
            fillRect(Rect(checkBox.x + 5, checkBox.y + 4, 4, 2), _theme.success);
        }

        // Draw label
        if (label.length > 0) {
            int labelX = bounds.x + 16;
            int labelY = bounds.y + (bounds.height - 16) / 2;
            drawText(label, Point(labelX, labelY), _theme.textPrimary);
        }
    }

    /**
     * Draw a numeric input field (E.5.3: Form widget rendering).
     *
     * Params:
     *   bounds = Input field bounds
     *   value = Current numeric value as string
     *   hasFocus = Whether field has focus
     */
    void drawNumericInput(Rect bounds, string value, bool hasFocus = false) {
        // Draw main input field
        Rect inputRect = Rect(bounds.x, bounds.y, bounds.width - 24, bounds.height);
        drawTextInput(inputRect, value, hasFocus);

        // Draw up/down buttons on the right (simplified as +/-)
        Rect upButton = Rect(bounds.x + bounds.width - 24, bounds.y, 12, bounds.height / 2);
        Rect downButton = Rect(bounds.x + bounds.width - 12, bounds.y + bounds.height / 2, 12, bounds.height / 2);

        // Draw up button
        fillRect(upButton, _theme.buttonBg);
        drawRect(upButton, _theme.buttonBorder, 1);
        drawText("+", Point(upButton.x + 2, upButton.y), _theme.buttonText);

        // Draw down button
        fillRect(downButton, _theme.buttonBg);
        drawRect(downButton, _theme.buttonBorder, 1);
        drawText("-", Point(downButton.x + 2, downButton.y), _theme.buttonText);
    }

    /**
     * Draw a dropdown/combobox (E.5.3: Form widget rendering).
     *
     * Params:
     *   bounds = Dropdown bounds
     *   selectedText = Currently selected item text
     *   hasFocus = Whether dropdown has focus
     */
    void drawDropdown(Rect bounds, string selectedText, bool hasFocus = false) {
        // Draw background
        fillRect(bounds, _theme.windowBg);

        // Draw border
        uint borderColor = hasFocus ? _theme.focusBorder : _theme.windowBorder;
        drawRect(bounds, borderColor, 1);

        // Draw selected text
        if (selectedText.length > 0) {
            int textX = bounds.x + 4;
            int textY = bounds.y + (bounds.height - 16) / 2;
            drawText(selectedText, Point(textX, textY), _theme.textPrimary);
        }

        // Draw dropdown arrow on the right
        int arrowX = bounds.x + bounds.width - 12;
        int arrowY = bounds.y + (bounds.height - 8) / 2;
        // Simple down arrow using lines
        fillRect(Rect(arrowX, arrowY, 8, 1), _theme.textPrimary);
        fillRect(Rect(arrowX + 2, arrowY + 1, 4, 1), _theme.textPrimary);
        fillRect(Rect(arrowX + 4, arrowY + 2, 1, 1), _theme.textPrimary);
    }

    /**
     * Draw a form label+input pair with alignment (E.5.3: Form widget rendering).
     *
     * Params:
     *   bounds = Total bounds for label and input
     *   labelText = Label text
     *   inputText = Input text
     *   labelWidth = Width reserved for label
     */
    void drawFormField(Rect bounds, string labelText, string inputText, int labelWidth = 150) {
        // Draw label
        if (labelText.length > 0) {
            int labelX = bounds.x;
            int labelY = bounds.y + (bounds.height - 16) / 2;
            drawText(labelText, Point(labelX, labelY), _theme.textPrimary);
        }

        // Draw input field
        Rect inputBounds = Rect(bounds.x + labelWidth, bounds.y,
                               bounds.width - labelWidth, bounds.height);
        drawTextInput(inputBounds, inputText);
    }

private:
    bool createShaderProgram() {
        const char* vertexSource = q{
            #version 330 core
            layout(location = 0) in vec2 position;
            layout(location = 1) in vec2 texCoord;

            uniform mat4 projection;

            out vec2 TexCoord;

            void main() {
                gl_Position = projection * vec4(position, 0.0, 1.0);
                TexCoord = texCoord;
            }
        };

        const char* fragmentSource = q{
            #version 330 core
            in vec2 TexCoord;
            uniform vec4 color;
            uniform sampler2D fontTexture;
            uniform bool useTexture = false;

            out vec4 FragColor;

            void main() {
                if (useTexture) {
                    // Sample glyph from font atlas (red channel only)
                    float alpha = texture(fontTexture, TexCoord).r;
                    FragColor = vec4(color.rgb, color.a * alpha);
                } else {
                    // Solid color quad
                    FragColor = color;
                }
            }
        };

        GLuint vertex = glCreateShader(GL_VERTEX_SHADER);
        glShaderSource(vertex, 1, &vertexSource, null);
        glCompileShader(vertex);

        // Check compilation
        int success;
        char[512] infoLog;
        glGetShaderiv(vertex, GL_COMPILE_STATUS, &success);
        if (!success) {
            glGetShaderInfoLog(vertex, infoLog.length, null, infoLog.ptr);
            stderr.writefln("Vertex shader compilation failed: %s", infoLog[0..512]);
            return false;
        }

        GLuint fragment = glCreateShader(GL_FRAGMENT_SHADER);
        glShaderSource(fragment, 1, &fragmentSource, null);
        glCompileShader(fragment);

        glGetShaderiv(fragment, GL_COMPILE_STATUS, &success);
        if (!success) {
            glGetShaderInfoLog(fragment, infoLog.length, null, infoLog.ptr);
            stderr.writefln("Fragment shader compilation failed: %s", infoLog[0..512]);
            return false;
        }

        _shaderProgram = glCreateProgram();
        glAttachShader(_shaderProgram, vertex);
        glAttachShader(_shaderProgram, fragment);
        glLinkProgram(_shaderProgram);

        glGetProgramiv(_shaderProgram, GL_LINK_STATUS, &success);
        if (!success) {
            glGetProgramInfoLog(_shaderProgram, infoLog.length, null, infoLog.ptr);
            stderr.writefln("Shader program linking failed: %s", infoLog[0..512]);
            return false;
        }

        glDeleteShader(vertex);
        glDeleteShader(fragment);

        _projectionLoc = glGetUniformLocation(_shaderProgram, "projection");
        _colorLoc = glGetUniformLocation(_shaderProgram, "color");
        _fontTextureLoc = glGetUniformLocation(_shaderProgram, "fontTexture");
        _positionLoc = glGetAttribLocation(_shaderProgram, "position");
        _texCoordLoc = glGetAttribLocation(_shaderProgram, "texCoord");

        return true;
    }

    bool createGeometryBuffers() {
        glGenVertexArrays(1, &_vao);
        glGenBuffers(1, &_vbo);

        glBindVertexArray(_vao);
        glBindBuffer(GL_ARRAY_BUFFER, _vbo);

        // Allocate space for quad vertices with position + texCoord
        enum size_t MaxQuads = 1000;
        size_t bufferSize = MaxQuads * 6 * 4 * float.sizeof;  // 6 vertices per quad, 4 floats per vertex (x, y, u, v)
        glBufferData(GL_ARRAY_BUFFER, bufferSize, null, GL_DYNAMIC_DRAW);

        // Position attribute (location 0, first 2 floats)
        glVertexAttribPointer(_positionLoc, 2, GL_FLOAT, GL_FALSE, 4 * float.sizeof, null);
        glEnableVertexAttribArray(_positionLoc);

        // TexCoord attribute (location 1, next 2 floats)
        glVertexAttribPointer(_texCoordLoc, 2, GL_FLOAT, GL_FALSE, 4 * float.sizeof, cast(void*)(2 * float.sizeof));
        glEnableVertexAttribArray(_texCoordLoc);

        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glBindVertexArray(0);

        return true;
    }

    void drawQuad(Rect rect, float r, float g, float b, float a) {
        if (_shaderProgram == 0 || _vao == 0) return;

        // Draw solid quad (no texture)
        drawQuadWithTexture(rect, r, g, b, a, 0, 0, 1, 1, false);
    }

    /**
     * Draw a glyph quad from the font atlas.
     * Params:
     *   rect = Target rectangle on screen
     *   glyphInfo = Glyph metrics and UV coordinates from FontAtlas
     *   r, g, b, a = Text color
     */
    private void drawGlyph(Rect rect, const GlyphInfo glyphInfo, float r, float g, float b, float a) {
        if (_shaderProgram == 0 || _vao == 0) return;
        if (!glyphInfo.valid) return;

        drawQuadWithTexture(rect, r, g, b, a, glyphInfo.u0, glyphInfo.v0, glyphInfo.u1, glyphInfo.v1, true);
    }

    /**
     * Internal: Draw a quad with optional texture coordinates.
     */
    private void drawQuadWithTexture(Rect rect, float r, float g, float b, float a,
                                      float u0, float v0, float u1, float v1, bool useTexture) {
        if (_shaderProgram == 0 || _vao == 0) return;

        // Normalize coordinates to NDC
        float x0 = (rect.x / cast(float)_viewportWidth) * 2.0f - 1.0f;
        float y0 = (rect.y / cast(float)_viewportHeight) * 2.0f - 1.0f;
        float x1 = ((rect.x + rect.width) / cast(float)_viewportWidth) * 2.0f - 1.0f;
        float y1 = ((rect.y + rect.height) / cast(float)_viewportHeight) * 2.0f - 1.0f;

        // Flip Y for OpenGL
        y0 = -y0;
        y1 = -y1;

        float[24] vertices = [
            // Position + TexCoord
            x0, y1, u0, v1,  // Bottom-left
            x1, y1, u1, v1,  // Bottom-right
            x0, y0, u0, v0,  // Top-left
            x1, y1, u1, v1,  // Bottom-right
            x1, y0, u1, v0,  // Top-right
            x0, y0, u0, v0,  // Top-left
        ];

        glBindBuffer(GL_ARRAY_BUFFER, _vbo);
        glBufferSubData(GL_ARRAY_BUFFER, 0, vertices.sizeof, vertices.ptr);

        glUseProgram(_shaderProgram);
        glUniform4f(_colorLoc, r, g, b, a);

        // Bind font texture and set uniform
        if (useTexture && _fontAtlas !is null) {
            _fontAtlas.bind(0);
            glUniform1i(_fontTextureLoc, 0);
            GLint useTextureLoc = glGetUniformLocation(_shaderProgram, "useTexture");
            glUniform1i(useTextureLoc, 1);
        } else {
            GLint useTextureLoc = glGetUniformLocation(_shaderProgram, "useTexture");
            glUniform1i(useTextureLoc, 0);
        }

        // Set orthogonal projection
        float[16] projection = [
            2.0f / _viewportWidth, 0, 0, 0,
            0, 2.0f / _viewportHeight, 0, 0,
            0, 0, -1, 0,
            -1, -1, 0, 1,
        ];
        glUniformMatrix4fv(_projectionLoc, 1, GL_TRUE, projection.ptr);

        glBindVertexArray(_vao);
        glDrawArrays(GL_TRIANGLES, 0, 6);
        glBindVertexArray(0);
    }

    Rect applyClipping(Rect rect) {
        if (_clipStack.length == 0) {
            return rect;
        }
        return rect.intersection(_clipStack[$ - 1]);
    }
}
