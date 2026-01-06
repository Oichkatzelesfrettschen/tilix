/**
 * Terminal Scrollback and Viewport Management
 *
 * Manages the scrollback buffer viewport, allowing users to scroll
 * through terminal history while the terminal continues receiving output.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.terminal.scrollback;

version (PURE_D_BACKEND):

import std.algorithm : min, max, clamp;

/**
 * Viewport controller for terminal scrollback.
 *
 * The viewport determines which portion of the scrollback buffer
 * is currently visible. When scrolled back, new output accumulates
 * below the viewport; when at bottom, the viewport follows new output.
 */
class ScrollbackViewport {
private:
    int _viewportOffset;    // Lines scrolled back from bottom (0 = at bottom)
    int _scrollbackLines;   // Total lines in scrollback (above visible area)
    int _visibleRows;       // Number of visible rows in terminal
    int _maxScrollback;     // Maximum scrollback buffer size

    // Smooth scrolling state
    float _targetOffset;
    float _currentOffset;
    bool _animating;
    float _scrollSpeed = 0.3f;  // Animation speed factor

public:
    /**
     * Create scrollback viewport.
     *
     * Params:
     *   visibleRows = Number of visible terminal rows
     *   maxScrollback = Maximum scrollback buffer size (lines)
     */
    this(int visibleRows, int maxScrollback = 10000) {
        _visibleRows = visibleRows;
        _maxScrollback = maxScrollback;
        _viewportOffset = 0;
        _scrollbackLines = 0;
        _targetOffset = 0;
        _currentOffset = 0;
    }

    /**
     * Notify that new lines were added to scrollback.
     *
     * Params:
     *   count = Number of lines added
     */
    void linesAdded(int count) {
        _scrollbackLines = min(_scrollbackLines + count, _maxScrollback);

        // If we're not at bottom, increase offset to maintain position
        if (_viewportOffset > 0) {
            _viewportOffset = min(_viewportOffset + count, _scrollbackLines);
            _targetOffset = _viewportOffset;
            _currentOffset = _viewportOffset;
        }
    }

    /**
     * Scroll by a number of lines.
     *
     * Params:
     *   delta = Lines to scroll (positive = up/back, negative = down/forward)
     *   animate = Whether to animate the scroll
     */
    void scroll(int delta, bool animate = false) {
        int newOffset = clamp(_viewportOffset + delta, 0, _scrollbackLines);

        if (animate) {
            _targetOffset = newOffset;
            _animating = true;
        } else {
            _viewportOffset = newOffset;
            _targetOffset = newOffset;
            _currentOffset = newOffset;
        }
    }

    /**
     * Scroll by pages.
     *
     * Params:
     *   pages = Pages to scroll (positive = up, negative = down)
     */
    void scrollPages(int pages) {
        scroll(pages * (_visibleRows - 1));  // Keep 1 line overlap
    }

    /**
     * Scroll to absolute position.
     *
     * Params:
     *   offset = Target offset from bottom
     *   animate = Whether to animate
     */
    void scrollTo(int offset, bool animate = false) {
        offset = clamp(offset, 0, _scrollbackLines);

        if (animate) {
            _targetOffset = offset;
            _animating = true;
        } else {
            _viewportOffset = offset;
            _targetOffset = offset;
            _currentOffset = offset;
        }
    }

    /**
     * Scroll to top of scrollback.
     */
    void scrollToTop() {
        scrollTo(_scrollbackLines);
    }

    /**
     * Scroll to bottom (follow output).
     */
    void scrollToBottom() {
        scrollTo(0);
    }

    /**
     * Handle scroll wheel input.
     *
     * Params:
     *   delta = Wheel delta (positive = up)
     *   linesPerNotch = Lines per scroll notch
     *
     * Returns: true if scroll was consumed (not at limit)
     */
    bool handleScrollWheel(double delta, int linesPerNotch = 3) {
        if (delta == 0) return false;

        int lines = cast(int)(delta * linesPerNotch);
        int oldOffset = _viewportOffset;

        scroll(lines);

        return _viewportOffset != oldOffset;
    }

    /**
     * Update animation state.
     *
     * Params:
     *   dt = Delta time in seconds
     *
     * Returns: true if still animating
     */
    bool updateAnimation(float dt) {
        if (!_animating) return false;

        float diff = _targetOffset - _currentOffset;
        if (abs(diff) < 0.5f) {
            _currentOffset = _targetOffset;
            _viewportOffset = cast(int)_targetOffset;
            _animating = false;
            return false;
        }

        _currentOffset += diff * _scrollSpeed;
        _viewportOffset = cast(int)(_currentOffset + 0.5f);
        return true;
    }

    /**
     * Resize viewport (when terminal resizes).
     */
    void resize(int newVisibleRows) {
        _visibleRows = newVisibleRows;
        // Clamp offset in case scrollback shrunk
        _viewportOffset = clamp(_viewportOffset, 0, _scrollbackLines);
        _targetOffset = _viewportOffset;
        _currentOffset = _viewportOffset;
    }

    /**
     * Clear scrollback buffer.
     */
    void clear() {
        _scrollbackLines = 0;
        _viewportOffset = 0;
        _targetOffset = 0;
        _currentOffset = 0;
        _animating = false;
    }

    /**
     * Set maximum scrollback size.
     */
    void setMaxScrollback(int lines) {
        _maxScrollback = max(lines, 0);
        _scrollbackLines = min(_scrollbackLines, _maxScrollback);
        _viewportOffset = min(_viewportOffset, _scrollbackLines);
    }

    // === Properties ===

    /// Current viewport offset (lines from bottom)
    @property int offset() const { return _viewportOffset; }

    /// Total lines in scrollback
    @property int scrollbackLines() const { return _scrollbackLines; }

    /// Maximum scrollback size
    @property int maxScrollback() const { return _maxScrollback; }

    /// Whether viewport is at the bottom
    @property bool atBottom() const { return _viewportOffset == 0; }

    /// Whether viewport is at the top of scrollback
    @property bool atTop() const { return _viewportOffset >= _scrollbackLines; }

    /// Whether currently animating
    @property bool animating() const { return _animating; }

    /// Visible rows in viewport
    @property int visibleRows() const { return _visibleRows; }

    /**
     * Get scroll percentage (0.0 = bottom, 1.0 = top).
     */
    @property float scrollPercent() const {
        if (_scrollbackLines == 0) return 0.0f;
        return cast(float)_viewportOffset / _scrollbackLines;
    }

    /**
     * Get row in buffer for given screen row.
     *
     * Params:
     *   screenRow = Row on screen (0-based from top)
     *
     * Returns: Row in buffer (may be negative for scrollback)
     */
    int bufferRow(int screenRow) const {
        // Scrollback rows are numbered negatively
        // Screen row 0 with offset 10 shows buffer row -10
        return screenRow - _viewportOffset;
    }

    /**
     * Get screen row for given buffer row.
     *
     * Params:
     *   bufferRow = Row in buffer (negative for scrollback)
     *
     * Returns: Screen row, or -1 if not visible
     */
    int screenRow(int bufferRow) const {
        int row = bufferRow + _viewportOffset;
        if (row < 0 || row >= _visibleRows)
            return -1;
        return row;
    }

private:
    static float abs(float x) {
        return x < 0 ? -x : x;
    }
}

/**
 * Scrollbar state for rendering.
 */
struct ScrollbarState {
    float thumbPosition;  // 0.0 = top, 1.0 = bottom
    float thumbSize;      // Proportion of track (0.0 - 1.0)
    bool visible;         // Whether scrollbar should be shown
    bool hovered;         // Mouse is over scrollbar
    bool dragging;        // Currently dragging thumb
}

/**
 * Calculate scrollbar state from viewport.
 */
ScrollbarState calculateScrollbar(const ScrollbackViewport viewport) {
    ScrollbarState state;

    int totalLines = viewport.scrollbackLines + viewport.visibleRows;
    if (totalLines <= viewport.visibleRows) {
        state.visible = false;
        return state;
    }

    state.visible = true;
    state.thumbSize = cast(float)viewport.visibleRows / totalLines;
    state.thumbSize = max(state.thumbSize, 0.05f);  // Minimum thumb size

    // Position is inverted: scroll offset 0 = thumb at bottom
    state.thumbPosition = 1.0f - viewport.scrollPercent;

    return state;
}
