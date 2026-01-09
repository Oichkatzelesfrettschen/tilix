/**
 * Keybinding Editor Dialog
 *
 * Configuration GUI for keyboard shortcuts.
 * Allows viewing, editing, and resetting keybindings.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.dialogs.keybind_editor;

version (PURE_D_BACKEND):

import pured.widget.base;
import pured.widget.container;
import pured.widget.controls;
import pured.widget.dialog;
import pured.widget.events;
import pured.util.signal;
import std.algorithm : min, max;
import std.format : format;
import std.string : toLower;

// ============================================================================
// Keybinding Data Structures
// ============================================================================

/**
 * Represents a keyboard shortcut.
 */
struct Keybinding {
    string action;       // Action name (e.g., "copy", "paste")
    string category;     // Category (e.g., "Clipboard", "Navigation")
    string binding;      // Current binding (e.g., "Ctrl+Shift+C")
    string defaultBinding;  // Default binding
    string description;  // Human-readable description

    /// Check if binding differs from default
    @property bool isModified() const {
        return binding != defaultBinding;
    }
}

// ============================================================================
// Keybinding Row Widget
// ============================================================================

/**
 * Single row in the keybinding list.
 */
class KeybindingRow : Widget {
private:
    Keybinding _binding;
    bool _selected = false;
    bool _hovered = false;
    bool _editing = false;
    string _editBuffer;

public:
    /// Row selected signal
    Signal!() onSelect;

    /// Binding changed signal
    Signal!string onBindingChanged;

    /// Edit started signal
    Signal!() onEditStart;

    /// Create row
    this(Keybinding binding) {
        _binding = binding;
    }

    /// Get binding data
    @property ref const(Keybinding) binding() const { return _binding; }

    /// Set binding
    @property void binding(Keybinding value) {
        _binding = value;
        invalidateVisual();
    }

    /// Whether row is selected
    @property bool selected() const { return _selected; }
    @property void selected(bool value) {
        _selected = value;
        invalidateVisual();
    }

    /// Whether row is in edit mode
    @property bool editing() const { return _editing; }

    /// Start editing the binding
    void startEdit() {
        _editing = true;
        _editBuffer = "";
        onEditStart.emit();
        invalidateVisual();
    }

    /// Cancel editing
    void cancelEdit() {
        _editing = false;
        invalidateVisual();
    }

    /// Apply captured key combination
    void applyEdit(string newBinding) {
        _editing = false;
        if (newBinding.length > 0) {
            _binding.binding = newBinding;
            onBindingChanged.emit(newBinding);
        }
        invalidateVisual();
    }

    /// Reset to default binding
    void resetToDefault() {
        _binding.binding = _binding.defaultBinding;
        onBindingChanged.emit(_binding.defaultBinding);
        invalidateVisual();
    }

protected:
    override Size measureOverride(Size availableSize) {
        return Size(availableSize.width, 28);  // Fixed row height
    }

    override void arrangeOverride(Size finalSize) {
        // No children
    }

    override void renderOverride(RenderContext renderer) {
        // Background
        uint bgColor = _selected ? 0xFF404060 : (_hovered ? 0xFF353545 : 0xFF2A2A35);
        renderer.fillRect(_bounds, bgColor);

        // Layout: [Action: 40%] [Binding: 30%] [Default: 30%]
        float actionWidth = _bounds.width * 0.4f;
        float bindingWidth = _bounds.width * 0.3f;

        // Action name
        Point actionPos = Point(_bounds.x + 8, _bounds.y + 6);
        renderer.drawText(_binding.action, actionPos, 0xFFDDDDDD);

        // Current binding (or edit prompt)
        Point bindingPos = Point(cast(int)(_bounds.x + actionWidth), _bounds.y + 6);
        if (_editing) {
            renderer.drawText("[Press key...]", bindingPos, 0xFFFFAA00);
        } else {
            uint bindingColor = _binding.isModified ? 0xFFAAFFAA : 0xFFBBBBBB;
            renderer.drawText(_binding.binding, bindingPos, bindingColor);
        }

        // Default binding
        Point defaultPos = Point(cast(int)(_bounds.x + actionWidth + bindingWidth), _bounds.y + 6);
        renderer.drawText(_binding.defaultBinding, defaultPos, 0xFF888888);

        // Border if selected
        if (_selected) {
            renderer.drawRect(_bounds, 0xFF6666AA, 1);
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
            onSelect.emit();
            return true;
        }
        return false;
    }
}

// ============================================================================
// Keybinding Editor Dialog
// ============================================================================

/**
 * Dialog for editing keyboard shortcuts.
 *
 * Features:
 * - Categorized keybinding list
 * - Click to edit (capture next keypress)
 * - Conflict detection
 * - Reset to default
 */
class KeybindingEditorDialog : Dialog {
private:
    StackPanel _listPanel;
    KeybindingRow[] _rows;
    KeybindingRow _selectedRow;
    KeybindingRow _editingRow;
    Label _statusLabel;
    Button _resetButton;
    Keybinding[] _bindings;
    bool _capturing = false;

public:
    /// Keybindings changed signal
    Signal!(Keybinding[]) onBindingsChanged;

    /// Create keybinding editor
    this() {
        super("Keyboard Shortcuts");
        initDefaultBindings();
        setupKeybindEditorContent();
    }

    /// Create with existing bindings
    this(Keybinding[] bindings) {
        super("Keyboard Shortcuts");
        _bindings = bindings.dup;
        if (_bindings.length == 0) {
            initDefaultBindings();
        }
        setupKeybindEditorContent();
    }

    /// Get current bindings
    @property Keybinding[] bindings() { return _bindings; }

protected:
    void initDefaultBindings() {
        // Clipboard
        _bindings ~= Keybinding("Copy", "Clipboard", "Ctrl+Shift+C", "Ctrl+Shift+C", "Copy selected text");
        _bindings ~= Keybinding("Paste", "Clipboard", "Ctrl+Shift+V", "Ctrl+Shift+V", "Paste from clipboard");
        _bindings ~= Keybinding("Copy as HTML", "Clipboard", "Ctrl+Shift+H", "Ctrl+Shift+H", "Copy with formatting");

        // Tabs
        _bindings ~= Keybinding("New Tab", "Tabs", "Ctrl+Shift+T", "Ctrl+Shift+T", "Open new tab");
        _bindings ~= Keybinding("Close Tab", "Tabs", "Ctrl+Shift+W", "Ctrl+Shift+W", "Close current tab");
        _bindings ~= Keybinding("Next Tab", "Tabs", "Ctrl+PageDown", "Ctrl+PageDown", "Switch to next tab");
        _bindings ~= Keybinding("Previous Tab", "Tabs", "Ctrl+PageUp", "Ctrl+PageUp", "Switch to previous tab");
        _bindings ~= Keybinding("Rename Tab", "Tabs", "Ctrl+Shift+R", "Ctrl+Shift+R", "Rename current tab");

        // Splits
        _bindings ~= Keybinding("Split Horizontal", "Splits", "Ctrl+Shift+E", "Ctrl+Shift+E", "Split pane horizontally");
        _bindings ~= Keybinding("Split Vertical", "Splits", "Ctrl+Shift+O", "Ctrl+Shift+O", "Split pane vertically");
        _bindings ~= Keybinding("Close Pane", "Splits", "Ctrl+Shift+Q", "Ctrl+Shift+Q", "Close current pane");
        _bindings ~= Keybinding("Focus Left", "Splits", "Alt+Left", "Alt+Left", "Focus pane to left");
        _bindings ~= Keybinding("Focus Right", "Splits", "Alt+Right", "Alt+Right", "Focus pane to right");
        _bindings ~= Keybinding("Focus Up", "Splits", "Alt+Up", "Alt+Up", "Focus pane above");
        _bindings ~= Keybinding("Focus Down", "Splits", "Alt+Down", "Alt+Down", "Focus pane below");

        // Search
        _bindings ~= Keybinding("Find", "Search", "Ctrl+Shift+F", "Ctrl+Shift+F", "Open search");
        _bindings ~= Keybinding("Find Next", "Search", "Ctrl+G", "Ctrl+G", "Find next match");
        _bindings ~= Keybinding("Find Previous", "Search", "Ctrl+Shift+G", "Ctrl+Shift+G", "Find previous match");

        // Zoom
        _bindings ~= Keybinding("Zoom In", "View", "Ctrl++", "Ctrl++", "Increase font size");
        _bindings ~= Keybinding("Zoom Out", "View", "Ctrl+-", "Ctrl+-", "Decrease font size");
        _bindings ~= Keybinding("Reset Zoom", "View", "Ctrl+0", "Ctrl+0", "Reset font size");

        // Other
        _bindings ~= Keybinding("Preferences", "Other", "Ctrl+,", "Ctrl+,", "Open preferences");
        _bindings ~= Keybinding("Fullscreen", "Other", "F11", "F11", "Toggle fullscreen");
    }

    void setupKeybindEditorContent() {
        auto mainPanel = new StackPanel();
        mainPanel.orientation = Orientation.vertical;
        mainPanel.spacing = 8;
        mainPanel.padding = Thickness.uniform(8);

        // Header row
        auto header = new StackPanel();
        header.orientation = Orientation.horizontal;
        header.spacing = 0;

        auto headerAction = new Label("Action");
        auto headerBinding = new Label("Binding");
        auto headerDefault = new Label("Default");

        header.addChild(headerAction);
        header.addChild(headerBinding);
        header.addChild(headerDefault);
        mainPanel.addChild(header);

        // Keybinding list
        _listPanel = new StackPanel();
        _listPanel.orientation = Orientation.vertical;
        _listPanel.spacing = 2;

        string currentCategory = "";
        foreach (ref binding; _bindings) {
            // Add category header if changed
            if (binding.category != currentCategory) {
                currentCategory = binding.category;
                auto catLabel = new Label("-- " ~ currentCategory ~ " --");
                _listPanel.addChild(catLabel);
            }

            auto row = new KeybindingRow(binding);
            row.onSelect.connect(() { selectRow(row); });
            row.onEditStart.connect(() { startCapture(row); });
            row.onBindingChanged.connect((newBinding) { updateBinding(row, newBinding); });
            _rows ~= row;
            _listPanel.addChild(row);
        }

        mainPanel.addChild(_listPanel);

        // Status/help area
        _statusLabel = new Label("Click a binding to edit. Press Escape to cancel.");
        mainPanel.addChild(_statusLabel);

        // Buttons row
        auto buttonRow = new StackPanel();
        buttonRow.orientation = Orientation.horizontal;
        buttonRow.spacing = 8;

        _resetButton = new Button("Reset to Default");
        _resetButton.onClick.connect(&resetSelected);
        _resetButton.enabled = false;
        buttonRow.addChild(_resetButton);

        auto resetAllBtn = new Button("Reset All");
        resetAllBtn.onClick.connect(&resetAll);
        buttonRow.addChild(resetAllBtn);

        mainPanel.addChild(buttonRow);

        contentArea.addChild(mainPanel);

        // Configure dialog buttons
        setOkButtonText("Apply");
    }

    void selectRow(KeybindingRow row) {
        if (_selectedRow !is null) {
            _selectedRow.selected = false;
        }
        _selectedRow = row;
        if (_selectedRow !is null) {
            _selectedRow.selected = true;
            _resetButton.enabled = _selectedRow.binding.isModified;

            // Double-click to edit
            if (_editingRow is null) {
                row.startEdit();
            }
        }
    }

    void startCapture(KeybindingRow row) {
        _editingRow = row;
        _capturing = true;
        _statusLabel.text = "Press key combination... (Escape to cancel)";
    }

    void updateBinding(KeybindingRow row, string newBinding) {
        // Find and update the binding in our array
        foreach (ref binding; _bindings) {
            if (binding.action == row.binding.action) {
                binding.binding = newBinding;
                break;
            }
        }

        // Check for conflicts
        checkConflicts(row);

        _capturing = false;
        _editingRow = null;
        _statusLabel.text = "Click a binding to edit. Press Escape to cancel.";

        if (_selectedRow !is null) {
            _resetButton.enabled = _selectedRow.binding.isModified;
        }
    }

    void checkConflicts(KeybindingRow changedRow) {
        string newBinding = changedRow.binding.binding;
        foreach (row; _rows) {
            if (row !is changedRow && row.binding.binding == newBinding) {
                _statusLabel.text = format("Conflict: '%s' already uses %s",
                    row.binding.action, newBinding);
                return;
            }
        }
    }

    void resetSelected() {
        if (_selectedRow !is null) {
            _selectedRow.resetToDefault();
            _resetButton.enabled = false;

            // Update our binding array
            foreach (ref binding; _bindings) {
                if (binding.action == _selectedRow.binding.action) {
                    binding.binding = binding.defaultBinding;
                    break;
                }
            }
        }
    }

    void resetAll() {
        foreach (row; _rows) {
            row.resetToDefault();
        }
        foreach (ref binding; _bindings) {
            binding.binding = binding.defaultBinding;
        }
        _resetButton.enabled = false;
        _statusLabel.text = "All bindings reset to defaults.";
    }

    /// Handle key capture for editing
    bool handleKeyForCapture(int key, int mods) {
        if (!_capturing || _editingRow is null) {
            return false;
        }

        // Escape cancels
        if (key == 256) {  // GLFW_KEY_ESCAPE
            _editingRow.cancelEdit();
            _editingRow = null;
            _capturing = false;
            _statusLabel.text = "Edit cancelled.";
            return true;
        }

        // Build key string
        string keyStr = buildKeyString(key, mods);
        if (keyStr.length > 0) {
            _editingRow.applyEdit(keyStr);
            return true;
        }

        return false;
    }

    string buildKeyString(int key, int mods) {
        import std.array : appender;

        auto result = appender!string();

        // Modifiers
        if (mods & 0x0002) result.put("Ctrl+");   // GLFW_MOD_CONTROL
        if (mods & 0x0004) result.put("Alt+");    // GLFW_MOD_ALT
        if (mods & 0x0001) result.put("Shift+");  // GLFW_MOD_SHIFT
        if (mods & 0x0008) result.put("Super+");  // GLFW_MOD_SUPER

        // Key name
        string keyName = getKeyName(key);
        if (keyName.length > 0) {
            result.put(keyName);
            return result.data;
        }

        return "";
    }

    string getKeyName(int key) {
        // Common keys
        switch (key) {
            case 32: return "Space";
            case 39: return "'";
            case 44: return ",";
            case 45: return "-";
            case 46: return ".";
            case 47: return "/";
            case 48: .. case 57: return [cast(char)('0' + key - 48)];
            case 59: return ";";
            case 61: return "=";
            case 65: .. case 90: return [cast(char)('A' + key - 65)];
            case 91: return "[";
            case 92: return "\\";
            case 93: return "]";
            case 96: return "`";
            case 256: return "Escape";
            case 257: return "Enter";
            case 258: return "Tab";
            case 259: return "Backspace";
            case 260: return "Insert";
            case 261: return "Delete";
            case 262: return "Right";
            case 263: return "Left";
            case 264: return "Down";
            case 265: return "Up";
            case 266: return "PageUp";
            case 267: return "PageDown";
            case 268: return "Home";
            case 269: return "End";
            case 280: return "CapsLock";
            case 281: return "ScrollLock";
            case 282: return "NumLock";
            case 283: return "PrintScreen";
            case 284: return "Pause";
            case 290: .. case 301: return format("F%d", key - 289);
            default: return "";
        }
    }

    override void closeOk() {
        onBindingsChanged.emit(_bindings);
        super.closeOk();
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

unittest {
    // Test Keybinding creation
    Keybinding kb;
    kb.action = "Copy";
    kb.binding = "Ctrl+C";
    kb.defaultBinding = "Ctrl+C";
    assert(!kb.isModified);

    kb.binding = "Ctrl+Shift+C";
    assert(kb.isModified);
}

unittest {
    // Test dialog creation
    auto dialog = new KeybindingEditorDialog();
    assert(dialog.title == "Keyboard Shortcuts");
    assert(dialog.bindings.length > 0);
}
