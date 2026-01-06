/**
 * Layout Strategies
 *
 * Advanced layout containers for complex UI arrangements.
 * Includes Grid, Dock, and flexible layouts.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.layout;

version (PURE_D_BACKEND):

import pured.widget.base;
import pured.widget.container;
import std.algorithm : max, min, sum, map, filter;
import std.array : array;

// ============================================================================
// Grid Layout
// ============================================================================

/**
 * Grid row/column size specification.
 */
struct GridLength {
    float value = 0;
    GridUnitType unitType = GridUnitType.auto_;

    /// Auto-size based on content
    static GridLength auto_() {
        return GridLength(0, GridUnitType.auto_);
    }

    /// Fixed pixel size
    static GridLength pixels(float px) {
        return GridLength(px, GridUnitType.pixel);
    }

    /// Star (proportional) size
    static GridLength star(float weight = 1.0f) {
        return GridLength(weight, GridUnitType.star);
    }

    @property bool isAuto() const { return unitType == GridUnitType.auto_; }
    @property bool isPixel() const { return unitType == GridUnitType.pixel; }
    @property bool isStar() const { return unitType == GridUnitType.star; }
}

/**
 * Grid size unit types.
 */
enum GridUnitType {
    auto_,  /// Size to content
    pixel,  /// Fixed pixel size
    star,   /// Proportional (remaining space)
}

/**
 * Grid layout container.
 *
 * Arranges children in a grid with configurable row/column sizes.
 */
class Grid : Container {
private:
    GridLength[] _columnDefs;
    GridLength[] _rowDefs;
    int[Widget] _childColumn;
    int[Widget] _childRow;
    int[Widget] _childColSpan;
    int[Widget] _childRowSpan;
    int _columnGap = 0;
    int _rowGap = 0;

    // Computed during layout
    int[] _columnWidths;
    int[] _rowHeights;

public:
    /// Number of columns
    @property size_t columnCount() const { return _columnDefs.length; }

    /// Number of rows
    @property size_t rowCount() const { return _rowDefs.length; }

    /// Gap between columns
    @property int columnGap() const { return _columnGap; }
    @property void columnGap(int value) {
        if (_columnGap != value) {
            _columnGap = value;
            invalidateMeasure();
        }
    }

    /// Gap between rows
    @property int rowGap() const { return _rowGap; }
    @property void rowGap(int value) {
        if (_rowGap != value) {
            _rowGap = value;
            invalidateMeasure();
        }
    }

    /**
     * Define columns.
     */
    void setColumns(GridLength[] cols...) {
        _columnDefs = cols.dup;
        invalidateMeasure();
    }

    /**
     * Define rows.
     */
    void setRows(GridLength[] rows...) {
        _rowDefs = rows.dup;
        invalidateMeasure();
    }

    /**
     * Set child grid position.
     */
    void setPosition(Widget child, int col, int row, int colSpan = 1, int rowSpan = 1) {
        _childColumn[child] = col;
        _childRow[child] = row;
        _childColSpan[child] = max(1, colSpan);
        _childRowSpan[child] = max(1, rowSpan);
        invalidateMeasure();
    }

    /**
     * Get child column.
     */
    int getColumn(Widget child) const {
        if (auto p = child in _childColumn)
            return *p;
        return 0;
    }

    /**
     * Get child row.
     */
    int getRow(Widget child) const {
        if (auto p = child in _childRow)
            return *p;
        return 0;
    }

protected:
    override void onChildAdded(Widget child) {
        // Default to cell (0, 0)
        if (child !in _childColumn) {
            _childColumn[child] = 0;
            _childRow[child] = 0;
            _childColSpan[child] = 1;
            _childRowSpan[child] = 1;
        }
    }

    override void onChildRemoved(Widget child) {
        _childColumn.remove(child);
        _childRow.remove(child);
        _childColSpan.remove(child);
        _childRowSpan.remove(child);
    }

    override Size measureOverride(Size availableSize) {
        if (_columnDefs.length == 0 || _rowDefs.length == 0)
            return Size.zero;

        size_t cols = _columnDefs.length;
        size_t rows = _rowDefs.length;

        // Initialize arrays
        _columnWidths = new int[cols];
        _rowHeights = new int[rows];

        // First pass: measure auto columns/rows
        foreach (child; _children) {
            if (child.visibility == Visibility.collapsed) continue;

            int col = getColumn(child);
            int row = getRow(child);
            int colSpan = _childColSpan.get(child, 1);
            int rowSpan = _childRowSpan.get(child, 1);

            // Skip if out of bounds
            if (col >= cols || row >= rows) continue;

            auto childSize = child.measure(Size.infinite);

            // Only contribute to auto-sized columns (single span)
            if (colSpan == 1 && col < cols && _columnDefs[col].isAuto) {
                _columnWidths[col] = max(_columnWidths[col], childSize.width);
            }

            // Only contribute to auto-sized rows (single span)
            if (rowSpan == 1 && row < rows && _rowDefs[row].isAuto) {
                _rowHeights[row] = max(_rowHeights[row], childSize.height);
            }
        }

        // Set pixel sizes
        foreach (i, def; _columnDefs) {
            if (def.isPixel)
                _columnWidths[i] = cast(int)def.value;
        }
        foreach (i, def; _rowDefs) {
            if (def.isPixel)
                _rowHeights[i] = cast(int)def.value;
        }

        // Calculate total for star distribution
        int totalWidth = _columnWidths.sum + cast(int)(_columnGap * (cols - 1));
        int totalHeight = _rowHeights.sum + cast(int)(_rowGap * (rows - 1));

        // Distribute star columns
        float totalStarCols = 0;
        foreach (def; _columnDefs)
            if (def.isStar) totalStarCols += def.value;

        if (totalStarCols > 0 && availableSize.width < int.max) {
            int remaining = availableSize.width - totalWidth;
            foreach (i, def; _columnDefs) {
                if (def.isStar) {
                    _columnWidths[i] = cast(int)(remaining * def.value / totalStarCols);
                    totalWidth += _columnWidths[i];
                }
            }
        }

        // Distribute star rows
        float totalStarRows = 0;
        foreach (def; _rowDefs)
            if (def.isStar) totalStarRows += def.value;

        if (totalStarRows > 0 && availableSize.height < int.max) {
            int remaining = availableSize.height - totalHeight;
            foreach (i, def; _rowDefs) {
                if (def.isStar) {
                    _rowHeights[i] = cast(int)(remaining * def.value / totalStarRows);
                    totalHeight += _rowHeights[i];
                }
            }
        }

        return Size(
            _columnWidths.sum + cast(int)(_columnGap * (cols - 1)),
            _rowHeights.sum + cast(int)(_rowGap * (rows - 1))
        );
    }

    override void arrangeOverride(Size finalSize) {
        if (_columnDefs.length == 0 || _rowDefs.length == 0) return;

        // Recalculate star sizes with final dimensions
        redistributeStarSizes(finalSize);

        // Calculate column/row positions
        int[] colPos = new int[_columnDefs.length + 1];
        int[] rowPos = new int[_rowDefs.length + 1];

        colPos[0] = 0;
        foreach (i, w; _columnWidths) {
            colPos[i + 1] = colPos[i] + w + _columnGap;
        }

        rowPos[0] = 0;
        foreach (i, h; _rowHeights) {
            rowPos[i + 1] = rowPos[i] + h + _rowGap;
        }

        // Arrange children
        foreach (child; _children) {
            if (child.visibility == Visibility.collapsed) continue;

            int col = getColumn(child);
            int row = getRow(child);
            int colSpan = _childColSpan.get(child, 1);
            int rowSpan = _childRowSpan.get(child, 1);

            // Clamp to bounds
            if (col >= _columnDefs.length || row >= _rowDefs.length) continue;
            int endCol = min(col + colSpan, cast(int)_columnDefs.length);
            int endRow = min(row + rowSpan, cast(int)_rowDefs.length);

            int x = colPos[col];
            int y = rowPos[row];
            int w = colPos[endCol] - x - _columnGap;
            int h = rowPos[endRow] - y - _rowGap;

            child.arrange(Rect(x, y, max(0, w), max(0, h)));
        }
    }

private:
    void redistributeStarSizes(Size finalSize) {
        // Redistribute star columns
        int fixedWidth = 0;
        float totalStarCols = 0;
        foreach (i, def; _columnDefs) {
            if (def.isStar)
                totalStarCols += def.value;
            else
                fixedWidth += _columnWidths[i];
        }
        fixedWidth += cast(int)(_columnGap * (_columnDefs.length - 1));

        if (totalStarCols > 0) {
            int remaining = max(0, finalSize.width - fixedWidth);
            foreach (i, def; _columnDefs) {
                if (def.isStar) {
                    _columnWidths[i] = cast(int)(remaining * def.value / totalStarCols);
                }
            }
        }

        // Redistribute star rows
        int fixedHeight = 0;
        float totalStarRows = 0;
        foreach (i, def; _rowDefs) {
            if (def.isStar)
                totalStarRows += def.value;
            else
                fixedHeight += _rowHeights[i];
        }
        fixedHeight += cast(int)(_rowGap * (_rowDefs.length - 1));

        if (totalStarRows > 0) {
            int remaining = max(0, finalSize.height - fixedHeight);
            foreach (i, def; _rowDefs) {
                if (def.isStar) {
                    _rowHeights[i] = cast(int)(remaining * def.value / totalStarRows);
                }
            }
        }
    }
}

// ============================================================================
// Dock Layout
// ============================================================================

/**
 * Dock position for DockPanel children.
 */
enum Dock {
    left,
    top,
    right,
    bottom,
    fill,  // Takes remaining space
}

/**
 * Dock panel - docks children to edges.
 *
 * Last child (or children with Dock.fill) fills remaining space.
 */
class DockPanel : Container {
private:
    Dock[Widget] _childDock;
    bool _lastChildFill = true;

public:
    /// Whether last child fills remaining space
    @property bool lastChildFill() const { return _lastChildFill; }
    @property void lastChildFill(bool value) {
        if (_lastChildFill != value) {
            _lastChildFill = value;
            invalidateArrange();
        }
    }

    /**
     * Set dock position for child.
     */
    void setDock(Widget child, Dock dock) {
        _childDock[child] = dock;
        invalidateMeasure();
    }

    /**
     * Get dock position for child.
     */
    Dock getDock(Widget child) const {
        if (auto p = child in _childDock)
            return *p;
        return Dock.left;
    }

protected:
    override void onChildRemoved(Widget child) {
        _childDock.remove(child);
    }

    override Size measureOverride(Size availableSize) {
        int usedWidth = 0;
        int usedHeight = 0;
        int maxWidth = 0;
        int maxHeight = 0;

        Size remaining = availableSize;

        foreach (i, child; _children) {
            if (child.visibility == Visibility.collapsed) continue;

            auto dock = getDock(child);
            auto childSize = child.measure(remaining);

            final switch (dock) {
                case Dock.left:
                case Dock.right:
                    maxHeight = max(maxHeight, usedHeight + childSize.height);
                    usedWidth += childSize.width;
                    remaining.width = max(0, remaining.width - childSize.width);
                    break;
                case Dock.top:
                case Dock.bottom:
                    maxWidth = max(maxWidth, usedWidth + childSize.width);
                    usedHeight += childSize.height;
                    remaining.height = max(0, remaining.height - childSize.height);
                    break;
                case Dock.fill:
                    maxWidth = max(maxWidth, usedWidth + childSize.width);
                    maxHeight = max(maxHeight, usedHeight + childSize.height);
                    break;
            }
        }

        return Size(max(maxWidth, usedWidth), max(maxHeight, usedHeight));
    }

    override void arrangeOverride(Size finalSize) {
        int left = 0;
        int top = 0;
        int right = finalSize.width;
        int bottom = finalSize.height;

        foreach (i, child; _children) {
            if (child.visibility == Visibility.collapsed) continue;

            auto dock = getDock(child);
            bool isLast = (i == _children.length - 1);

            // Last child fills if enabled
            if (isLast && _lastChildFill) {
                dock = Dock.fill;
            }

            Rect childRect;

            final switch (dock) {
                case Dock.left:
                    childRect = Rect(left, top, child.desiredSize.width, bottom - top);
                    left += child.desiredSize.width;
                    break;
                case Dock.top:
                    childRect = Rect(left, top, right - left, child.desiredSize.height);
                    top += child.desiredSize.height;
                    break;
                case Dock.right:
                    int w = child.desiredSize.width;
                    childRect = Rect(right - w, top, w, bottom - top);
                    right -= w;
                    break;
                case Dock.bottom:
                    int h = child.desiredSize.height;
                    childRect = Rect(left, bottom - h, right - left, h);
                    bottom -= h;
                    break;
                case Dock.fill:
                    childRect = Rect(left, top, right - left, bottom - top);
                    break;
            }

            child.arrange(childRect);
        }
    }
}

// ============================================================================
// Wrap Panel
// ============================================================================

/**
 * Wrap panel - arranges children in lines, wrapping as needed.
 */
class WrapPanel : Container {
private:
    Orientation _orientation = Orientation.horizontal;
    int _itemWidth = 0;   // 0 = auto
    int _itemHeight = 0;  // 0 = auto

public:
    @property Orientation orientation() const { return _orientation; }
    @property void orientation(Orientation value) {
        if (_orientation != value) {
            _orientation = value;
            invalidateMeasure();
        }
    }

    /// Fixed item width (0 for auto)
    @property int itemWidth() const { return _itemWidth; }
    @property void itemWidth(int value) {
        if (_itemWidth != value) {
            _itemWidth = value;
            invalidateMeasure();
        }
    }

    /// Fixed item height (0 for auto)
    @property int itemHeight() const { return _itemHeight; }
    @property void itemHeight(int value) {
        if (_itemHeight != value) {
            _itemHeight = value;
            invalidateMeasure();
        }
    }

protected:
    override Size measureOverride(Size availableSize) {
        int lineSize = 0;    // Size in primary direction
        int lineThickness = 0;  // Size in cross direction
        int totalThickness = 0;
        int maxLineSize = 0;

        int constraint = _orientation == Orientation.horizontal
            ? availableSize.width : availableSize.height;

        foreach (child; _children) {
            if (child.visibility == Visibility.collapsed) continue;

            auto childSize = child.measure(availableSize);
            int w = _itemWidth > 0 ? _itemWidth : childSize.width;
            int h = _itemHeight > 0 ? _itemHeight : childSize.height;

            int childMain = _orientation == Orientation.horizontal ? w : h;
            int childCross = _orientation == Orientation.horizontal ? h : w;

            // Wrap to new line?
            if (lineSize + childMain > constraint && lineSize > 0) {
                totalThickness += lineThickness;
                maxLineSize = max(maxLineSize, lineSize);
                lineSize = 0;
                lineThickness = 0;
            }

            lineSize += childMain;
            lineThickness = max(lineThickness, childCross);
        }

        // Account for last line
        totalThickness += lineThickness;
        maxLineSize = max(maxLineSize, lineSize);

        if (_orientation == Orientation.horizontal)
            return Size(maxLineSize, totalThickness);
        else
            return Size(totalThickness, maxLineSize);
    }

    override void arrangeOverride(Size finalSize) {
        int lineStart = 0;
        int lineSize = 0;
        int lineThickness = 0;

        int constraint = _orientation == Orientation.horizontal
            ? finalSize.width : finalSize.height;

        // First pass: find line breaks
        size_t lineStartIdx = 0;

        void arrangeLine(size_t endIdx, int thickness) {
            int pos = 0;
            foreach (i; lineStartIdx .. endIdx) {
                auto child = _children[i];
                if (child.visibility == Visibility.collapsed) continue;

                int w = _itemWidth > 0 ? _itemWidth : child.desiredSize.width;
                int h = _itemHeight > 0 ? _itemHeight : child.desiredSize.height;

                if (_orientation == Orientation.horizontal) {
                    child.arrange(Rect(pos, lineStart, w, thickness));
                    pos += w;
                } else {
                    child.arrange(Rect(lineStart, pos, thickness, h));
                    pos += h;
                }
            }
        }

        foreach (i, child; _children) {
            if (child.visibility == Visibility.collapsed) continue;

            int w = _itemWidth > 0 ? _itemWidth : child.desiredSize.width;
            int h = _itemHeight > 0 ? _itemHeight : child.desiredSize.height;

            int childMain = _orientation == Orientation.horizontal ? w : h;
            int childCross = _orientation == Orientation.horizontal ? h : w;

            if (lineSize + childMain > constraint && lineSize > 0) {
                // Arrange previous line
                arrangeLine(i, lineThickness);
                lineStart += lineThickness;
                lineStartIdx = i;
                lineSize = 0;
                lineThickness = 0;
            }

            lineSize += childMain;
            lineThickness = max(lineThickness, childCross);
        }

        // Arrange last line
        arrangeLine(_children.length, lineThickness);
    }
}

// ============================================================================
// Canvas (Absolute Positioning)
// ============================================================================

/**
 * Canvas - positions children at absolute coordinates.
 */
class Canvas : Container {
private:
    int[Widget] _childLeft;
    int[Widget] _childTop;
    int[Widget] _childRight;
    int[Widget] _childBottom;

public:
    /**
     * Set left position.
     */
    void setLeft(Widget child, int value) {
        _childLeft[child] = value;
        invalidateArrange();
    }

    /**
     * Set top position.
     */
    void setTop(Widget child, int value) {
        _childTop[child] = value;
        invalidateArrange();
    }

    /**
     * Set right position (distance from right edge).
     */
    void setRight(Widget child, int value) {
        _childRight[child] = value;
        invalidateArrange();
    }

    /**
     * Set bottom position (distance from bottom edge).
     */
    void setBottom(Widget child, int value) {
        _childBottom[child] = value;
        invalidateArrange();
    }

    int getLeft(Widget child) const {
        if (auto p = child in _childLeft) return *p;
        return int.min;
    }

    int getTop(Widget child) const {
        if (auto p = child in _childTop) return *p;
        return int.min;
    }

    int getRight(Widget child) const {
        if (auto p = child in _childRight) return *p;
        return int.min;
    }

    int getBottom(Widget child) const {
        if (auto p = child in _childBottom) return *p;
        return int.min;
    }

protected:
    override void onChildRemoved(Widget child) {
        _childLeft.remove(child);
        _childTop.remove(child);
        _childRight.remove(child);
        _childBottom.remove(child);
    }

    override Size measureOverride(Size availableSize) {
        // Canvas doesn't constrain children
        foreach (child; _children) {
            if (child.visibility == Visibility.collapsed) continue;
            child.measure(Size.infinite);
        }
        return Size.zero;  // Canvas has no natural size
    }

    override void arrangeOverride(Size finalSize) {
        foreach (child; _children) {
            if (child.visibility == Visibility.collapsed) continue;

            int left = getLeft(child);
            int top = getTop(child);
            int right = getRight(child);
            int bottom = getBottom(child);

            int x = 0, y = 0;
            int w = child.desiredSize.width;
            int h = child.desiredSize.height;

            // Horizontal positioning
            if (left != int.min) {
                x = left;
                if (right != int.min) {
                    w = finalSize.width - left - right;
                }
            } else if (right != int.min) {
                x = finalSize.width - right - w;
            }

            // Vertical positioning
            if (top != int.min) {
                y = top;
                if (bottom != int.min) {
                    h = finalSize.height - top - bottom;
                }
            } else if (bottom != int.min) {
                y = finalSize.height - bottom - h;
            }

            child.arrange(Rect(x, y, max(0, w), max(0, h)));
        }
    }
}

// ============================================================================
// Uniform Grid
// ============================================================================

/**
 * Uniform grid - all cells are the same size.
 */
class UniformGrid : Container {
private:
    int _columns = 0;  // 0 = auto-calculate
    int _rows = 0;     // 0 = auto-calculate
    int _firstColumn = 0;

public:
    /// Number of columns (0 = auto)
    @property int columns() const { return _columns; }
    @property void columns(int value) {
        if (_columns != value) {
            _columns = value;
            invalidateMeasure();
        }
    }

    /// Number of rows (0 = auto)
    @property int rows() const { return _rows; }
    @property void rows(int value) {
        if (_rows != value) {
            _rows = value;
            invalidateMeasure();
        }
    }

    /// First column offset for first row
    @property int firstColumn() const { return _firstColumn; }
    @property void firstColumn(int value) {
        if (_firstColumn != value) {
            _firstColumn = value;
            invalidateArrange();
        }
    }

protected:
    override Size measureOverride(Size availableSize) {
        auto dims = computeDimensions();
        if (dims.cols == 0 || dims.rows == 0)
            return Size.zero;

        int cellWidth = availableSize.width / dims.cols;
        int cellHeight = availableSize.height / dims.rows;
        Size cellSize = Size(cellWidth, cellHeight);

        int maxChildWidth = 0;
        int maxChildHeight = 0;

        foreach (child; _children) {
            if (child.visibility == Visibility.collapsed) continue;
            auto childSize = child.measure(cellSize);
            maxChildWidth = max(maxChildWidth, childSize.width);
            maxChildHeight = max(maxChildHeight, childSize.height);
        }

        return Size(maxChildWidth * dims.cols, maxChildHeight * dims.rows);
    }

    override void arrangeOverride(Size finalSize) {
        auto dims = computeDimensions();
        if (dims.cols == 0 || dims.rows == 0) return;

        int cellWidth = finalSize.width / dims.cols;
        int cellHeight = finalSize.height / dims.rows;

        int col = _firstColumn;
        int row = 0;

        foreach (child; _children) {
            if (child.visibility == Visibility.collapsed) continue;

            child.arrange(Rect(col * cellWidth, row * cellHeight, cellWidth, cellHeight));

            col++;
            if (col >= dims.cols) {
                col = 0;
                row++;
            }
        }
    }

private:
    struct Dimensions { int cols; int rows; }

    Dimensions computeDimensions() {
        size_t visibleCount = 0;
        foreach (child; _children) {
            if (child.visibility != Visibility.collapsed)
                visibleCount++;
        }

        if (visibleCount == 0)
            return Dimensions(0, 0);

        int cols = _columns;
        int rows = _rows;

        if (cols == 0 && rows == 0) {
            // Auto: make roughly square
            import std.math : sqrt, ceil;
            cols = cast(int)ceil(sqrt(cast(double)(visibleCount + _firstColumn)));
        }

        if (cols == 0)
            cols = cast(int)((visibleCount + _firstColumn + rows - 1) / rows);

        if (rows == 0)
            rows = cast(int)((visibleCount + _firstColumn + cols - 1) / cols);

        return Dimensions(cols, rows);
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

unittest {
    // Test GridLength
    auto auto_ = GridLength.auto_();
    assert(auto_.isAuto);

    auto px = GridLength.pixels(100);
    assert(px.isPixel);
    assert(px.value == 100);

    auto star = GridLength.star(2);
    assert(star.isStar);
    assert(star.value == 2);
}

unittest {
    // Test Grid creation
    auto grid = new Grid();
    grid.setColumns(GridLength.pixels(100), GridLength.star(1), GridLength.auto_());
    grid.setRows(GridLength.auto_(), GridLength.star(1));
    assert(grid.columnCount == 3);
    assert(grid.rowCount == 2);
}

unittest {
    // Test DockPanel
    auto dock = new DockPanel();
    assert(dock.lastChildFill == true);
}
