/**
 * Common UI Controls
 *
 * Basic widget controls: Label, Button, TextInput, Checkbox.
 * Building blocks for dialogs and configuration screens.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.controls;

version (PURE_D_BACKEND):

import pured.widget.base;
import pured.widget.events;
import pured.util.signal;
import std.algorithm : min, max;

// ============================================================================
// Label Widget
// ============================================================================

/**
 * Static text display widget.
 *
 * Displays a single line of non-editable text with configurable alignment.
 */
class Label : Widget {
private:
    string _text;
    uint _textColor = 0xFFFFFFFF;  // White
    int _fontSize = 14;  // Logical font size (for measurement estimation)

public:
    /// Text content
    @property string text() const { return _text; }
    @property void text(string value) {
        if (_text != value) {
            _text = value;
            invalidateMeasure();
        }
    }

    /// Text color (ARGB format)
    @property uint textColor() const { return _textColor; }
    @property void textColor(uint value) {
        if (_textColor != value) {
            _textColor = value;
            invalidateVisual();
        }
    }

    /// Font size for measurement estimation
    @property int fontSize() const { return _fontSize; }
    @property void fontSize(int value) {
        if (_fontSize != value) {
            _fontSize = value;
            invalidateMeasure();
        }
    }

    /// Create label with text
    this(string text = "") {
        _text = text;
    }

protected:
    override Size measureOverride(Size availableSize) {
        if (_text.length == 0)
            return Size.zero;

        // Estimate text size based on character count and font size
        // Actual measurement will be done by renderer at render time
        // Using ~0.6 width ratio for typical proportional font
        int estimatedWidth = cast(int)(_text.length * _fontSize * 0.6);
        int estimatedHeight = _fontSize + 4;  // Font height + padding

        return Size(
            min(estimatedWidth, availableSize.width),
            estimatedHeight
        );
    }

    override void renderOverride(RenderContext renderer) {
        if (_text.length == 0)
            return;

        // Calculate text position based on alignment
        Point textPos = Point(_bounds.x, _bounds.y);

        // Vertical centering within bounds
        int textHeight = _fontSize;
        int verticalPad = (_bounds.height - textHeight) / 2;
        textPos.y += max(0, verticalPad);

        // Horizontal alignment
        final switch (_horizontalAlign) {
            case HorizontalAlignment.left:
            case HorizontalAlignment.stretch:
                textPos.x += _padding.left;
                break;
            case HorizontalAlignment.center:
                int estWidth = cast(int)(_text.length * _fontSize * 0.6);
                textPos.x += (_bounds.width - estWidth) / 2;
                break;
            case HorizontalAlignment.right:
                int estWidth = cast(int)(_text.length * _fontSize * 0.6);
                textPos.x += _bounds.width - estWidth - _padding.right;
                break;
        }

        renderer.drawText(_text, textPos, _textColor);
    }
}

// ============================================================================
// Button Widget
// ============================================================================

/**
 * Clickable button control.
 *
 * Displays text with hover/pressed visual states.
 * Emits onClick signal when activated.
 */
class Button : Widget {
    mixin EventHandlers;

private:
    string _label;
    uint _backgroundColor = 0xFF404040;  // Default gray
    uint _hoverColor = 0xFF505050;       // Lighter gray on hover
    uint _pressedColor = 0xFF303030;     // Darker gray when pressed
    uint _textColor = 0xFFFFFFFF;        // White text
    uint _borderColor = 0xFF606060;      // Border color
    int _borderWidth = 1;
    int _fontSize = 14;

    bool _isHovered = false;
    bool _isPressed = false;

public:
    /// Clicked signal - emitted when button is activated
    Signal!() onClick;

    /// Button label text
    @property string label() const { return _label; }
    @property void label(string value) {
        if (_label != value) {
            _label = value;
            invalidateMeasure();
        }
    }

    /// Background color
    @property uint backgroundColor() const { return _backgroundColor; }
    @property void backgroundColor(uint value) {
        _backgroundColor = value;
        invalidateVisual();
    }

    /// Hover color
    @property uint hoverColor() const { return _hoverColor; }
    @property void hoverColor(uint value) { _hoverColor = value; }

    /// Pressed color
    @property uint pressedColor() const { return _pressedColor; }
    @property void pressedColor(uint value) { _pressedColor = value; }

    /// Text color
    @property uint textColor() const { return _textColor; }
    @property void textColor(uint value) {
        _textColor = value;
        invalidateVisual();
    }

    /// Whether button is currently hovered
    @property bool isHovered() const { return _isHovered; }

    /// Whether button is currently pressed
    @property bool isPressed() const { return _isPressed; }

    /// Create button with label
    this(string label = "") {
        _label = label;
        _padding = Thickness.symmetric(12, 6);  // Horizontal=12, Vertical=6
    }

    /// Handle mouse events for button behavior
    bool handleMouseEvent(MouseEvent event) {
        if (!_enabled) return false;

        final switch (event.eventType) {
            case MouseEventType.enter:
                _isHovered = true;
                invalidateVisual();
                return true;

            case MouseEventType.leave:
                _isHovered = false;
                _isPressed = false;
                invalidateVisual();
                return true;

            case MouseEventType.buttonDown:
                if (event.button == MouseButton.left) {
                    _isPressed = true;
                    invalidateVisual();
                    return true;
                }
                break;

            case MouseEventType.buttonUp:
                if (event.button == MouseButton.left && _isPressed) {
                    _isPressed = false;
                    invalidateVisual();
                    // Emit click if still within bounds
                    if (_bounds.contains(event.position)) {
                        onClick.emit();
                    }
                    return true;
                }
                break;

            case MouseEventType.move:
            case MouseEventType.wheel:
                break;
        }

        return false;
    }

    /// Handle keyboard activation (Enter/Space)
    bool handleKeyEvent(KeyEvent event) {
        if (!_enabled || !_focused) return false;

        if (event.isPressed) {
            if (event.keyCode == KeyCode.enter || event.keyCode == KeyCode.space) {
                // Visual feedback
                _isPressed = true;
                invalidateVisual();
                return true;
            }
        } else if (event.isReleased) {
            if (event.keyCode == KeyCode.enter || event.keyCode == KeyCode.space) {
                _isPressed = false;
                invalidateVisual();
                onClick.emit();
                return true;
            }
        }

        return false;
    }

    override bool canFocus() const {
        return _enabled && _visibility == Visibility.visible;
    }

protected:
    override Size measureOverride(Size availableSize) {
        // Estimate text size
        int textWidth = cast(int)(_label.length * _fontSize * 0.6);
        int textHeight = _fontSize;

        // Add padding
        return Size(
            textWidth + _padding.horizontalTotal,
            textHeight + _padding.verticalTotal
        );
    }

    override void renderOverride(RenderContext renderer) {
        // Determine current background color based on state
        uint bgColor = _backgroundColor;
        if (!_enabled) {
            bgColor = 0xFF303030;  // Disabled gray
        } else if (_isPressed) {
            bgColor = _pressedColor;
        } else if (_isHovered) {
            bgColor = _hoverColor;
        }

        // Draw background
        renderer.fillRect(_bounds, bgColor);

        // Draw border
        if (_borderWidth > 0) {
            renderer.drawRect(_bounds, _borderColor, _borderWidth);
        }

        // Draw focus indicator
        if (_focused) {
            auto focusRect = _bounds.shrink(2);
            renderer.drawRect(focusRect, 0xFF6699FF, 1);  // Blue focus ring
        }

        // Draw label text centered
        if (_label.length > 0) {
            int textWidth = cast(int)(_label.length * _fontSize * 0.6);
            int textHeight = _fontSize;

            Point textPos = Point(
                _bounds.x + (_bounds.width - textWidth) / 2,
                _bounds.y + (_bounds.height - textHeight) / 2
            );

            uint actualTextColor = _enabled ? _textColor : 0xFF808080;
            renderer.drawText(_label, textPos, actualTextColor);
        }
    }

    override void onGotFocus() {
        super.onGotFocus();
        invalidateVisual();
    }

    override void onLostFocus() {
        super.onLostFocus();
        _isPressed = false;
        invalidateVisual();
    }
}

// ============================================================================
// TextInput Widget
// ============================================================================

/**
 * Single-line text input control.
 *
 * Allows text entry with cursor and selection support.
 */
class TextInput : Widget {
    mixin EventHandlers;

private:
    string _text;
    string _placeholder;
    int _cursorPos = 0;
    int _selectionStart = -1;  // -1 means no selection
    int _selectionEnd = -1;
    bool _cursorVisible = true;
    uint _backgroundColor = 0xFF1A1A1A;  // Dark background
    uint _textColor = 0xFFFFFFFF;
    uint _placeholderColor = 0xFF808080;
    uint _borderColor = 0xFF404040;
    uint _focusBorderColor = 0xFF6699FF;
    int _fontSize = 14;
    int _scrollOffset = 0;  // Horizontal scroll for long text

public:
    /// Text changed signal
    Signal!string onTextChanged;

    /// Text submitted signal (Enter pressed)
    Signal!string onSubmit;

    /// Text content
    @property string text() const { return _text; }
    @property void text(string value) {
        if (_text != value) {
            _text = value;
            _cursorPos = min(_cursorPos, cast(int)_text.length);
            clearSelection();
            onTextChanged.emit(_text);
            invalidateVisual();
        }
    }

    /// Placeholder text (shown when empty)
    @property string placeholder() const { return _placeholder; }
    @property void placeholder(string value) {
        _placeholder = value;
        if (_text.length == 0) invalidateVisual();
    }

    /// Cursor position
    @property int cursorPosition() const { return _cursorPos; }
    @property void cursorPosition(int value) {
        _cursorPos = max(0, min(value, cast(int)_text.length));
        invalidateVisual();
    }

    /// Create text input
    this(string text = "", string placeholder = "") {
        _text = text;
        _placeholder = placeholder;
        _cursorPos = cast(int)text.length;
        _padding = Thickness.symmetric(8, 4);
    }

    /// Insert text at cursor
    void insertText(string text) {
        deleteSelection();

        if (_cursorPos >= _text.length) {
            _text ~= text;
        } else {
            _text = _text[0 .. _cursorPos] ~ text ~ _text[_cursorPos .. $];
        }
        _cursorPos += cast(int)text.length;
        onTextChanged.emit(_text);
        invalidateVisual();
    }

    /// Delete character before cursor
    void deleteBack() {
        if (hasSelection()) {
            deleteSelection();
            return;
        }

        if (_cursorPos > 0 && _text.length > 0) {
            _text = _text[0 .. _cursorPos - 1] ~ _text[_cursorPos .. $];
            _cursorPos--;
            onTextChanged.emit(_text);
            invalidateVisual();
        }
    }

    /// Delete character at cursor
    void deleteForward() {
        if (hasSelection()) {
            deleteSelection();
            return;
        }

        if (_cursorPos < _text.length) {
            _text = _text[0 .. _cursorPos] ~ _text[_cursorPos + 1 .. $];
            onTextChanged.emit(_text);
            invalidateVisual();
        }
    }

    /// Move cursor left
    void moveCursorLeft(bool extendSelection = false) {
        if (!extendSelection) clearSelection();
        if (_cursorPos > 0) {
            _cursorPos--;
            if (extendSelection) updateSelection();
            invalidateVisual();
        }
    }

    /// Move cursor right
    void moveCursorRight(bool extendSelection = false) {
        if (!extendSelection) clearSelection();
        if (_cursorPos < _text.length) {
            _cursorPos++;
            if (extendSelection) updateSelection();
            invalidateVisual();
        }
    }

    /// Move cursor to start
    void moveCursorHome(bool extendSelection = false) {
        if (!extendSelection) clearSelection();
        _cursorPos = 0;
        if (extendSelection) updateSelection();
        invalidateVisual();
    }

    /// Move cursor to end
    void moveCursorEnd(bool extendSelection = false) {
        if (!extendSelection) clearSelection();
        _cursorPos = cast(int)_text.length;
        if (extendSelection) updateSelection();
        invalidateVisual();
    }

    /// Select all text
    void selectAll() {
        _selectionStart = 0;
        _selectionEnd = cast(int)_text.length;
        _cursorPos = cast(int)_text.length;
        invalidateVisual();
    }

    /// Check if there is a selection
    bool hasSelection() const {
        return _selectionStart >= 0 && _selectionEnd >= 0 &&
               _selectionStart != _selectionEnd;
    }

    /// Get selected text
    string selectedText() const {
        if (!hasSelection()) return "";
        int start = min(_selectionStart, _selectionEnd);
        int end = max(_selectionStart, _selectionEnd);
        return _text[start .. end];
    }

    /// Handle character input
    bool handleCharEvent(CharEvent event) {
        if (!_enabled || !_focused) return false;

        // Ignore control characters
        if (event.codepoint < 32 && event.codepoint != '\t')
            return false;

        insertText(event.character);
        return true;
    }

    /// Handle key events
    bool handleKeyEvent(KeyEvent event) {
        if (!_enabled || !_focused) return false;
        if (!event.isPressed && !event.isRepeat) return false;

        bool shift = event.shift;
        bool ctrl = event.ctrl;

        switch (event.keyCode) {
            case KeyCode.backspace:
                deleteBack();
                return true;

            case KeyCode.delete_:
                deleteForward();
                return true;

            case KeyCode.left:
                moveCursorLeft(shift);
                return true;

            case KeyCode.right:
                moveCursorRight(shift);
                return true;

            case KeyCode.home:
                moveCursorHome(shift);
                return true;

            case KeyCode.end:
                moveCursorEnd(shift);
                return true;

            case KeyCode.a:
                if (ctrl) {
                    selectAll();
                    return true;
                }
                break;

            case KeyCode.enter:
                onSubmit.emit(_text);
                return true;

            case KeyCode.escape:
                // Clear focus
                return false;

            default:
                break;
        }

        return false;
    }

    override bool canFocus() const {
        return _enabled && _visibility == Visibility.visible;
    }

protected:
    override Size measureOverride(Size availableSize) {
        // Fixed height based on font size, width can stretch
        int height = _fontSize + _padding.verticalTotal + 4;
        return Size(
            min(200, availableSize.width),  // Default min width
            height
        );
    }

    override void renderOverride(RenderContext renderer) {
        // Draw background
        renderer.fillRect(_bounds, _backgroundColor);

        // Draw border
        uint borderColor = _focused ? _focusBorderColor : _borderColor;
        renderer.drawRect(_bounds, borderColor, 1);

        // Content area
        Rect contentArea = Rect(
            _bounds.x + _padding.left,
            _bounds.y + _padding.top,
            _bounds.width - _padding.horizontalTotal,
            _bounds.height - _padding.verticalTotal
        );

        renderer.pushClip(contentArea);
        scope(exit) renderer.popClip();

        // Draw selection background
        if (hasSelection()) {
            int start = min(_selectionStart, _selectionEnd);
            int end = max(_selectionStart, _selectionEnd);
            int selX = contentArea.x + cast(int)(start * _fontSize * 0.6);
            int selWidth = cast(int)((end - start) * _fontSize * 0.6);
            renderer.fillRect(Rect(selX, contentArea.y, selWidth, contentArea.height), 0xFF4466AA);
        }

        // Draw text or placeholder
        Point textPos = Point(contentArea.x, contentArea.y);
        if (_text.length > 0) {
            renderer.drawText(_text, textPos, _textColor);
        } else if (_placeholder.length > 0 && !_focused) {
            renderer.drawText(_placeholder, textPos, _placeholderColor);
        }

        // Draw cursor
        if (_focused && _cursorVisible) {
            int cursorX = contentArea.x + cast(int)(_cursorPos * _fontSize * 0.6);
            renderer.fillRect(Rect(cursorX, contentArea.y, 2, contentArea.height), _textColor);
        }
    }

    override void onGotFocus() {
        super.onGotFocus();
        _cursorVisible = true;
        invalidateVisual();
    }

    override void onLostFocus() {
        super.onLostFocus();
        clearSelection();
        invalidateVisual();
    }

private:
    void clearSelection() {
        _selectionStart = -1;
        _selectionEnd = -1;
    }

    void updateSelection() {
        if (_selectionStart < 0) {
            _selectionStart = _cursorPos;
        }
        _selectionEnd = _cursorPos;
    }

    void deleteSelection() {
        if (!hasSelection()) return;

        int start = min(_selectionStart, _selectionEnd);
        int end = max(_selectionStart, _selectionEnd);

        _text = _text[0 .. start] ~ _text[end .. $];
        _cursorPos = start;
        clearSelection();
        onTextChanged.emit(_text);
        invalidateVisual();
    }
}

// ============================================================================
// Checkbox Widget
// ============================================================================

/**
 * Boolean toggle control with label.
 */
class Checkbox : Widget {
    mixin EventHandlers;

private:
    string _label;
    bool _checked = false;
    bool _isHovered = false;
    uint _checkColor = 0xFF6699FF;  // Blue check
    uint _boxColor = 0xFF404040;
    uint _textColor = 0xFFFFFFFF;
    int _boxSize = 16;
    int _fontSize = 14;

public:
    /// Checked changed signal
    Signal!bool onCheckedChanged;

    /// Checked state
    @property bool checked() const { return _checked; }
    @property void checked(bool value) {
        if (_checked != value) {
            _checked = value;
            onCheckedChanged.emit(_checked);
            invalidateVisual();
        }
    }

    /// Label text
    @property string label() const { return _label; }
    @property void label(string value) {
        _label = value;
        invalidateMeasure();
    }

    /// Create checkbox with label
    this(string label = "", bool checked = false) {
        _label = label;
        _checked = checked;
    }

    /// Toggle checked state
    void toggle() {
        checked = !_checked;
    }

    /// Handle mouse events
    bool handleMouseEvent(MouseEvent event) {
        if (!_enabled) return false;

        switch (event.eventType) {
            case MouseEventType.enter:
                _isHovered = true;
                invalidateVisual();
                return true;

            case MouseEventType.leave:
                _isHovered = false;
                invalidateVisual();
                return true;

            case MouseEventType.buttonUp:
                if (event.button == MouseButton.left) {
                    toggle();
                    return true;
                }
                break;

            default:
                break;
        }

        return false;
    }

    /// Handle keyboard events
    bool handleKeyEvent(KeyEvent event) {
        if (!_enabled || !_focused) return false;

        if (event.isPressed && event.keyCode == KeyCode.space) {
            toggle();
            return true;
        }

        return false;
    }

    override bool canFocus() const {
        return _enabled && _visibility == Visibility.visible;
    }

protected:
    override Size measureOverride(Size availableSize) {
        int labelWidth = cast(int)(_label.length * _fontSize * 0.6);
        int width = _boxSize + 8 + labelWidth;  // Box + spacing + label
        int height = max(_boxSize, _fontSize);

        return Size(width, height);
    }

    override void renderOverride(RenderContext renderer) {
        // Calculate box position (vertically centered)
        int boxY = _bounds.y + (_bounds.height - _boxSize) / 2;
        Rect boxRect = Rect(_bounds.x, boxY, _boxSize, _boxSize);

        // Draw checkbox box
        uint boxBg = _isHovered ? 0xFF505050 : _boxColor;
        renderer.fillRect(boxRect, boxBg);
        renderer.drawRect(boxRect, 0xFF606060, 1);

        // Draw checkmark if checked
        if (_checked) {
            Rect checkRect = boxRect.shrink(3);
            renderer.fillRect(checkRect, _checkColor);
        }

        // Draw focus ring
        if (_focused) {
            renderer.drawRect(boxRect.expand(2), 0xFF6699FF, 1);
        }

        // Draw label
        if (_label.length > 0) {
            Point labelPos = Point(
                _bounds.x + _boxSize + 8,
                _bounds.y + (_bounds.height - _fontSize) / 2
            );
            renderer.drawText(_label, labelPos, _textColor);
        }
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

unittest {
    // Test Label creation
    auto label = new Label("Hello");
    assert(label.text == "Hello");
}

unittest {
    // Test Button creation and click signal
    auto btn = new Button("Click Me");
    assert(btn.label == "Click Me");

    bool clicked = false;
    btn.onClick.connect(() { clicked = true; });
    btn.onClick.emit();
    assert(clicked);
}

unittest {
    // Test TextInput operations
    auto input = new TextInput("Hello");
    assert(input.text == "Hello");
    assert(input.cursorPosition == 5);

    input.insertText(" World");
    assert(input.text == "Hello World");
    assert(input.cursorPosition == 11);

    input.deleteBack();
    assert(input.text == "Hello Worl");
}

unittest {
    // Test Checkbox toggle
    auto cb = new Checkbox("Option", false);
    assert(!cb.checked);

    cb.toggle();
    assert(cb.checked);

    cb.toggle();
    assert(!cb.checked);
}
