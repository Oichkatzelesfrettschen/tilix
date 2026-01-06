/**
 * Scrollbar Widget
 *
 * Vertical and horizontal scrollbar controls.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.scrollbar;

version (PURE_D_BACKEND):

import pured.widget.base;
import pured.widget.container : Orientation;
import pured.util.signal;
import std.algorithm : max, min, clamp;

/**
 * Scrollbar widget.
 *
 * Provides visual indication of scroll position and
 * allows direct manipulation via drag.
 */
class Scrollbar : Widget {
private:
    Orientation _orientation = Orientation.vertical;
    float _minimum = 0;
    float _maximum = 100;
    float _value = 0;
    float _viewportSize = 10;  // Size of visible portion
    int _trackSize = 14;       // Width (vertical) or height (horizontal)

    // Interaction state
    bool _isDragging;
    float _dragStartValue;
    int _dragStartPos;

    // Colors
    uint _trackColor = 0xFF202020;
    uint _thumbColor = 0xFF606060;
    uint _thumbHoverColor = 0xFF808080;
    uint _thumbDragColor = 0xFF909090;
    bool _isHovered;

public:
    // === Signals ===

    Signal!float valueChanged;
    Signal!() scrollStarted;
    Signal!() scrollEnded;

    // === Properties ===

    @property Orientation orientation() const { return _orientation; }
    @property void orientation(Orientation value) {
        if (_orientation != value) {
            _orientation = value;
            invalidateMeasure();
        }
    }

    @property float minimum() const { return _minimum; }
    @property void minimum(float value) {
        if (_minimum != value) {
            _minimum = value;
            _value = clamp(_value, _minimum, _maximum);
            invalidateVisual();
        }
    }

    @property float maximum() const { return _maximum; }
    @property void maximum(float value) {
        if (_maximum != value) {
            _maximum = value;
            _value = clamp(_value, _minimum, _maximum);
            invalidateVisual();
        }
    }

    @property float value() const { return _value; }
    @property void value(float v) {
        v = clamp(v, _minimum, _maximum);
        if (_value != v) {
            _value = v;
            valueChanged.emit(_value);
            invalidateVisual();
        }
    }

    @property float viewportSize() const { return _viewportSize; }
    @property void viewportSize(float value) {
        if (_viewportSize != value) {
            _viewportSize = max(1, value);
            invalidateVisual();
        }
    }

    @property int trackSize() const { return _trackSize; }
    @property void trackSize(int value) {
        if (_trackSize != value) {
            _trackSize = value;
            invalidateMeasure();
        }
    }

    /// Track color
    @property uint trackColor() const { return _trackColor; }
    @property void trackColor(uint value) {
        _trackColor = value;
        invalidateVisual();
    }

    /// Thumb color
    @property uint thumbColor() const { return _thumbColor; }
    @property void thumbColor(uint value) {
        _thumbColor = value;
        invalidateVisual();
    }

    // === Scroll Operations ===

    /**
     * Scroll by a small amount (line).
     */
    void smallIncrement() {
        value = _value + smallStep();
    }

    void smallDecrement() {
        value = _value - smallStep();
    }

    /**
     * Scroll by a large amount (page).
     */
    void largeIncrement() {
        value = _value + largeStep();
    }

    void largeDecrement() {
        value = _value - largeStep();
    }

    /**
     * Scroll to beginning.
     */
    void scrollToStart() {
        value = _minimum;
    }

    /**
     * Scroll to end.
     */
    void scrollToEnd() {
        value = _maximum;
    }

    // === Input Handling ===

    /**
     * Handle mouse button.
     */
    void handleMouseDown(int x, int y) {
        auto thumbRect = getThumbRect();

        if (thumbRect.contains(x, y)) {
            // Start dragging thumb
            _isDragging = true;
            _dragStartValue = _value;
            _dragStartPos = _orientation == Orientation.vertical ? y : x;
            scrollStarted.emit();
        } else {
            // Click on track - page scroll
            if (_orientation == Orientation.vertical) {
                if (y < thumbRect.y)
                    largeDecrement();
                else
                    largeIncrement();
            } else {
                if (x < thumbRect.x)
                    largeDecrement();
                else
                    largeIncrement();
            }
        }
    }

    void handleMouseUp(int x, int y) {
        if (_isDragging) {
            _isDragging = false;
            scrollEnded.emit();
        }
    }

    void handleMouseMove(int x, int y) {
        if (_isDragging) {
            int currentPos = _orientation == Orientation.vertical ? y : x;
            int delta = currentPos - _dragStartPos;

            // Convert pixel delta to value delta
            int trackLength = getTrackLength();
            int thumbLength = getThumbLength();
            int availableTrack = trackLength - thumbLength;

            if (availableTrack > 0) {
                float range = _maximum - _minimum;
                float valueDelta = (delta * range) / availableTrack;
                value = _dragStartValue + valueDelta;
            }
        }

        // Update hover state
        auto thumbRect = getThumbRect();
        bool wasHovered = _isHovered;
        _isHovered = thumbRect.contains(x, y);
        if (wasHovered != _isHovered) {
            invalidateVisual();
        }
    }

    void handleMouseLeave() {
        if (_isHovered) {
            _isHovered = false;
            invalidateVisual();
        }
    }

    /**
     * Handle scroll wheel.
     */
    void handleScroll(float delta) {
        if (delta > 0)
            smallDecrement();
        else
            smallIncrement();
    }

protected:
    override Size measureOverride(Size availableSize) {
        if (_orientation == Orientation.vertical) {
            return Size(_trackSize, availableSize.height);
        } else {
            return Size(availableSize.width, _trackSize);
        }
    }

    override void renderOverride(RenderContext ctx) {
        // Draw track
        ctx.fillRect(Rect(0, 0, _bounds.width, _bounds.height), _trackColor);

        // Draw thumb
        auto thumbRect = getThumbRect();
        uint color = _isDragging ? _thumbDragColor :
                     _isHovered ? _thumbHoverColor : _thumbColor;

        // Inset thumb slightly from track edges
        int inset = 2;
        if (_orientation == Orientation.vertical) {
            thumbRect = Rect(inset, thumbRect.y, _bounds.width - inset * 2, thumbRect.height);
        } else {
            thumbRect = Rect(thumbRect.x, inset, thumbRect.width, _bounds.height - inset * 2);
        }

        ctx.fillRect(thumbRect, color);
    }

    override Widget hitTestOverride(Point localPoint) {
        // Always return self for mouse handling
        return this;
    }

private:
    float smallStep() const {
        // 1/10th of viewport or 1, whichever is larger
        return max(1, _viewportSize / 10);
    }

    float largeStep() const {
        // Nearly full viewport
        return max(1, _viewportSize * 0.9f);
    }

    int getTrackLength() const {
        return _orientation == Orientation.vertical ? _bounds.height : _bounds.width;
    }

    int getThumbLength() const {
        float range = _maximum - _minimum + _viewportSize;
        if (range <= 0) return getTrackLength();

        float ratio = _viewportSize / range;
        int length = cast(int)(getTrackLength() * ratio);
        return max(length, 20);  // Minimum thumb size
    }

    Rect getThumbRect() const {
        int trackLen = getTrackLength();
        int thumbLen = getThumbLength();
        int availableTrack = trackLen - thumbLen;

        float range = _maximum - _minimum;
        float ratio = range > 0 ? (_value - _minimum) / range : 0;
        int thumbPos = cast(int)(availableTrack * ratio);

        if (_orientation == Orientation.vertical) {
            return Rect(0, thumbPos, _bounds.width, thumbLen);
        } else {
            return Rect(thumbPos, 0, thumbLen, _bounds.height);
        }
    }
}

/**
 * Scroll viewer - container with scrollbars.
 *
 * Wraps content and provides scrollbar controls when
 * content exceeds visible area.
 */
class ScrollViewer : Widget {
private:
    Widget _content;
    Scrollbar _verticalBar;
    Scrollbar _horizontalBar;
    bool _verticalVisible = true;
    bool _horizontalVisible = false;
    int _scrollbarSize = 14;

    // Scroll policy
    ScrollBarVisibility _verticalPolicy = ScrollBarVisibility.auto_;
    ScrollBarVisibility _horizontalPolicy = ScrollBarVisibility.auto_;

public:
    this() {
        _verticalBar = new Scrollbar();
        _verticalBar.orientation = Orientation.vertical;
        _verticalBar.valueChanged.connect(&onVerticalScroll);

        _horizontalBar = new Scrollbar();
        _horizontalBar.orientation = Orientation.horizontal;
        _horizontalBar.valueChanged.connect(&onHorizontalScroll);
    }

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

    @property ScrollBarVisibility verticalScrollBarVisibility() const { return _verticalPolicy; }
    @property void verticalScrollBarVisibility(ScrollBarVisibility value) {
        _verticalPolicy = value;
        invalidateMeasure();
    }

    @property ScrollBarVisibility horizontalScrollBarVisibility() const { return _horizontalPolicy; }
    @property void horizontalScrollBarVisibility(ScrollBarVisibility value) {
        _horizontalPolicy = value;
        invalidateMeasure();
    }

    /// Vertical scroll offset
    @property float verticalOffset() const { return _verticalBar.value; }
    @property void verticalOffset(float value) { _verticalBar.value = value; }

    /// Horizontal scroll offset
    @property float horizontalOffset() const { return _horizontalBar.value; }
    @property void horizontalOffset(float value) { _horizontalBar.value = value; }

    /**
     * Scroll to make point visible.
     */
    void scrollToVisible(int x, int y) {
        // Adjust vertical offset
        if (y < _verticalBar.value) {
            _verticalBar.value = y;
        } else if (y >= _verticalBar.value + _bounds.height - _scrollbarSize) {
            _verticalBar.value = y - _bounds.height + _scrollbarSize + 1;
        }

        // Adjust horizontal offset
        if (x < _horizontalBar.value) {
            _horizontalBar.value = x;
        } else if (x >= _horizontalBar.value + _bounds.width - _scrollbarSize) {
            _horizontalBar.value = x - _bounds.width + _scrollbarSize + 1;
        }
    }

protected:
    override Size measureOverride(Size availableSize) {
        if (_content is null) return Size.zero;

        // Measure content with infinite size
        auto contentSize = _content.measure(Size.infinite);

        // Determine scrollbar visibility
        updateScrollbarVisibility(availableSize, contentSize);

        return availableSize;
    }

    override void arrangeOverride(Size finalSize) {
        if (_content is null) return;

        int contentWidth = finalSize.width;
        int contentHeight = finalSize.height;

        // Adjust for scrollbars
        if (_verticalVisible) contentWidth -= _scrollbarSize;
        if (_horizontalVisible) contentHeight -= _scrollbarSize;

        // Arrange content with offset
        auto contentSize = _content.desiredSize;
        int scrollX = cast(int)_horizontalBar.value;
        int scrollY = cast(int)_verticalBar.value;

        _content.arrange(Rect(-scrollX, -scrollY, contentSize.width, contentSize.height));

        // Update scrollbar ranges
        _verticalBar.maximum = max(0, contentSize.height - contentHeight);
        _verticalBar.viewportSize = contentHeight;

        _horizontalBar.maximum = max(0, contentSize.width - contentWidth);
        _horizontalBar.viewportSize = contentWidth;

        // Arrange scrollbars
        if (_verticalVisible) {
            _verticalBar.arrange(Rect(
                contentWidth, 0,
                _scrollbarSize, contentHeight
            ));
        }

        if (_horizontalVisible) {
            _horizontalBar.arrange(Rect(
                0, contentHeight,
                contentWidth, _scrollbarSize
            ));
        }
    }

    override void renderOverride(RenderContext ctx) {
        // Clip to viewport
        Rect viewport = Rect(0, 0,
            _bounds.width - (_verticalVisible ? _scrollbarSize : 0),
            _bounds.height - (_horizontalVisible ? _scrollbarSize : 0)
        );

        ctx.pushClip(viewport);
        if (_content !is null) {
            _content.render(ctx);
        }
        ctx.popClip();

        // Render scrollbars
        if (_verticalVisible) {
            _verticalBar.render(ctx);
        }
        if (_horizontalVisible) {
            _horizontalBar.render(ctx);
        }

        // Corner square if both scrollbars visible
        if (_verticalVisible && _horizontalVisible) {
            ctx.fillRect(Rect(
                _bounds.width - _scrollbarSize,
                _bounds.height - _scrollbarSize,
                _scrollbarSize, _scrollbarSize
            ), _verticalBar.trackColor);
        }
    }

private:
    void updateScrollbarVisibility(Size availableSize, Size contentSize) {
        final switch (_verticalPolicy) {
            case ScrollBarVisibility.disabled:
            case ScrollBarVisibility.hidden:
                _verticalVisible = false;
                break;
            case ScrollBarVisibility.visible:
                _verticalVisible = true;
                break;
            case ScrollBarVisibility.auto_:
                _verticalVisible = contentSize.height > availableSize.height;
                break;
        }

        final switch (_horizontalPolicy) {
            case ScrollBarVisibility.disabled:
            case ScrollBarVisibility.hidden:
                _horizontalVisible = false;
                break;
            case ScrollBarVisibility.visible:
                _horizontalVisible = true;
                break;
            case ScrollBarVisibility.auto_:
                _horizontalVisible = contentSize.width > availableSize.width;
                break;
        }
    }

    void onVerticalScroll(float value) {
        invalidateVisual();
    }

    void onHorizontalScroll(float value) {
        invalidateVisual();
    }
}

/**
 * Scrollbar visibility policy.
 */
enum ScrollBarVisibility {
    disabled,  /// Never show, disable scrolling
    auto_,     /// Show when content exceeds viewport
    hidden,    /// Never show, but allow scrolling
    visible,   /// Always show
}
