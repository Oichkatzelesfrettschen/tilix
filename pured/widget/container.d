/**
 * Container Widget
 *
 * Base class for widgets that contain other widgets.
 * Provides child management, layout delegation, and event routing.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.container;

version (PURE_D_BACKEND):

import pured.widget.base;
import std.algorithm : remove, countUntil, map, max, sum;
import std.array : array;

/**
 * Container base class.
 *
 * Manages a collection of child widgets and provides infrastructure
 * for layout and event propagation.
 */
class Container : Widget {
protected:
    Widget[] _children;

public:
    // === Child Management ===

    /**
     * Add a child widget.
     */
    void addChild(Widget child) {
        if (child is null) return;
        if (child._parent !is null) {
            // Parent must be a Container to have children
            if (auto container = cast(Container)child._parent) {
                container.removeChild(child);
            }
        }
        child._parent = this;
        _children ~= child;
        onChildAdded(child);
        invalidateMeasure();
    }

    /**
     * Remove a child widget.
     */
    void removeChild(Widget child) {
        if (child is null) return;
        auto idx = _children.countUntil(child);
        if (idx >= 0) {
            child._parent = null;
            _children = _children.remove(idx);
            onChildRemoved(child);
            invalidateMeasure();
        }
    }

    /**
     * Remove all children.
     */
    void clearChildren() {
        foreach (child; _children) {
            child._parent = null;
            onChildRemoved(child);
        }
        _children = [];
        invalidateMeasure();
    }

    /**
     * Get child at index.
     */
    Widget childAt(size_t index) {
        if (index < _children.length)
            return _children[index];
        return null;
    }

    /**
     * Number of children.
     */
    @property size_t childCount() const {
        return _children.length;
    }

    /**
     * Iterate over children.
     */
    int opApply(scope int delegate(Widget) dg) {
        foreach (child; _children) {
            if (auto result = dg(child))
                return result;
        }
        return 0;
    }

    /**
     * Iterate over children with index.
     */
    int opApply(scope int delegate(size_t, Widget) dg) {
        foreach (i, child; _children) {
            if (auto result = dg(i, child))
                return result;
        }
        return 0;
    }

protected:
    // === Overridable Child Events ===

    /**
     * Called when a child is added.
     */
    void onChildAdded(Widget child) {
        // Override in subclass
    }

    /**
     * Called when a child is removed.
     */
    void onChildRemoved(Widget child) {
        // Override in subclass
    }

    // === Layout Override ===

    override Size measureOverride(Size availableSize) {
        // Default: measure all children and return max size
        int maxWidth = 0;
        int maxHeight = 0;

        foreach (child; _children) {
            if (child.visibility == Visibility.collapsed) continue;
            auto childSize = child.measure(availableSize);
            maxWidth = max(maxWidth, childSize.width);
            maxHeight = max(maxHeight, childSize.height);
        }

        return Size(maxWidth, maxHeight);
    }

    override void arrangeOverride(Size finalSize) {
        // Default: arrange all children at full bounds
        foreach (child; _children) {
            if (child.visibility == Visibility.collapsed) continue;
            child.arrange(Rect(0, 0, finalSize.width, finalSize.height));
        }
    }

    override void renderOverride(RenderContext renderer) {
        // Render children back to front
        foreach (child; _children) {
            child.render(renderer);
        }
    }

    override Widget hitTestOverride(Point localPoint) {
        // Hit test children front to back (reverse order)
        foreach_reverse (child; _children) {
            auto childLocal = child.parentToLocal(localPoint);
            auto hit = child.hitTest(childLocal);
            if (hit !is null)
                return hit;
        }
        return this;
    }
}

/**
 * Panel with single child.
 *
 * Useful as a base for decorated containers (borders, backgrounds).
 */
class ContentControl : Widget {
protected:
    Widget _content;

public:
    @property Widget content() { return _content; }
    @property void content(Widget value) {
        if (_content !is null) {
            _content._parent = null;
        }
        _content = value;
        if (_content !is null) {
            _content._parent = this;
        }
        invalidateMeasure();
    }

protected:
    override Size measureOverride(Size availableSize) {
        if (_content is null || _content.visibility == Visibility.collapsed)
            return Size.zero;

        // Subtract padding for content
        Size contentAvailable = Size(
            max(0, availableSize.width - _padding.horizontalTotal),
            max(0, availableSize.height - _padding.verticalTotal)
        );

        auto contentSize = _content.measure(contentAvailable);

        return Size(
            contentSize.width + _padding.horizontalTotal,
            contentSize.height + _padding.verticalTotal
        );
    }

    override void arrangeOverride(Size finalSize) {
        if (_content is null || _content.visibility == Visibility.collapsed)
            return;

        Rect contentBounds = Rect(
            _padding.left,
            _padding.top,
            max(0, finalSize.width - _padding.horizontalTotal),
            max(0, finalSize.height - _padding.verticalTotal)
        );

        _content.arrange(contentBounds);
    }

    override void renderOverride(RenderContext renderer) {
        if (_content !is null) {
            _content.render(renderer);
        }
    }

    override Widget hitTestOverride(Point localPoint) {
        if (_content !is null) {
            auto contentLocal = _content.parentToLocal(localPoint);
            auto hit = _content.hitTest(contentLocal);
            if (hit !is null)
                return hit;
        }
        return this;
    }
}

/**
 * Stack panel - arranges children in a line.
 */
class StackPanel : Container {
private:
    Orientation _orientation = Orientation.vertical;
    int _spacing = 0;

public:
    @property Orientation orientation() const { return _orientation; }
    @property void orientation(Orientation value) {
        if (_orientation != value) {
            _orientation = value;
            invalidateMeasure();
        }
    }

    @property int spacing() const { return _spacing; }
    @property void spacing(int value) {
        if (_spacing != value) {
            _spacing = value;
            invalidateMeasure();
        }
    }

protected:
    override Size measureOverride(Size availableSize) {
        int totalMain = 0;
        int maxCross = 0;
        bool first = true;

        foreach (child; _children) {
            if (child.visibility == Visibility.collapsed) continue;

            auto childSize = child.measure(availableSize);

            if (_orientation == Orientation.vertical) {
                if (!first) totalMain += _spacing;
                totalMain += childSize.height;
                maxCross = max(maxCross, childSize.width);
            } else {
                if (!first) totalMain += _spacing;
                totalMain += childSize.width;
                maxCross = max(maxCross, childSize.height);
            }
            first = false;
        }

        if (_orientation == Orientation.vertical)
            return Size(maxCross, totalMain);
        else
            return Size(totalMain, maxCross);
    }

    override void arrangeOverride(Size finalSize) {
        int offset = 0;

        foreach (child; _children) {
            if (child.visibility == Visibility.collapsed) continue;

            if (_orientation == Orientation.vertical) {
                child.arrange(Rect(0, offset, finalSize.width, child.desiredSize.height));
                offset += child.desiredSize.height + _spacing;
            } else {
                child.arrange(Rect(offset, 0, child.desiredSize.width, finalSize.height));
                offset += child.desiredSize.width + _spacing;
            }
        }
    }
}

/**
 * Orientation for linear layouts.
 */
enum Orientation {
    horizontal,
    vertical,
}

/**
 * Split container - divides space between two children.
 *
 * Used for terminal split panes.
 */
class SplitContainer : Container {
private:
    Orientation _orientation = Orientation.horizontal;
    float _splitRatio = 0.5f;
    int _splitterSize = 4;
    bool _draggingSplitter;

public:
    @property Orientation orientation() const { return _orientation; }
    @property void orientation(Orientation value) {
        if (_orientation != value) {
            _orientation = value;
            invalidateArrange();
        }
    }

    @property float splitRatio() const { return _splitRatio; }
    @property void splitRatio(float value) {
        value = value < 0.1f ? 0.1f : (value > 0.9f ? 0.9f : value);
        if (_splitRatio != value) {
            _splitRatio = value;
            invalidateArrange();
        }
    }

    @property int splitterSize() const { return _splitterSize; }
    @property void splitterSize(int value) {
        if (_splitterSize != value) {
            _splitterSize = value;
            invalidateArrange();
        }
    }

    /// First child (left or top)
    @property Widget first() {
        return _children.length > 0 ? _children[0] : null;
    }

    /// Second child (right or bottom)
    @property Widget second() {
        return _children.length > 1 ? _children[1] : null;
    }

    /// Set first child
    void setFirst(Widget child) {
        if (_children.length > 0) {
            removeChild(_children[0]);
        }
        if (child !is null) {
            if (_children.length == 0) {
                addChild(child);
            } else {
                // Insert at beginning
                child._parent = this;
                _children = [child] ~ _children;
                onChildAdded(child);
                invalidateMeasure();
            }
        }
    }

    /// Set second child
    void setSecond(Widget child) {
        while (_children.length > 1) {
            removeChild(_children[$ - 1]);
        }
        if (child !is null) {
            addChild(child);
        }
    }

    /// Get splitter bounds
    Rect splitterBounds() const {
        if (_orientation == Orientation.horizontal) {
            int x = cast(int)(_bounds.width * _splitRatio) - _splitterSize / 2;
            return Rect(x, 0, _splitterSize, _bounds.height);
        } else {
            int y = cast(int)(_bounds.height * _splitRatio) - _splitterSize / 2;
            return Rect(0, y, _bounds.width, _splitterSize);
        }
    }

protected:
    override Size measureOverride(Size availableSize) {
        int totalMain = 0;
        int maxCross = 0;

        foreach (child; _children) {
            if (child.visibility == Visibility.collapsed) continue;

            auto childSize = child.measure(availableSize);

            if (_orientation == Orientation.horizontal) {
                totalMain += childSize.width;
                maxCross = max(maxCross, childSize.height);
            } else {
                totalMain += childSize.height;
                maxCross = max(maxCross, childSize.width);
            }
        }

        totalMain += _splitterSize;

        if (_orientation == Orientation.horizontal)
            return Size(totalMain, maxCross);
        else
            return Size(maxCross, totalMain);
    }

    override void arrangeOverride(Size finalSize) {
        if (_children.length == 0) return;

        if (_orientation == Orientation.horizontal) {
            int splitX = cast(int)(finalSize.width * _splitRatio);
            int firstWidth = splitX - _splitterSize / 2;
            int secondX = splitX + _splitterSize / 2;
            int secondWidth = finalSize.width - secondX;

            if (_children.length > 0)
                _children[0].arrange(Rect(0, 0, firstWidth, finalSize.height));
            if (_children.length > 1)
                _children[1].arrange(Rect(secondX, 0, secondWidth, finalSize.height));
        } else {
            int splitY = cast(int)(finalSize.height * _splitRatio);
            int firstHeight = splitY - _splitterSize / 2;
            int secondY = splitY + _splitterSize / 2;
            int secondHeight = finalSize.height - secondY;

            if (_children.length > 0)
                _children[0].arrange(Rect(0, 0, finalSize.width, firstHeight));
            if (_children.length > 1)
                _children[1].arrange(Rect(0, secondY, finalSize.width, secondHeight));
        }
    }

    override void renderOverride(RenderContext renderer) {
        // Render children
        super.renderOverride(renderer);

        // Render splitter
        auto sb = splitterBounds();
        renderer.fillRect(sb, 0xFF404040);  // Dark gray splitter
    }
}

/**
 * Tab container - shows one child at a time with tab bar.
 */
class TabContainer : Container {
private:
    int _selectedIndex = 0;
    int _tabBarHeight = 28;
    string[] _tabTitles;

public:
    @property int selectedIndex() const { return _selectedIndex; }
    @property void selectedIndex(int value) {
        if (value >= 0 && value < cast(int)_children.length) {
            _selectedIndex = value;
            invalidateVisual();
        }
    }

    @property Widget selectedChild() {
        if (_selectedIndex >= 0 && _selectedIndex < cast(int)_children.length)
            return _children[_selectedIndex];
        return null;
    }

    @property int tabBarHeight() const { return _tabBarHeight; }
    @property void tabBarHeight(int value) {
        if (_tabBarHeight != value) {
            _tabBarHeight = value;
            invalidateArrange();
        }
    }

    /**
     * Add tab with title.
     */
    void addTab(Widget content, string title) {
        addChild(content);
        _tabTitles ~= title;
        if (_children.length == 1)
            _selectedIndex = 0;
    }

    /**
     * Remove tab by index.
     */
    void removeTab(int index) {
        if (index >= 0 && index < cast(int)_children.length) {
            removeChild(_children[index]);
            if (index < _tabTitles.length)
                _tabTitles = _tabTitles[0 .. index] ~ _tabTitles[index + 1 .. $];
            if (_selectedIndex >= cast(int)_children.length)
                _selectedIndex = cast(int)_children.length - 1;
        }
    }

    /**
     * Get tab title.
     */
    string tabTitle(int index) const {
        if (index >= 0 && index < cast(int)_tabTitles.length)
            return _tabTitles[index];
        return "";
    }

    /**
     * Set tab title.
     */
    void setTabTitle(int index, string title) {
        if (index >= 0 && index < cast(int)_tabTitles.length) {
            _tabTitles[index] = title;
            invalidateVisual();
        }
    }

protected:
    override Size measureOverride(Size availableSize) {
        // Measure content area
        Size contentAvailable = Size(
            availableSize.width,
            max(0, availableSize.height - _tabBarHeight)
        );

        int maxWidth = 0;
        int maxHeight = 0;

        foreach (child; _children) {
            if (child.visibility == Visibility.collapsed) continue;
            auto childSize = child.measure(contentAvailable);
            maxWidth = max(maxWidth, childSize.width);
            maxHeight = max(maxHeight, childSize.height);
        }

        return Size(maxWidth, maxHeight + _tabBarHeight);
    }

    override void arrangeOverride(Size finalSize) {
        // Content area below tab bar
        Rect contentBounds = Rect(
            0, _tabBarHeight,
            finalSize.width,
            max(0, finalSize.height - _tabBarHeight)
        );

        // Only arrange selected child
        foreach (i, child; _children) {
            if (i == _selectedIndex) {
                child.arrange(contentBounds);
            } else {
                child.arrange(Rect.zero);
            }
        }
    }

    override void renderOverride(RenderContext renderer) {
        // Render tab bar background
        renderer.fillRect(Rect(0, 0, _bounds.width, _tabBarHeight), 0xFF303030);

        // Render tabs
        int tabX = 0;
        int tabWidth = 120;  // Fixed width for now

        foreach (i, title; _tabTitles) {
            bool selected = (i == _selectedIndex);
            uint bgColor = selected ? 0xFF404040 : 0xFF303030;
            uint textColor = selected ? 0xFFFFFFFF : 0xFFAAAAAA;

            renderer.fillRect(Rect(tabX, 0, tabWidth, _tabBarHeight), bgColor);
            renderer.drawText(title, Point(tabX + 8, 6), textColor);

            // Tab separator
            renderer.fillRect(Rect(tabX + tabWidth - 1, 0, 1, _tabBarHeight), 0xFF202020);

            tabX += tabWidth;
        }

        // Render selected child only
        auto selected = selectedChild;
        if (selected !is null) {
            selected.render(renderer);
        }
    }

    override Widget hitTestOverride(Point localPoint) {
        // Check tab bar
        if (localPoint.y < _tabBarHeight) {
            return this;  // Tab bar hits return container
        }

        // Check content
        auto selected = selectedChild;
        if (selected !is null) {
            auto contentLocal = selected.parentToLocal(localPoint);
            auto hit = selected.hitTest(contentLocal);
            if (hit !is null)
                return hit;
        }

        return this;
    }
}
