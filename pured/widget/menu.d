/**
 * Menu System
 *
 * Menu infrastructure for dropdown menus, context menus, and menu bars.
 * Provides keyboard navigation, shortcut display, and submenu support.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.menu;

version (PURE_D_BACKEND):

import pured.widget.base;
import pured.widget.container;
import pured.widget.events;
import pured.util.signal;
import std.algorithm : min, max;

// ============================================================================
// Menu Item
// ============================================================================

/**
 * Individual menu item with label, shortcut, and optional icon.
 */
class MenuItem : Widget {
    mixin EventHandlers;

private:
    string _label;
    string _shortcut;
    bool _hovered = false;
    bool _isSeparator = false;
    Menu _submenu;

    // Appearance
    uint _textColor = 0xFFFFFFFF;
    uint _disabledColor = 0xFF808080;
    uint _hoverColor = 0xFF404060;
    uint _backgroundColor = 0xFF2A2A2A;
    int _itemHeight = 24;
    int _iconWidth = 20;
    int _shortcutPadding = 40;

public:
    /// Click signal
    Signal!() onClick;

    /// Item label
    @property string label() const { return _label; }
    @property void label(string value) {
        _label = value;
        invalidateMeasure();
    }

    /// Keyboard shortcut display text
    @property string shortcut() const { return _shortcut; }
    @property void shortcut(string value) {
        _shortcut = value;
        invalidateMeasure();
    }

    /// Whether this is a separator
    @property bool isSeparator() const { return _isSeparator; }

    /// Submenu (if any)
    @property Menu submenu() { return _submenu; }
    @property void submenu(Menu value) { _submenu = value; }

    /// Whether item has submenu
    @property bool hasSubmenu() const { return _submenu !is null; }

    /// Create menu item
    this(string label, string shortcut = "") {
        _label = label;
        _shortcut = shortcut;
    }

    /// Create separator
    static MenuItem separator() {
        auto item = new MenuItem("");
        item._isSeparator = true;
        item._enabled = false;
        return item;
    }

    /// Activate the menu item
    void activate() {
        if (_enabled && !_isSeparator) {
            onClick.emit();
        }
    }

protected:
    override Size measureOverride(Size availableSize) {
        if (_isSeparator) {
            return Size(0, 8);  // Separator height
        }

        // Estimate text width (simplified)
        int labelWidth = cast(int)(_label.length * 8);
        int shortcutWidth = cast(int)(_shortcut.length * 7);
        int totalWidth = _iconWidth + labelWidth + _shortcutPadding + shortcutWidth + 20;

        return Size(totalWidth, _itemHeight);
    }

    override void arrangeOverride(Size finalSize) {
        // Menu items don't have children to arrange
    }

    override void renderOverride(RenderContext renderer) {
        if (_isSeparator) {
            // Draw separator line using a thin filled rect
            int y = _bounds.y + _bounds.height / 2;
            renderer.fillRect(
                Rect(_bounds.x + 4, y, _bounds.width - 8, 1),
                0xFF606060
            );
            return;
        }

        // Background
        uint bgColor = _hovered && _enabled ? _hoverColor : _backgroundColor;
        renderer.fillRect(_bounds, bgColor);

        // Text color
        uint textColor = _enabled ? _textColor : _disabledColor;

        // Draw label
        Point labelPos = Point(_bounds.x + _iconWidth, _bounds.y + 4);
        renderer.drawText(_label, labelPos, textColor);

        // Draw shortcut (right-aligned)
        if (_shortcut.length > 0) {
            int shortcutWidth = cast(int)(_shortcut.length * 7);
            Point shortcutPos = Point(
                _bounds.x + _bounds.width - shortcutWidth - 8,
                _bounds.y + 4
            );
            renderer.drawText(_shortcut, shortcutPos, _disabledColor);
        }

        // Draw submenu arrow
        if (hasSubmenu) {
            int arrowX = _bounds.x + _bounds.width - 12;
            int arrowY = _bounds.y + _bounds.height / 2;
            renderer.drawText(">", Point(arrowX, arrowY - 6), textColor);
        }
    }

    override Widget hitTestOverride(Point localPoint) {
        if (_isSeparator) return null;
        if (!_enabled) return null;
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
        if (_enabled && !_isSeparator && event.eventType == MouseEventType.buttonDown && event.button == MouseButton.left) {
            activate();
            return true;
        }
        return false;
    }
}

// ============================================================================
// Menu
// ============================================================================

/**
 * Container for menu items.
 *
 * Renders as a vertical list of menu items with keyboard navigation.
 */
class Menu : Container {
    mixin EventHandlers;

private:
    int _selectedIndex = -1;
    bool _isOpen = false;
    Point _popupPosition;

    // Appearance
    uint _backgroundColor = 0xFF2A2A2A;
    uint _borderColor = 0xFF606060;
    int _borderWidth = 1;
    int _padding = 4;

public:
    /// Menu closed signal
    Signal!() onClosed;

    /// Menu item selected signal (emits selected item)
    Signal!MenuItem onItemSelected;

    /// Whether menu is currently open
    @property bool isOpen() const { return _isOpen; }

    /// Currently selected index
    @property int selectedIndex() const { return _selectedIndex; }

    /// Create empty menu
    this() {
        // Default setup
    }

    /// Add menu item
    void addItem(MenuItem item) {
        addChild(item);
    }

    /// Add separator
    void addSeparator() {
        addChild(MenuItem.separator());
    }

    /// Open menu at position
    void open(Point position) {
        _popupPosition = position;
        _isOpen = true;
        _selectedIndex = -1;

        // Find first selectable item
        selectNextItem(true);

        invalidateMeasure();
    }

    /// Close menu
    void close() {
        _isOpen = false;
        _selectedIndex = -1;
        onClosed.emit();
        invalidateVisual();
    }

    /// Handle keyboard navigation
    bool handleKeyEvent(KeyEvent event) {
        if (!_isOpen) return false;
        if (!event.isPressed) return false;

        switch (event.keyCode) {
            case KeyCode.up:
                selectPreviousItem();
                return true;

            case KeyCode.down:
                selectNextItem();
                return true;

            case KeyCode.enter:
            case KeyCode.space:
                activateSelected();
                return true;

            case KeyCode.escape:
                close();
                return true;

            case KeyCode.right:
                // Open submenu if available
                if (auto item = getSelectedItem()) {
                    if (item.hasSubmenu) {
                        // TODO: Open submenu
                        return true;
                    }
                }
                break;

            default:
                // Check for accelerator keys
                if (auto item = findItemByAccelerator(event.keyCode)) {
                    item.activate();
                    close();
                    return true;
                }
                break;
        }

        return false;
    }

    /// Get currently selected item
    MenuItem getSelectedItem() {
        if (_selectedIndex < 0 || _selectedIndex >= _children.length)
            return null;
        return cast(MenuItem)_children[_selectedIndex];
    }

protected:
    /// Select next selectable item
    void selectNextItem(bool initial = false) {
        int start = initial ? -1 : _selectedIndex;
        for (int i = 1; i <= cast(int)_children.length; i++) {
            int idx = (start + i) % cast(int)_children.length;
            if (idx < 0) idx += cast(int)_children.length;
            auto item = cast(MenuItem)_children[idx];
            if (item !is null && item.enabled && !item.isSeparator) {
                _selectedIndex = idx;
                invalidateVisual();
                return;
            }
        }
    }

    /// Select previous selectable item
    void selectPreviousItem() {
        for (int i = 1; i <= cast(int)_children.length; i++) {
            int idx = _selectedIndex - i;
            if (idx < 0) idx += cast(int)_children.length;
            auto item = cast(MenuItem)_children[idx];
            if (item !is null && item.enabled && !item.isSeparator) {
                _selectedIndex = idx;
                invalidateVisual();
                return;
            }
        }
    }

    /// Activate currently selected item
    void activateSelected() {
        if (auto item = getSelectedItem()) {
            if (item.hasSubmenu) {
                // TODO: Open submenu
            } else {
                item.activate();
                close();
            }
        }
    }

    /// Find item by accelerator key (first letter)
    MenuItem findItemByAccelerator(KeyCode keyCode) {
        char accel = keyCodeToChar(keyCode);
        if (accel == '\0') return null;

        foreach (child; _children) {
            auto item = cast(MenuItem)child;
            if (item !is null && item.enabled && !item.isSeparator) {
                if (item.label.length > 0) {
                    char firstChar = cast(char)(item.label[0] | 0x20);  // Lowercase
                    if (firstChar == (accel | 0x20)) {
                        return item;
                    }
                }
            }
        }
        return null;
    }

    /// Convert keycode to character
    char keyCodeToChar(KeyCode keyCode) {
        if (keyCode >= KeyCode.a && keyCode <= KeyCode.z) {
            return cast(char)('a' + (keyCode - KeyCode.a));
        }
        return '\0';
    }

    override Size measureOverride(Size availableSize) {
        if (!_isOpen)
            return Size.zero;

        int maxWidth = 0;
        int totalHeight = 0;

        foreach (child; _children) {
            Size childSize = child.measure(availableSize);
            maxWidth = max(maxWidth, childSize.width);
            totalHeight += childSize.height;
        }

        return Size(maxWidth + _padding * 2, totalHeight + _padding * 2);
    }

    override void arrangeOverride(Size finalSize) {
        if (!_isOpen) return;

        int y = _popupPosition.y + _padding;

        foreach (child; _children) {
            int childHeight = child.desiredSize.height;
            child.arrange(Rect(
                _popupPosition.x + _padding,
                y,
                finalSize.width - _padding * 2,
                childHeight
            ));
            y += childHeight;
        }
    }

    override void renderOverride(RenderContext renderer) {
        if (!_isOpen) return;

        // Menu bounds
        Rect menuBounds = Rect(
            _popupPosition.x,
            _popupPosition.y,
            _desiredSize.width,
            _desiredSize.height
        );

        // Background
        renderer.fillRect(menuBounds, _backgroundColor);

        // Border
        renderer.drawRect(menuBounds, _borderColor, _borderWidth);

        // Render items with selection highlight
        foreach (idx, child; _children) {
            auto item = cast(MenuItem)child;
            if (item !is null && idx == _selectedIndex) {
                // Draw selection highlight
                renderer.fillRect(item.bounds, 0xFF404060);
            }
            child.render(renderer);
        }
    }
}

// ============================================================================
// Context Menu
// ============================================================================

/**
 * Popup context menu.
 *
 * Appears at cursor position and dismisses on click-away.
 */
class ContextMenu : Menu {
private:
    Widget _owner;

public:
    /// Create context menu
    this() {
        super();
    }

    /// Show at cursor position
    void showAt(Point position, Widget owner = null) {
        _owner = owner;
        open(position);
    }

    /// Handle click outside menu
    override Widget hitTestOverride(Point localPoint) {
        if (!_isOpen) return null;

        // Check if within menu bounds
        Rect menuBounds = Rect(
            _popupPosition.x,
            _popupPosition.y,
            _desiredSize.width,
            _desiredSize.height
        );

        if (menuBounds.contains(localPoint)) {
            // Hit test children
            foreach_reverse (child; _children) {
                auto childLocal = child.parentToLocal(localPoint);
                auto hit = child.hitTest(childLocal);
                if (hit !is null)
                    return hit;
            }
            return this;
        }

        // Click outside - close menu
        close();
        return null;
    }
}

// ============================================================================
// Menu Bar
// ============================================================================

/**
 * Horizontal menu bar at top of window.
 */
class MenuBar : Container {
    mixin EventHandlers;

private:
    int _activeMenuIndex = -1;
    Menu[] _menus;
    string[] _labels;

    // Appearance
    uint _backgroundColor = 0xFF303030;
    uint _textColor = 0xFFFFFFFF;
    uint _hoverColor = 0xFF404060;
    uint _activeColor = 0xFF505080;
    int _barHeight = 24;
    int _itemPadding = 12;

public:
    /// Menu bar height
    @property int barHeight() const { return _barHeight; }
    @property void barHeight(int value) {
        _barHeight = value;
        invalidateMeasure();
    }

    /// Create menu bar
    this() {
        // Default setup
    }

    /// Add menu with label
    void addMenu(string label, Menu menu) {
        _labels ~= label;
        _menus ~= menu;
        invalidateMeasure();
    }

    /// Close any open menus
    void closeMenus() {
        if (_activeMenuIndex >= 0 && _activeMenuIndex < _menus.length) {
            _menus[_activeMenuIndex].close();
        }
        _activeMenuIndex = -1;
        invalidateVisual();
    }

    /// Handle keyboard navigation
    bool handleKeyEvent(KeyEvent event) {
        if (!event.isPressed) return false;

        switch (event.keyCode) {
            case KeyCode.left:
                if (_activeMenuIndex > 0) {
                    closeMenus();
                    _activeMenuIndex--;
                    openActiveMenu();
                    return true;
                }
                break;

            case KeyCode.right:
                if (_activeMenuIndex < cast(int)_menus.length - 1) {
                    closeMenus();
                    _activeMenuIndex++;
                    openActiveMenu();
                    return true;
                }
                break;

            case KeyCode.escape:
                closeMenus();
                return true;

            default:
                // Forward to active menu
                if (_activeMenuIndex >= 0 && _activeMenuIndex < _menus.length) {
                    return _menus[_activeMenuIndex].handleKeyEvent(event);
                }
                break;
        }

        return false;
    }

protected:
    /// Open the active menu
    void openActiveMenu() {
        if (_activeMenuIndex < 0 || _activeMenuIndex >= _menus.length)
            return;

        // Calculate menu position
        int x = _bounds.x;
        foreach (i; 0 .. _activeMenuIndex) {
            x += cast(int)(_labels[i].length * 8) + _itemPadding * 2;
        }

        _menus[_activeMenuIndex].open(Point(x, _bounds.y + _barHeight));
        invalidateVisual();
    }

    override Size measureOverride(Size availableSize) {
        // Calculate total width of menu labels
        int totalWidth = 0;
        foreach (label; _labels) {
            totalWidth += cast(int)(label.length * 8) + _itemPadding * 2;
        }

        return Size(max(totalWidth, availableSize.width), _barHeight);
    }

    override void arrangeOverride(Size finalSize) {
        // No children to arrange in traditional sense
        // Menus are positioned when opened
    }

    override void renderOverride(RenderContext renderer) {
        // Background
        renderer.fillRect(_bounds, _backgroundColor);

        // Draw menu labels
        int x = _bounds.x;
        foreach (idx, label; _labels) {
            int labelWidth = cast(int)(label.length * 8) + _itemPadding * 2;
            Rect itemBounds = Rect(x, _bounds.y, labelWidth, _barHeight);

            // Highlight active/hovered item
            if (idx == _activeMenuIndex) {
                renderer.fillRect(itemBounds, _activeColor);
            }

            // Draw label
            Point labelPos = Point(x + _itemPadding, _bounds.y + 4);
            renderer.drawText(label, labelPos, _textColor);

            x += labelWidth;
        }

        // Render open menu
        if (_activeMenuIndex >= 0 && _activeMenuIndex < _menus.length) {
            _menus[_activeMenuIndex].render(renderer);
        }
    }

    override Widget hitTestOverride(Point localPoint) {
        // Check if in menu bar area
        if (localPoint.y >= _bounds.y && localPoint.y < _bounds.y + _barHeight) {
            // Find which menu label was clicked
            int x = _bounds.x;
            foreach (idx, label; _labels) {
                int labelWidth = cast(int)(label.length * 8) + _itemPadding * 2;
                if (localPoint.x >= x && localPoint.x < x + labelWidth) {
                    return this;
                }
                x += labelWidth;
            }
        }

        // Check if in open menu
        if (_activeMenuIndex >= 0 && _activeMenuIndex < _menus.length) {
            auto hit = _menus[_activeMenuIndex].hitTestOverride(localPoint);
            if (hit !is null)
                return hit;
        }

        return null;
    }

    bool handleMouseClick(MouseEvent event) {
        if (event.eventType != MouseEventType.buttonDown || event.button != MouseButton.left)
            return false;

        // Check if clicked on menu bar
        if (event.position.y >= _bounds.y && event.position.y < _bounds.y + _barHeight) {
            int x = _bounds.x;
            foreach (idx, label; _labels) {
                int labelWidth = cast(int)(label.length * 8) + _itemPadding * 2;
                if (event.position.x >= x && event.position.x < x + labelWidth) {
                    if (_activeMenuIndex == idx) {
                        closeMenus();
                    } else {
                        closeMenus();
                        _activeMenuIndex = cast(int)idx;
                        openActiveMenu();
                    }
                    return true;
                }
                x += labelWidth;
            }
        }

        return false;
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

unittest {
    // Test MenuItem creation
    auto item = new MenuItem("File", "Ctrl+O");
    assert(item.label == "File");
    assert(item.shortcut == "Ctrl+O");
    assert(item.enabled);
    assert(!item.isSeparator);
}

unittest {
    // Test separator creation
    auto sep = MenuItem.separator();
    assert(sep.isSeparator);
    assert(!sep.enabled);
}

unittest {
    // Test Menu
    auto menu = new Menu();
    menu.addItem(new MenuItem("New"));
    menu.addItem(new MenuItem("Open"));
    menu.addSeparator();
    menu.addItem(new MenuItem("Exit"));
    assert(!menu.isOpen);
}

unittest {
    // Test ContextMenu
    auto ctx = new ContextMenu();
    ctx.addItem(new MenuItem("Copy"));
    ctx.addItem(new MenuItem("Paste"));
    assert(!ctx.isOpen);
}

unittest {
    // Test MenuBar
    auto bar = new MenuBar();
    auto fileMenu = new Menu();
    fileMenu.addItem(new MenuItem("New"));
    bar.addMenu("File", fileMenu);
    assert(bar.barHeight == 24);
}
