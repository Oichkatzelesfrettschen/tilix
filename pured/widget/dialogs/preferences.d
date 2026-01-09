/**
 * Preferences Dialog
 *
 * Configuration GUI for terminal settings.
 * Organized into tabbed sections for different setting categories.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.dialogs.preferences;

version (PURE_D_BACKEND):

import pured.widget.base;
import pured.widget.container;
import pured.widget.controls;
import pured.widget.dialog;
import pured.util.signal;
import pured.config : PureDConfig;
import std.algorithm : min, max;
import std.conv : to;

// ============================================================================
// Preferences Dialog
// ============================================================================

/**
 * Main preferences dialog with tabbed settings pages.
 *
 * Tabs:
 * - General: Font, scrollback, window behavior
 * - Appearance: Colors, theme, cursor style
 * - Keybindings: Keyboard shortcuts
 * - Advanced: IPC, accessibility
 */
class PreferencesDialog : Dialog {
private:
    TabContainer _tabs;
    PureDConfig _config;
    PureDConfig _originalConfig;

    // General tab controls
    TextInput _fontSizeInput;
    TextInput _scrollbackInput;
    Checkbox _quakeModeCheck;

    // Appearance tab controls
    TextInput _themePathInput;
    TextInput _cursorStyleInput;

    // Apply button
    Button _applyButton;

public:
    /// Settings changed signal
    Signal!PureDConfig onSettingsChanged;

    /// Create preferences dialog
    this(PureDConfig config) {
        super("Preferences");
        _config = config;
        _originalConfig = config;

        setupPreferencesContent();
    }

    /// Get current configuration
    @property PureDConfig config() { return _config; }

    /// Get tab container (E.5.2: For rendering support)
    @property TabContainer tabContainer() { return _tabs; }

    /// Get number of tabs
    @property int tabCount() { return cast(int)_tabs.childCount; }

    /// Get selected tab index
    @property int selectedTab() { return _tabs.selectedIndex; }

    /// Get tab title by index
    string getTabTitle(int index) {
        return _tabs.tabTitle(index);
    }

    /// Get selected tab title
    string selectedTabTitle() {
        if (_tabs.selectedIndex >= 0)
            return _tabs.tabTitle(_tabs.selectedIndex);
        return "";
    }

    /// Reset to original values
    void reset() {
        _config = _originalConfig;
        loadSettingsToControls();
    }

    /// Apply current settings
    void apply() {
        saveControlsToSettings();
        onSettingsChanged.emit(_config);
    }

protected:
    /// Set up preferences content with tabs
    void setupPreferencesContent() {
        // Create tab container
        _tabs = new TabContainer();
        _tabs.horizontalAlignment = HorizontalAlignment.stretch;
        _tabs.verticalAlignment = VerticalAlignment.stretch;

        // Create tab pages
        auto generalPage = createGeneralPage();
        auto appearancePage = createAppearancePage();
        auto keybindingsPage = createKeybindingsPage();
        auto profilesPage = createProfilesPage();
        auto advancedPage = createAdvancedPage();

        // Add tabs
        _tabs.addTab(generalPage, "General");
        _tabs.addTab(appearancePage, "Appearance");
        _tabs.addTab(keybindingsPage, "Keybindings");
        _tabs.addTab(profilesPage, "Profiles");
        _tabs.addTab(advancedPage, "Advanced");

        // Add to content area
        contentArea.addChild(_tabs);

        // Configure buttons
        setOkButtonText("OK");
        setCancelButtonText("Cancel");

        // Load current settings
        loadSettingsToControls();
    }

    /// Create General settings page
    Widget createGeneralPage() {
        auto panel = new StackPanel();
        panel.orientation = Orientation.vertical;
        panel.spacing = 12;
        panel.padding = Thickness.uniform(8);

        // Font size
        panel.addChild(new Label("Font Size:"));
        _fontSizeInput = new TextInput("16");
        panel.addChild(_fontSizeInput);

        // Scrollback lines
        panel.addChild(new Label("Scrollback Lines:"));
        _scrollbackInput = new TextInput("200000");
        panel.addChild(_scrollbackInput);

        // Quake mode
        _quakeModeCheck = new Checkbox("Enable Quake Mode (dropdown terminal)");
        panel.addChild(_quakeModeCheck);

        // Window size (read-only info)
        panel.addChild(new Label("Window size: Configured in window manager"));

        return panel;
    }

    /// Create Appearance settings page
    Widget createAppearancePage() {
        auto panel = new StackPanel();
        panel.orientation = Orientation.vertical;
        panel.spacing = 12;
        panel.padding = Thickness.uniform(8);

        // Theme path
        panel.addChild(new Label("Theme Path:"));
        _themePathInput = new TextInput("");
        panel.addChild(_themePathInput);

        // Cursor style
        panel.addChild(new Label("Cursor Style:"));
        _cursorStyleInput = new TextInput("block");
        panel.addChild(_cursorStyleInput);

        // Color scheme info
        panel.addChild(new Label("Colors are loaded from theme file"));
        panel.addChild(new Label("Supported formats: JSON, TOML, Xresources"));

        return panel;
    }

    /// Create Keybindings settings page
    Widget createKeybindingsPage() {
        auto panel = new StackPanel();
        panel.orientation = Orientation.vertical;
        panel.spacing = 8;
        panel.padding = Thickness.uniform(8);

        panel.addChild(new Label("Keyboard Shortcuts"));
        panel.addChild(new Label(""));

        // Header row
        auto header = new StackPanel();
        header.orientation = Orientation.horizontal;
        header.spacing = 40;
        header.addChild(new Label("Action"));
        header.addChild(new Label("Binding"));
        panel.addChild(header);

        // Standard keybindings (display only for now)
        addKeybindingRow(panel, "Copy", "Ctrl+Shift+C");
        addKeybindingRow(panel, "Paste", "Ctrl+Shift+V");
        addKeybindingRow(panel, "New Tab", "Ctrl+Shift+T");
        addKeybindingRow(panel, "Close Tab", "Ctrl+Shift+W");
        addKeybindingRow(panel, "Split Horizontal", "Ctrl+Shift+E");
        addKeybindingRow(panel, "Split Vertical", "Ctrl+Shift+O");
        addKeybindingRow(panel, "Find", "Ctrl+Shift+F");
        addKeybindingRow(panel, "Zoom In", "Ctrl++");
        addKeybindingRow(panel, "Zoom Out", "Ctrl+-");

        return panel;
    }

    /// Create Profiles settings page
    Widget createProfilesPage() {
        auto panel = new StackPanel();
        panel.orientation = Orientation.vertical;
        panel.spacing = 8;
        panel.padding = Thickness.uniform(8);

        panel.addChild(new Label("Named Configuration Profiles"));
        panel.addChild(new Label(""));

        // Profile list (read-only for now)
        panel.addChild(new Label("Current Profile: Default"));
        panel.addChild(new Label(""));

        // Available profiles
        panel.addChild(new Label("Available Profiles:"));
        panel.addChild(new Label("  - Default (system defaults)"));
        panel.addChild(new Label("  - Dark Theme (optimized for dark backgrounds)"));
        panel.addChild(new Label("  - Light Theme (optimized for light backgrounds)"));
        panel.addChild(new Label("  - High Contrast (accessibility)"));
        panel.addChild(new Label(""));
        panel.addChild(new Label("Note: Profile editing coming in future update"));

        return panel;
    }

    /// Create Advanced settings page
    Widget createAdvancedPage() {
        auto panel = new StackPanel();
        panel.orientation = Orientation.vertical;
        panel.spacing = 12;
        panel.padding = Thickness.uniform(8);

        panel.addChild(new Label("Advanced Settings"));
        panel.addChild(new Label(""));

        // IPC info
        panel.addChild(new Label("IPC: Cap'n Proto over Unix socket"));
        panel.addChild(new Label("Socket: $XDG_RUNTIME_DIR/tilix-pure.sock"));

        // Accessibility
        panel.addChild(new Label(""));
        panel.addChild(new Label("Accessibility:"));
        panel.addChild(new Label("  - High contrast themes available"));
        panel.addChild(new Label("  - Keyboard-only navigation supported"));
        panel.addChild(new Label("  - Screen reader integration planned"));

        return panel;
    }

    /// Helper to add keybinding row (simple layout)
    void addKeybindingRow(StackPanel parent, string action, string binding) {
        auto row = new StackPanel();
        row.orientation = Orientation.horizontal;
        row.spacing = 40;
        row.addChild(new Label(action ~ ":"));
        row.addChild(new Label(binding));
        parent.addChild(row);
    }

    /// Load current settings into controls
    void loadSettingsToControls() {
        if (_fontSizeInput !is null)
            _fontSizeInput.text = _config.fontSize.to!string;

        if (_scrollbackInput !is null)
            _scrollbackInput.text = _config.scrollbackMaxLines.to!string;

        if (_quakeModeCheck !is null)
            _quakeModeCheck.checked = _config.quakeMode;

        if (_themePathInput !is null)
            _themePathInput.text = _config.themePath;

        if (_cursorStyleInput !is null)
            _cursorStyleInput.text = _config.cursorStyle;
    }

    /// Save controls to settings
    void saveControlsToSettings() {
        if (_fontSizeInput !is null) {
            try {
                _config.fontSize = _fontSizeInput.text.to!int;
            } catch (Exception) {}
        }

        if (_scrollbackInput !is null) {
            try {
                _config.scrollbackMaxLines = _scrollbackInput.text.to!size_t;
            } catch (Exception) {}
        }

        if (_quakeModeCheck !is null)
            _config.quakeMode = _quakeModeCheck.checked;

        if (_themePathInput !is null)
            _config.themePath = _themePathInput.text;

        if (_cursorStyleInput !is null)
            _config.cursorStyle = _cursorStyleInput.text;
    }

    /// Override closeOk to apply settings
    override void closeOk() {
        apply();
        super.closeOk();
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

unittest {
    import pured.config : defaultConfig;

    // Test dialog creation
    auto config = defaultConfig();
    auto dialog = new PreferencesDialog(config);
    assert(dialog.title == "Preferences");
}

unittest {
    import pured.config : defaultConfig;

    // Test reset functionality
    auto config = defaultConfig();
    config.fontSize = 20;
    auto dialog = new PreferencesDialog(config);
    dialog.reset();
    assert(dialog.config.fontSize == 20);  // Should match original
}
