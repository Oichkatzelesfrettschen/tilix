/**
 * Tab Rename Dialog
 *
 * Dialog for renaming terminal tabs.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.dialogs.tab_rename;

version (PURE_D_BACKEND):

import pured.widget.base;
import pured.widget.container;
import pured.widget.controls;
import pured.widget.dialog;
import pured.util.signal;

/**
 * Dialog for renaming a tab.
 *
 * Displays a text input with the current tab name and
 * OK/Cancel buttons. Emits onRenamed signal with the
 * new name when confirmed.
 */
class TabRenameDialog : Dialog {
private:
    TextInput _nameInput;
    Label _promptLabel;
    string _originalName;

public:
    /// Renamed signal - emits new name when confirmed
    Signal!string onRenamed;

    /**
     * Create tab rename dialog.
     *
     * Params:
     *   currentName = Current tab name to display in input
     */
    this(string currentName = "") {
        super("Rename Tab");
        _originalName = currentName;

        setupDialogContent();
    }

    /// Current input value
    @property string newName() const {
        return _nameInput !is null ? _nameInput.text : "";
    }

    /// Set input value
    @property void newName(string value) {
        if (_nameInput !is null) {
            _nameInput.text = value;
        }
    }

    /// Original name before editing
    @property string originalName() const {
        return _originalName;
    }

    /// Reset to original name
    void reset() {
        if (_nameInput !is null) {
            _nameInput.text = _originalName;
            _nameInput.selectAll();
        }
    }

    /// Show dialog and focus input
    override void showModal() {
        super.showModal();

        // Focus and select all text in input
        if (_nameInput !is null) {
            _nameInput.focus();
            _nameInput.selectAll();
        }
    }

protected:
    /// Set up dialog-specific content
    void setupDialogContent() {
        // Create vertical layout for content
        auto layout = new StackPanel();
        layout.orientation = Orientation.vertical;
        layout.spacing = 8;

        // Prompt label
        _promptLabel = new Label("Enter new tab name:");
        layout.addChild(_promptLabel);

        // Name input
        _nameInput = new TextInput(_originalName, "Tab name");
        _nameInput.horizontalAlignment = HorizontalAlignment.stretch;
        layout.addChild(_nameInput);

        // Connect input submit to dialog close
        _nameInput.onSubmit.connect((string text) {
            if (text.length > 0) {
                onRenamed.emit(text);
                closeOk();
            }
        });

        // Add layout to content area
        contentArea.addChild(layout);

        // Configure OK button
        setOkButtonText("Rename");
    }

    /// Override to emit renamed signal on OK
    override void closeOk() {
        string name = newName;
        if (name.length > 0 && name != _originalName) {
            onRenamed.emit(name);
        }
        super.closeOk();
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

unittest {
    // Test dialog creation
    auto dialog = new TabRenameDialog("Terminal");
    assert(dialog.title == "Rename Tab");
    assert(dialog.originalName == "Terminal");
    assert(dialog.newName == "Terminal");
}

unittest {
    // Test name change
    auto dialog = new TabRenameDialog("Old Name");
    dialog.newName = "New Name";
    assert(dialog.newName == "New Name");
    assert(dialog.originalName == "Old Name");
}

unittest {
    // Test reset
    auto dialog = new TabRenameDialog("Original");
    dialog.newName = "Changed";
    dialog.reset();
    assert(dialog.newName == "Original");
}
