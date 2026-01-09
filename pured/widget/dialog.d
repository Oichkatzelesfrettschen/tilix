/**
 * Dialog System
 *
 * Modal dialog base class and infrastructure for popup dialogs.
 * Provides focus trapping, keyboard shortcuts, and overlay rendering.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.dialog;

version (PURE_D_BACKEND):

import pured.widget.base;
import pured.widget.container;
import pured.widget.controls;
import pured.widget.events;
import pured.util.signal;
import std.algorithm : min, max;

// ============================================================================
// Dialog Result
// ============================================================================

/**
 * Result of a dialog interaction.
 */
enum DialogResult {
    none,      /// Dialog still open
    ok,        /// User confirmed (OK, Yes, Save)
    cancel,    /// User cancelled (Cancel, No)
    abort,     /// Dialog was closed abnormally
    yes,       /// Affirmative response
    no,        /// Negative response
    retry,     /// User wants to retry
    ignore,    /// User wants to ignore
}

// ============================================================================
// Dialog Base Class
// ============================================================================

/**
 * Modal dialog base class.
 *
 * Dialogs capture focus and display over other content with a dimmed background.
 * They support standard keyboard shortcuts (Escape=Cancel, Enter=OK) and
 * automatic focus trapping within the dialog bounds.
 *
 * To create a dialog:
 * 1. Extend Dialog and set up content in constructor
 * 2. Call showModal() to display
 * 3. Connect to onClosed signal for result handling
 */
class Dialog : Container {
    mixin EventHandlers;

private:
    DialogResult _result = DialogResult.none;
    bool _isModal = false;
    bool _isShowing = false;
    string _title;
    Widget _previousFocus;  // Widget that had focus before dialog opened

    // Dialog appearance
    uint _overlayColor = 0x80000000;      // Semi-transparent black
    uint _backgroundColor = 0xFF2A2A2A;   // Dark gray
    uint _titleBarColor = 0xFF404040;     // Slightly lighter
    uint _borderColor = 0xFF606060;
    uint _titleColor = 0xFFFFFFFF;
    int _titleBarHeight = 28;
    int _borderWidth = 1;
    int _cornerRadius = 4;  // For visual reference (actual rendering may not support)

    // Buttons (managed by dialog)
    Button _okButton;
    Button _cancelButton;
    StackPanel _buttonPanel;
    Container _contentArea;

    // Focus management for tab cycling
    Widget[] _focusableWidgets;
    int _focusIndex = 0;

public:
    /// Dialog closed signal (emits result)
    Signal!DialogResult onClosed;

    /// Dialog title
    @property string title() const { return _title; }
    @property void title(string value) {
        _title = value;
        invalidateVisual();
    }

    /// Dialog result
    @property DialogResult result() const { return _result; }

    /// Whether dialog is currently showing
    @property bool isShowing() const { return _isShowing; }

    /// Whether dialog is modal
    @property bool isModal() const { return _isModal; }

    /// Content area for dialog-specific widgets
    @property Container contentArea() { return _contentArea; }

    /// Create dialog with title
    this(string title = "Dialog") {
        _title = title;

        // Create internal layout
        setupDialogLayout();
    }

    /// Show dialog as modal
    void showModal() {
        _isModal = true;
        _isShowing = true;
        _result = DialogResult.none;

        // Save current focus
        auto root = findRoot();
        if (root !is null) {
            _previousFocus = root.focusedWidget;
        }

        // Build focusable widget list
        buildFocusableList();

        // Focus first focusable widget (or OK button)
        if (_focusableWidgets.length > 0) {
            _focusableWidgets[0].focus();
            _focusIndex = 0;
        } else if (_okButton !is null) {
            _okButton.focus();
        }

        invalidateMeasure();
    }

    /// Close dialog with result
    void close(DialogResult result) {
        _result = result;
        _isShowing = false;
        _isModal = false;

        // Restore previous focus
        if (_previousFocus !is null) {
            _previousFocus.focus();
            _previousFocus = null;
        }

        onClosed.emit(result);
        invalidateVisual();
    }

    /// Close with OK result
    void closeOk() {
        close(DialogResult.ok);
    }

    /// Close with Cancel result
    void closeCancel() {
        close(DialogResult.cancel);
    }

    /// Handle keyboard events for dialog
    bool handleKeyEvent(KeyEvent event) {
        if (!_isShowing) return false;
        if (!event.isPressed) return false;

        switch (event.keyCode) {
            case KeyCode.escape:
                closeCancel();
                return true;

            case KeyCode.enter:
                // Enter activates focused button, or OK if no button focused
                if (_okButton !is null && (_okButton.focused || !anyButtonFocused())) {
                    closeOk();
                    return true;
                }
                break;

            case KeyCode.tab:
                // Focus cycling within dialog
                cycleFocus(event.shift);
                return true;

            default:
                break;
        }

        return false;
    }

    /// Set OK button text
    void setOkButtonText(string text) {
        if (_okButton !is null) {
            _okButton.label = text;
        }
    }

    /// Set Cancel button text
    void setCancelButtonText(string text) {
        if (_cancelButton !is null) {
            _cancelButton.label = text;
        }
    }

    /// Hide Cancel button (for info dialogs)
    void hideCancelButton() {
        if (_cancelButton !is null) {
            _cancelButton.visibility = Visibility.collapsed;
        }
    }

    /// Show Cancel button
    void showCancelButton() {
        if (_cancelButton !is null) {
            _cancelButton.visibility = Visibility.visible;
        }
    }

protected:
    /// Override to add content before showing
    void setupContent() {
        // Override in subclass to add content widgets
    }

    /// Build list of focusable widgets for tab cycling
    void buildFocusableList() {
        _focusableWidgets = [];
        collectFocusable(_contentArea);
        // Add buttons last
        if (_okButton !is null && _okButton.canFocus())
            _focusableWidgets ~= _okButton;
        if (_cancelButton !is null && _cancelButton.canFocus())
            _focusableWidgets ~= _cancelButton;
    }

    /// Collect focusable widgets from a container
    void collectFocusable(Widget widget) {
        if (widget is null) return;

        if (widget.canFocus() && widget !is _okButton && widget !is _cancelButton) {
            _focusableWidgets ~= widget;
        }

        // Recurse into containers
        if (auto container = cast(Container)widget) {
            foreach (child; container) {
                collectFocusable(child);
            }
        }
    }

    /// Cycle focus to next/previous widget
    void cycleFocus(bool reverse) {
        if (_focusableWidgets.length == 0) return;

        if (reverse) {
            _focusIndex = (_focusIndex - 1 + cast(int)_focusableWidgets.length)
                          % cast(int)_focusableWidgets.length;
        } else {
            _focusIndex = (_focusIndex + 1) % cast(int)_focusableWidgets.length;
        }

        _focusableWidgets[_focusIndex].focus();
    }

    /// Check if any button is focused
    bool anyButtonFocused() {
        return (_okButton !is null && _okButton.focused) ||
               (_cancelButton !is null && _cancelButton.focused);
    }

    /// Set up internal dialog layout
    void setupDialogLayout() {
        // Content area
        _contentArea = new Container();
        _contentArea.padding = Thickness.uniform(12);

        // Button panel (horizontal stack at bottom)
        _buttonPanel = new StackPanel();
        _buttonPanel.orientation = Orientation.horizontal;
        _buttonPanel.spacing = 8;
        _buttonPanel.horizontalAlignment = HorizontalAlignment.right;
        _buttonPanel.padding = Thickness(12, 8, 12, 12);

        // OK button
        _okButton = new Button("OK");
        _okButton.onClick.connect(&closeOk);
        _buttonPanel.addChild(_okButton);

        // Cancel button
        _cancelButton = new Button("Cancel");
        _cancelButton.onClick.connect(&closeCancel);
        _buttonPanel.addChild(_cancelButton);

        // Add to dialog
        addChild(_contentArea);
        addChild(_buttonPanel);
    }

    override Size measureOverride(Size availableSize) {
        if (!_isShowing)
            return Size.zero;

        // Measure content area
        Size contentSize = Size.zero;
        if (_contentArea !is null) {
            contentSize = _contentArea.measure(Size(
                max(0, availableSize.width - _padding.horizontalTotal),
                max(0, availableSize.height - _titleBarHeight - 60 - _padding.verticalTotal)
            ));
        }

        // Measure button panel
        Size buttonSize = Size.zero;
        if (_buttonPanel !is null) {
            buttonSize = _buttonPanel.measure(Size(
                max(0, availableSize.width - _padding.horizontalTotal),
                60
            ));
        }

        // Total size
        int width = max(contentSize.width, buttonSize.width) + _padding.horizontalTotal;
        int height = _titleBarHeight + contentSize.height + buttonSize.height + _padding.verticalTotal;

        // Minimum dialog size
        width = max(width, 200);
        height = max(height, 100);

        return Size(width, height);
    }

    override void arrangeOverride(Size finalSize) {
        if (!_isShowing) return;

        int y = _titleBarHeight;

        // Content area
        if (_contentArea !is null) {
            int contentHeight = finalSize.height - _titleBarHeight -
                               (_buttonPanel !is null ? _buttonPanel.desiredSize.height : 0);
            _contentArea.arrange(Rect(0, y, finalSize.width, max(0, contentHeight)));
            y += max(0, contentHeight);
        }

        // Button panel at bottom
        if (_buttonPanel !is null) {
            _buttonPanel.arrange(Rect(0, y, finalSize.width, _buttonPanel.desiredSize.height));
        }
    }

    override void renderOverride(RenderContext renderer) {
        if (!_isShowing) return;

        // Get screen bounds for overlay
        auto root = findRoot();
        Rect screenBounds = root !is null
            ? Rect(0, 0, root.windowSize.width, root.windowSize.height)
            : _bounds;

        // Draw modal overlay (dimmed background)
        if (_isModal) {
            renderer.fillRect(screenBounds, _overlayColor);
        }

        // Draw dialog background
        renderer.fillRect(_bounds, _backgroundColor);

        // Draw border
        renderer.drawRect(_bounds, _borderColor, _borderWidth);

        // Draw title bar
        Rect titleBar = Rect(_bounds.x, _bounds.y, _bounds.width, _titleBarHeight);
        renderer.fillRect(titleBar, _titleBarColor);

        // Draw title text
        if (_title.length > 0) {
            Point titlePos = Point(_bounds.x + 8, _bounds.y + 6);
            renderer.drawText(_title, titlePos, _titleColor);
        }

        // Draw children (content and buttons)
        foreach (child; _children) {
            child.render(renderer);
        }
    }

    override Widget hitTestOverride(Point localPoint) {
        if (!_isShowing) return null;

        // Modal dialogs capture all mouse input
        if (_isModal) {
            // Check if within dialog bounds
            if (_bounds.contains(localPoint)) {
                // Hit test children first
                foreach_reverse (child; _children) {
                    auto childLocal = child.parentToLocal(localPoint);
                    auto hit = child.hitTest(childLocal);
                    if (hit !is null)
                        return hit;
                }
                return this;
            }
            // Click outside dialog - still return dialog to capture click
            return this;
        }

        return super.hitTestOverride(localPoint);
    }
}

// ============================================================================
// Message Dialog
// ============================================================================

/**
 * Simple message dialog with icon and text.
 */
class MessageDialog : Dialog {
private:
    Label _messageLabel;
    MessageType _messageType = MessageType.info;

public:
    enum MessageType {
        info,
        warning,
        error,
        question,
    }

    /// Create message dialog
    this(string title, string message, MessageType type = MessageType.info) {
        super(title);
        _messageType = type;

        // Create message label
        _messageLabel = new Label(message);
        _messageLabel.horizontalAlignment = HorizontalAlignment.left;
        contentArea.addChild(_messageLabel);

        // Configure buttons based on type
        if (type == MessageType.question) {
            setOkButtonText("Yes");
            setCancelButtonText("No");
        } else {
            hideCancelButton();
        }
    }

    /// Message text
    @property string message() const {
        return _messageLabel !is null ? _messageLabel.text : "";
    }

    @property void message(string value) {
        if (_messageLabel !is null) {
            _messageLabel.text = value;
        }
    }
}

// ============================================================================
// Input Dialog
// ============================================================================

/**
 * Dialog with text input field.
 */
class InputDialog : Dialog {
private:
    Label _promptLabel;
    TextInput _textInput;

public:
    /// Input submitted signal
    Signal!string onInput;

    /// Create input dialog
    this(string title, string prompt, string defaultValue = "") {
        super(title);

        // Create prompt label
        _promptLabel = new Label(prompt);
        contentArea.addChild(_promptLabel);

        // Create text input
        _textInput = new TextInput(defaultValue);
        _textInput.horizontalAlignment = HorizontalAlignment.stretch;
        contentArea.addChild(_textInput);

        // Connect input submit to dialog close
        _textInput.onSubmit.connect((string text) {
            onInput.emit(text);
            closeOk();
        });
    }

    /// Get input value
    @property string inputValue() const {
        return _textInput !is null ? _textInput.text : "";
    }

    /// Set input value
    @property void inputValue(string value) {
        if (_textInput !is null) {
            _textInput.text = value;
        }
    }

    /// Focus the input field
    void focusInput() {
        if (_textInput !is null) {
            _textInput.focus();
        }
    }

protected:
    override void buildFocusableList() {
        super.buildFocusableList();
        // Input should be first in focus order
        if (_textInput !is null) {
            // Move input to front
            import std.algorithm : remove, countUntil;
            auto idx = _focusableWidgets.countUntil(_textInput);
            if (idx > 0) {
                _focusableWidgets = _focusableWidgets.remove(idx);
                _focusableWidgets = [cast(Widget)_textInput] ~ _focusableWidgets;
            }
        }
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

unittest {
    // Test DialogResult enum
    auto result = DialogResult.ok;
    assert(result == DialogResult.ok);
}

unittest {
    // Test Dialog creation
    auto dialog = new Dialog("Test Dialog");
    assert(dialog.title == "Test Dialog");
    assert(!dialog.isShowing);
}

unittest {
    // Test MessageDialog creation
    auto msg = new MessageDialog("Info", "Hello World", MessageDialog.MessageType.info);
    assert(msg.title == "Info");
    assert(msg.message == "Hello World");
}

unittest {
    // Test InputDialog creation
    auto input = new InputDialog("Name", "Enter your name:", "Default");
    assert(input.title == "Name");
    assert(input.inputValue == "Default");
}
