/**
 * Widget Base Class
 *
 * Foundation for all UI elements in the Pure D terminal.
 * Implements measure/arrange layout protocol and event handling.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.base;

version (PURE_D_BACKEND):

import std.algorithm : min, max;

/**
 * 2D point with integer coordinates.
 */
struct Point {
    int x = 0;
    int y = 0;

    Point opBinary(string op)(Point other) const if (op == "+") {
        return Point(x + other.x, y + other.y);
    }

    Point opBinary(string op)(Point other) const if (op == "-") {
        return Point(x - other.x, y - other.y);
    }
}

/**
 * 2D size with integer dimensions.
 */
struct Size {
    int width = 0;
    int height = 0;

    /// Zero size constant
    static immutable Size zero = Size(0, 0);

    /// Infinite size for unconstrained layout
    static immutable Size infinite = Size(int.max, int.max);

    bool opEquals(Size other) const {
        return width == other.width && height == other.height;
    }
}

/**
 * Rectangle with position and size.
 */
struct Rect {
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;

    /// Create from position and size
    static Rect fromPosSize(Point pos, Size size) {
        return Rect(pos.x, pos.y, size.width, size.height);
    }

    /// Create from two corners
    static Rect fromCorners(Point topLeft, Point bottomRight) {
        return Rect(
            topLeft.x,
            topLeft.y,
            bottomRight.x - topLeft.x,
            bottomRight.y - topLeft.y
        );
    }

    @property Point position() const { return Point(x, y); }
    @property Size size() const { return Size(width, height); }

    @property int left() const { return x; }
    @property int top() const { return y; }
    @property int right() const { return x + width; }
    @property int bottom() const { return y + height; }

    @property Point topLeft() const { return Point(x, y); }
    @property Point topRight() const { return Point(x + width, y); }
    @property Point bottomLeft() const { return Point(x, y + height); }
    @property Point bottomRight() const { return Point(x + width, y + height); }

    @property Point center() const {
        return Point(x + width / 2, y + height / 2);
    }

    /// Check if point is inside rectangle
    bool contains(Point p) const {
        return p.x >= x && p.x < x + width &&
               p.y >= y && p.y < y + height;
    }

    /// Check if point coordinates are inside
    bool contains(int px, int py) const {
        return px >= x && px < x + width &&
               py >= y && py < y + height;
    }

    /// Check if rectangles intersect
    bool intersects(Rect other) const {
        return !(other.right <= x || other.x >= right ||
                 other.bottom <= y || other.y >= bottom);
    }

    /// Get intersection of two rectangles
    Rect intersection(Rect other) const {
        int nx = max(x, other.x);
        int ny = max(y, other.y);
        int nr = min(right, other.right);
        int nb = min(bottom, other.bottom);

        if (nr <= nx || nb <= ny)
            return Rect.init;

        return Rect(nx, ny, nr - nx, nb - ny);
    }

    /// Expand rectangle by margin
    Rect expand(int margin) const {
        return Rect(x - margin, y - margin,
                   width + margin * 2, height + margin * 2);
    }

    /// Shrink rectangle by margin
    Rect shrink(int margin) const {
        return expand(-margin);
    }

    /// Check if rectangle is empty
    @property bool isEmpty() const {
        return width <= 0 || height <= 0;
    }

    /// Zero rectangle constant
    static immutable Rect zero = Rect(0, 0, 0, 0);
}

/**
 * Thickness for margins and padding.
 */
struct Thickness {
    int left = 0;
    int top = 0;
    int right = 0;
    int bottom = 0;

    /// Uniform thickness on all sides
    static Thickness uniform(int value) {
        return Thickness(value, value, value, value);
    }

    /// Symmetric thickness
    static Thickness symmetric(int horizontal, int vertical) {
        return Thickness(horizontal, vertical, horizontal, vertical);
    }

    @property int horizontalTotal() const { return left + right; }
    @property int verticalTotal() const { return top + bottom; }
}

/**
 * Horizontal alignment within container.
 */
enum HorizontalAlignment {
    left,
    center,
    right,
    stretch,
}

/**
 * Vertical alignment within container.
 */
enum VerticalAlignment {
    top,
    center,
    bottom,
    stretch,
}

/**
 * Widget visibility state.
 */
enum Visibility {
    visible,    /// Rendered and participates in layout
    hidden,     /// Not rendered but participates in layout
    collapsed,  /// Not rendered and does not participate in layout
}

/**
 * Base class for all widgets.
 *
 * Widgets follow a two-pass layout protocol:
 * 1. Measure: Widget reports desired size given available space
 * 2. Arrange: Widget positions itself within final bounds
 *
 * Events flow from root to leaf (capture) then leaf to root (bubble).
 */
class Widget {
protected:
    Widget _parent;
    Rect _bounds;
    Size _desiredSize;
    Thickness _margin;
    Thickness _padding;
    HorizontalAlignment _horizontalAlign = HorizontalAlignment.stretch;
    VerticalAlignment _verticalAlign = VerticalAlignment.stretch;
    Visibility _visibility = Visibility.visible;
    bool _enabled = true;
    bool _focused = false;
    bool _measureDirty = true;
    bool _arrangeDirty = true;
    string _name;

public:
    // === Properties ===

    /// Parent widget (null for root)
    @property Widget parent() { return _parent; }

    /// Widget bounds in parent coordinates
    @property Rect bounds() const { return _bounds; }

    /// Desired size from last measure pass
    @property Size desiredSize() const { return _desiredSize; }

    /// Margin around widget (outside bounds)
    @property Thickness margin() const { return _margin; }
    @property void margin(Thickness value) {
        if (_margin != value) {
            _margin = value;
            invalidateMeasure();
        }
    }

    /// Padding inside widget (inside bounds)
    @property Thickness padding() const { return _padding; }
    @property void padding(Thickness value) {
        if (_padding != value) {
            _padding = value;
            invalidateMeasure();
        }
    }

    @property HorizontalAlignment horizontalAlignment() const { return _horizontalAlign; }
    @property void horizontalAlignment(HorizontalAlignment value) {
        if (_horizontalAlign != value) {
            _horizontalAlign = value;
            invalidateArrange();
        }
    }

    @property VerticalAlignment verticalAlignment() const { return _verticalAlign; }
    @property void verticalAlignment(VerticalAlignment value) {
        if (_verticalAlign != value) {
            _verticalAlign = value;
            invalidateArrange();
        }
    }

    @property Visibility visibility() const { return _visibility; }
    @property void visibility(Visibility value) {
        if (_visibility != value) {
            _visibility = value;
            invalidateMeasure();
        }
    }

    @property bool isVisible() const {
        return _visibility == Visibility.visible;
    }

    @property bool enabled() const { return _enabled; }
    @property void enabled(bool value) { _enabled = value; }

    @property bool focused() const { return _focused; }

    @property string name() const { return _name; }
    @property void name(string value) { _name = value; }

    // === Layout Protocol ===

    /**
     * Measure the widget's desired size.
     *
     * Params:
     *   availableSize = Maximum available space
     *
     * Returns: Desired size (may be larger than available)
     */
    final Size measure(Size availableSize) {
        if (_visibility == Visibility.collapsed) {
            _desiredSize = Size.zero;
            return _desiredSize;
        }

        // Subtract margin from available space
        Size constrainedSize = Size(
            max(0, availableSize.width - _margin.horizontalTotal),
            max(0, availableSize.height - _margin.verticalTotal)
        );

        // Let subclass measure content
        _desiredSize = measureOverride(constrainedSize);

        // Add margin back
        _desiredSize = Size(
            _desiredSize.width + _margin.horizontalTotal,
            _desiredSize.height + _margin.verticalTotal
        );

        _measureDirty = false;
        return _desiredSize;
    }

    /**
     * Arrange the widget within final bounds.
     *
     * Params:
     *   finalRect = Allocated bounds in parent coordinates
     */
    final void arrange(Rect finalRect) {
        if (_visibility == Visibility.collapsed) {
            _bounds = Rect.zero;
            return;
        }

        // Apply margin
        Rect contentRect = Rect(
            finalRect.x + _margin.left,
            finalRect.y + _margin.top,
            max(0, finalRect.width - _margin.horizontalTotal),
            max(0, finalRect.height - _margin.verticalTotal)
        );

        // Apply alignment if not stretching
        Size arrangeSize = Size(contentRect.width, contentRect.height);

        if (_horizontalAlign != HorizontalAlignment.stretch) {
            arrangeSize.width = min(_desiredSize.width - _margin.horizontalTotal, contentRect.width);
        }
        if (_verticalAlign != VerticalAlignment.stretch) {
            arrangeSize.height = min(_desiredSize.height - _margin.verticalTotal, contentRect.height);
        }

        // Calculate position based on alignment
        int x = contentRect.x;
        int y = contentRect.y;

        final switch (_horizontalAlign) {
            case HorizontalAlignment.left:
            case HorizontalAlignment.stretch:
                break;
            case HorizontalAlignment.center:
                x += (contentRect.width - arrangeSize.width) / 2;
                break;
            case HorizontalAlignment.right:
                x += contentRect.width - arrangeSize.width;
                break;
        }

        final switch (_verticalAlign) {
            case VerticalAlignment.top:
            case VerticalAlignment.stretch:
                break;
            case VerticalAlignment.center:
                y += (contentRect.height - arrangeSize.height) / 2;
                break;
            case VerticalAlignment.bottom:
                y += contentRect.height - arrangeSize.height;
                break;
        }

        _bounds = Rect(x, y, arrangeSize.width, arrangeSize.height);

        // Let subclass arrange children
        arrangeOverride(Size(_bounds.width, _bounds.height));

        _arrangeDirty = false;
    }

    /**
     * Render the widget.
     *
     * Params:
     *   renderer = Rendering context
     */
    void render(RenderContext renderer) {
        if (_visibility != Visibility.visible) return;
        renderOverride(renderer);
    }

    // === Focus Management ===

    /**
     * Request focus for this widget.
     */
    bool focus() {
        if (!_enabled) return false;
        if (!canFocus()) return false;

        // Find root and request focus change
        auto root = findRoot();
        if (root !is null) {
            root.setFocusedWidget(this);
            return true;
        }
        return false;
    }

    /**
     * Check if widget can receive focus.
     */
    bool canFocus() const {
        return _enabled && _visibility == Visibility.visible;
    }

    // === Hit Testing ===

    /**
     * Find widget at point (in local coordinates).
     */
    Widget hitTest(Point localPoint) {
        if (_visibility != Visibility.visible) return null;
        if (!_bounds.contains(localPoint)) return null;
        return hitTestOverride(localPoint);
    }

    // === Coordinate Conversion ===

    /**
     * Convert point from local to parent coordinates.
     */
    Point localToParent(Point local) const {
        return Point(local.x + _bounds.x, local.y + _bounds.y);
    }

    /**
     * Convert point from parent to local coordinates.
     */
    Point parentToLocal(Point parent) const {
        return Point(parent.x - _bounds.x, parent.y - _bounds.y);
    }

    /**
     * Convert point to screen coordinates.
     */
    Point localToScreen(Point local) const {
        Point result = localToParent(local);
        // Walk up the parent chain
        Widget p = cast(Widget)_parent;  // Cast away const for iteration
        while (p !is null) {
            result = p.localToParent(result);
            p = p._parent;
        }
        return result;
    }

    // === Invalidation ===

    /**
     * Mark measure as needing recalculation.
     */
    void invalidateMeasure() {
        _measureDirty = true;
        _arrangeDirty = true;
        if (_parent !is null) {
            _parent.invalidateMeasure();
        }
    }

    /**
     * Mark arrange as needing recalculation.
     */
    void invalidateArrange() {
        _arrangeDirty = true;
        if (_parent !is null) {
            _parent.invalidateArrange();
        }
    }

    /**
     * Request visual refresh.
     */
    void invalidateVisual() {
        // Propagate to root for redraw scheduling
        if (_parent !is null) {
            _parent.invalidateVisual();
        }
    }

protected:
    // === Overridable Methods ===

    /**
     * Measure content size (override in subclass).
     *
     * Default returns zero (no content).
     */
    Size measureOverride(Size availableSize) {
        return Size.zero;
    }

    /**
     * Arrange content (override in subclass).
     *
     * Default does nothing.
     */
    void arrangeOverride(Size finalSize) {
        // Override in subclass
    }

    /**
     * Render content (override in subclass).
     */
    void renderOverride(RenderContext renderer) {
        // Override in subclass
    }

    /**
     * Hit test within bounds (override in subclass).
     *
     * Default returns self if point is within bounds.
     */
    Widget hitTestOverride(Point localPoint) {
        return this;
    }

    /**
     * Called when widget gains focus.
     */
    void onGotFocus() {
        _focused = true;
    }

    /**
     * Called when widget loses focus.
     */
    void onLostFocus() {
        _focused = false;
    }

    /**
     * Find root widget.
     */
    RootWidget findRoot() {
        Widget current = this;
        while (current._parent !is null) {
            current = current._parent;
        }
        return cast(RootWidget)current;
    }

    /**
     * Set focus (called by RootWidget).
     * Override in RootWidget to implement focus management.
     */
    protected void setFocusedWidget(Widget widget) {
        // Only RootWidget implements this
    }
}

/**
 * Placeholder for render context.
 * Will be implemented with OpenGL rendering.
 */
interface RenderContext {
    /// Fill rectangle with color
    void fillRect(Rect rect, uint color);

    /// Draw rectangle outline
    void drawRect(Rect rect, uint color, int lineWidth = 1);

    /// Draw text at position
    void drawText(string text, Point pos, uint color);

    /// Push clipping rectangle
    void pushClip(Rect clip);

    /// Pop clipping rectangle
    void popClip();

    /// Get current clip bounds
    Rect currentClip();
}

/**
 * Root widget - top of widget tree.
 *
 * Manages focus and provides root for coordinate transforms.
 */
class RootWidget : Widget {
private:
    Widget _focusedWidget;
    Size _windowSize;

public:
    this(int width, int height) {
        _windowSize = Size(width, height);
        _bounds = Rect(0, 0, width, height);
    }

    /// Currently focused widget
    @property Widget focusedWidget() { return _focusedWidget; }

    /// Window size
    @property Size windowSize() const { return _windowSize; }

    /**
     * Update window size (call on resize).
     */
    void setSize(int width, int height) {
        _windowSize = Size(width, height);
        _bounds = Rect(0, 0, width, height);
        invalidateMeasure();
    }

    /**
     * Perform full layout pass.
     */
    void layout() {
        measure(_windowSize);
        arrange(Rect(0, 0, _windowSize.width, _windowSize.height));
    }

    /**
     * Set focused widget (called by Widget.focus()).
     */
    protected override void setFocusedWidget(Widget widget) {
        if (_focusedWidget is widget) return;

        if (_focusedWidget !is null) {
            _focusedWidget.onLostFocus();
        }
        _focusedWidget = widget;
        if (_focusedWidget !is null) {
            _focusedWidget.onGotFocus();
        }
    }

protected:
    override RootWidget findRoot() {
        return this;
    }
}
