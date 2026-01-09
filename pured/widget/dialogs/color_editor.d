/**
 * Color Scheme Editor
 *
 * Dialog for editing terminal color palettes with live preview.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.dialogs.color_editor;

version (PURE_D_BACKEND):

import pured.widget.base;
import pured.widget.container;
import pured.widget.controls;
import pured.widget.dialog;
import pured.widget.events;
import pured.util.signal;
import pured.config : ThemeConfig, ResolvedTheme;
import std.algorithm : min, max;
import std.format : format;

// ============================================================================
// Color Swatch Widget
// ============================================================================

/**
 * A clickable color swatch that displays a single color.
 */
class ColorSwatch : Widget {
    mixin EventHandlers;

private:
    float[4] _color = [0.5f, 0.5f, 0.5f, 1.0f];
    bool _selected = false;
    bool _hovered = false;
    int _index = -1;  // Palette index (-1 = special color)
    string _label;

public:
    /// Click signal
    Signal!() onClick;

    /// Color changed signal
    Signal!(float[4]) onColorChanged;

    /// Color value (RGBA 0-1)
    @property float[4] color() const { return _color; }
    @property void color(float[4] value) {
        _color = value;
        invalidateVisual();
    }

    /// Whether swatch is selected
    @property bool selected() const { return _selected; }
    @property void selected(bool value) {
        _selected = value;
        invalidateVisual();
    }

    /// Palette index
    @property int index() const { return _index; }

    /// Label text
    @property string label() const { return _label; }

    /// Create swatch
    this(int index = -1, string label = "") {
        _index = index;
        _label = label;
    }

    /// Set color from RGB hex
    void setFromHex(uint rgb) {
        _color[0] = ((rgb >> 16) & 0xFF) / 255.0f;
        _color[1] = ((rgb >> 8) & 0xFF) / 255.0f;
        _color[2] = (rgb & 0xFF) / 255.0f;
        _color[3] = 1.0f;
        invalidateVisual();
    }

    /// Get color as RGB hex
    uint toHex() const {
        uint r = cast(uint)(min(1.0f, max(0.0f, _color[0])) * 255);
        uint g = cast(uint)(min(1.0f, max(0.0f, _color[1])) * 255);
        uint b = cast(uint)(min(1.0f, max(0.0f, _color[2])) * 255);
        return (r << 16) | (g << 8) | b;
    }

    /// Get color as ARGB for rendering
    uint toARGB() const {
        uint a = cast(uint)(min(1.0f, max(0.0f, _color[3])) * 255);
        return (a << 24) | toHex();
    }

protected:
    override Size measureOverride(Size availableSize) {
        return Size(32, 32);  // Fixed size swatch
    }

    override void arrangeOverride(Size finalSize) {
        // No children
    }

    override void renderOverride(RenderContext renderer) {
        // Draw color fill
        renderer.fillRect(_bounds, toARGB());

        // Draw border
        uint borderColor = _selected ? 0xFFFFFFFF : (_hovered ? 0xFFAAAAAA : 0xFF606060);
        renderer.drawRect(_bounds, borderColor, _selected ? 2 : 1);

        // Draw label if present
        if (_label.length > 0) {
            Point labelPos = Point(_bounds.x + 2, _bounds.y + _bounds.height + 2);
            renderer.drawText(_label, labelPos, 0xFFCCCCCC);
        }
    }

    override Widget hitTestOverride(Point localPoint) {
        return _bounds.contains(localPoint) ? this : null;
    }

    bool handleMouseMove(MouseEvent event) {
        bool wasHovered = _hovered;
        _hovered = _bounds.contains(event.position);
        if (wasHovered != _hovered) {
            invalidateVisual();
        }
        return _hovered;
    }

    bool handleMouseLeave() {
        if (_hovered) {
            _hovered = false;
            invalidateVisual();
        }
        return true;
    }

    bool handleMouseClick(MouseEvent event) {
        if (event.eventType == MouseEventType.buttonDown && event.button == MouseButton.left) {
            onClick.emit();
            return true;
        }
        return false;
    }
}

// ============================================================================
// Color Editor Dialog
// ============================================================================

/**
 * Dialog for editing terminal color scheme.
 *
 * Displays:
 * - 16-color ANSI palette grid
 * - Foreground/background color pickers
 * - Hex input fields
 * - Live preview
 */
class ColorEditorDialog : Dialog {
private:
    ColorSwatch[16] _paletteSwatch;
    ColorSwatch _fgSwatch;
    ColorSwatch _bgSwatch;
    TextInput _hexInput;
    ColorSwatch _selectedSwatch;
    Container _previewArea;

    // Current theme being edited
    ResolvedTheme _theme;

    // ANSI color names
    static immutable string[] colorNames = [
        "Black", "Red", "Green", "Yellow",
        "Blue", "Magenta", "Cyan", "White",
        "Bright Black", "Bright Red", "Bright Green", "Bright Yellow",
        "Bright Blue", "Bright Magenta", "Bright Cyan", "Bright White"
    ];

public:
    /// Theme changed signal
    Signal!ResolvedTheme onThemeChanged;

    /// Create color editor
    this(ResolvedTheme theme) {
        super("Color Scheme Editor");
        _theme = theme;

        setupColorEditorContent();
    }

    /// Get current theme
    @property ResolvedTheme theme() { return _theme; }

protected:
    void setupColorEditorContent() {
        auto mainPanel = new StackPanel();
        mainPanel.orientation = Orientation.vertical;
        mainPanel.spacing = 16;
        mainPanel.padding = Thickness.uniform(8);

        // Foreground/Background section
        mainPanel.addChild(new Label("Base Colors:"));
        auto baseRow = new StackPanel();
        baseRow.orientation = Orientation.horizontal;
        baseRow.spacing = 16;

        _fgSwatch = new ColorSwatch(-1, "Foreground");
        _fgSwatch.color = _theme.foreground;
        _fgSwatch.onClick.connect(() { selectSwatch(_fgSwatch); });
        baseRow.addChild(_fgSwatch);

        _bgSwatch = new ColorSwatch(-2, "Background");
        _bgSwatch.color = _theme.background;
        _bgSwatch.onClick.connect(() { selectSwatch(_bgSwatch); });
        baseRow.addChild(_bgSwatch);

        mainPanel.addChild(baseRow);

        // Palette section
        mainPanel.addChild(new Label("ANSI Palette:"));

        // First 8 colors (normal)
        auto row1 = new StackPanel();
        row1.orientation = Orientation.horizontal;
        row1.spacing = 4;
        foreach (i; 0 .. 8) {
            _paletteSwatch[i] = new ColorSwatch(i, colorNames[i][0..1]);
            _paletteSwatch[i].color = _theme.palette[i];
            auto idx = i;
            _paletteSwatch[i].onClick.connect(() { selectSwatch(_paletteSwatch[idx]); });
            row1.addChild(_paletteSwatch[i]);
        }
        mainPanel.addChild(row1);

        // Next 8 colors (bright)
        auto row2 = new StackPanel();
        row2.orientation = Orientation.horizontal;
        row2.spacing = 4;
        foreach (i; 8 .. 16) {
            _paletteSwatch[i] = new ColorSwatch(i, colorNames[i][0..2]);
            _paletteSwatch[i].color = _theme.palette[i];
            auto idx = i;
            _paletteSwatch[i].onClick.connect(() { selectSwatch(_paletteSwatch[idx]); });
            row2.addChild(_paletteSwatch[i]);
        }
        mainPanel.addChild(row2);

        // Hex input section
        mainPanel.addChild(new Label("Hex Color:"));
        auto hexRow = new StackPanel();
        hexRow.orientation = Orientation.horizontal;
        hexRow.spacing = 8;
        hexRow.addChild(new Label("#"));
        _hexInput = new TextInput("FFFFFF");
        _hexInput.onSubmit.connect((string text) { applyHexColor(text); });
        hexRow.addChild(_hexInput);
        mainPanel.addChild(hexRow);

        // Preview section (placeholder)
        mainPanel.addChild(new Label("Preview:"));
        _previewArea = new Container();
        _previewArea.padding = Thickness.uniform(4);
        mainPanel.addChild(_previewArea);

        contentArea.addChild(mainPanel);

        // Configure buttons
        setOkButtonText("Apply");
    }

    void selectSwatch(ColorSwatch swatch) {
        // Deselect previous
        if (_selectedSwatch !is null) {
            _selectedSwatch.selected = false;
        }

        // Select new
        _selectedSwatch = swatch;
        if (_selectedSwatch !is null) {
            _selectedSwatch.selected = true;
            // Update hex input
            _hexInput.text = format!"%06X"(_selectedSwatch.toHex());
        }
    }

    void applyHexColor(string hexText) {
        if (_selectedSwatch is null) return;

        // Parse hex color
        try {
            uint rgb = 0;
            foreach (c; hexText) {
                if (c >= '0' && c <= '9')
                    rgb = (rgb << 4) | (c - '0');
                else if (c >= 'a' && c <= 'f')
                    rgb = (rgb << 4) | (c - 'a' + 10);
                else if (c >= 'A' && c <= 'F')
                    rgb = (rgb << 4) | (c - 'A' + 10);
            }

            _selectedSwatch.setFromHex(rgb);

            // Update theme
            int idx = _selectedSwatch.index;
            if (idx >= 0 && idx < 16) {
                _theme.palette[idx] = _selectedSwatch.color;
            } else if (idx == -1) {
                _theme.foreground = _selectedSwatch.color;
            } else if (idx == -2) {
                _theme.background = _selectedSwatch.color;
            }
        } catch (Exception) {
            // Invalid hex - ignore
        }
    }

    override void closeOk() {
        onThemeChanged.emit(_theme);
        super.closeOk();
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

unittest {
    // Test ColorSwatch creation
    auto swatch = new ColorSwatch(0, "Test");
    assert(swatch.index == 0);
    assert(swatch.label == "Test");
}

unittest {
    // Test hex conversion
    auto swatch = new ColorSwatch();
    swatch.setFromHex(0xFF0000);  // Red
    auto c = swatch.color;
    assert(c[0] > 0.99f && c[0] <= 1.0f);  // R
    assert(c[1] < 0.01f);  // G
    assert(c[2] < 0.01f);  // B
}

unittest {
    // Test toHex
    auto swatch = new ColorSwatch();
    float[4] blue = [0.0f, 0.0f, 1.0f, 1.0f];
    swatch.color = blue;
    assert(swatch.toHex() == 0x0000FF);
}
