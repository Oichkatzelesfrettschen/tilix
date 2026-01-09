/**
 * AT-SPI Core Interface Implementations
 *
 * Defines D-Bus accessible interfaces for screen reader interaction:
 * - org.a11y.atspi.Accessible: Basic accessible properties
 * - org.a11y.atspi.Text: Text content extraction and navigation
 * - org.a11y.atspi.Component: Geometry and focus management
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.accessibility.atspi.interfaces;

version (PURE_D_BACKEND):

import pured.accessibility.atspi.types;
import pured.accessibility.atspi.provider;

/**
 * org.a11y.atspi.Accessible interface (D-Bus accessible object).
 * Base interface that all accessible objects implement.
 */
interface IAccessibleDbus : IAccessible {
    /**
     * Get list of interfaces implemented by this object.
     * Returns: Array of interface names (e.g., ["Accessible", "Text", "Component"])
     */
    string[] getInterfaces() const;

    /**
     * Get accessible parent object.
     * Returns: Object path of parent, or empty if none.
     */
    string getParentPath() const;

    /**
     * Get list of child object paths.
     * Returns: Array of child object paths.
     */
    string[] getChildPaths() const;

    /**
     * Get indexed application property.
     * Params:
     *   key = Property name (e.g., "accessible-name", "accessible-description")
     * Returns: Property value as variant.
     */
    string getProperty(string key) const;

    /**
     * Check if this accessible has a cached value for a property.
     */
    bool hasProperty(string key) const;
}

/**
 * org.a11y.atspi.Text interface (D-Bus text extraction).
 * Provides text content and navigation for text-based accessible objects.
 */
interface IAccessibleText {
    /**
     * Get all text content.
     * Returns: Full visible text of this accessible.
     */
    string getText() const;

    /**
     * Get text range by character offsets.
     * Params:
     *   startOffset = Starting character index
     *   endOffset = Ending character index (exclusive)
     * Returns: Text substring, or empty if out of bounds.
     */
    string getTextRange(uint startOffset, uint endOffset) const;

    /**
     * Get text at specified offset with boundary type.
     * Params:
     *   offset = Character offset
     *   boundary = Text boundary type (Char, WordStart, LineStart, etc.)
     * Returns: Text at boundary (word, line, sentence, etc.)
     */
    string getTextAtOffset(uint offset, ATSPITextBoundary boundary) const;

    /**
     * Get the current caret (cursor) position in characters.
     * Returns: Character offset of cursor (0-based).
     */
    uint getCaretOffset() const;

    /**
     * Set the caret position.
     * Params:
     *   offset = New character offset
     * Returns: true if successful.
     */
    bool setCaretOffset(uint offset);

    /**
     * Get total number of characters.
     * Returns: Character count of visible text.
     */
    uint getCharacterCount() const;

    /**
     * Get bounding box of character at offset.
     * Params:
     *   offset = Character offset
     *   coordType = Coordinate system (Screen, Window, Parent)
     * Returns: Rectangle containing the character.
     */
    ATSPIRect getCharacterExtents(uint offset, ATSPICoordType coordType) const;

    /**
     * Check if text is editable.
     * Returns: true if text can be modified.
     */
    bool isEditable() const;

    /**
     * Get character offset at screen coordinates.
     * Params:
     *   x, y = Screen coordinates
     *   coordType = Coordinate system
     * Returns: Character offset at position, or -1 if not found.
     */
    int getOffsetAtPoint(int x, int y, ATSPICoordType coordType) const;
}

/**
 * org.a11y.atspi.Component interface (D-Bus geometry and focus).
 * Provides spatial information and focus management for accessible objects.
 */
interface IAccessibleComponent {
    /**
     * Get the bounding box of this accessible.
     * Params:
     *   coordType = Coordinate system (Screen, Window, Parent)
     * Returns: Rectangle in specified coordinate system.
     */
    ATSPIRect getExtents(ATSPICoordType coordType) const;

    /**
     * Get layer (z-order group) of this component.
     * Returns: Layer enumeration value.
     */
    uint getLayer() const;

    /**
     * Get z-order position within the layer.
     * Returns: Z-order value (higher = on top).
     */
    int getZOrder() const;

    /**
     * Request focus on this accessible.
     * Returns: true if focus was successfully acquired.
     */
    bool grabFocus();

    /**
     * Check if this component contains the given point.
     * Params:
     *   x, y = Screen coordinates
     *   coordType = Coordinate system
     * Returns: true if point is within bounds.
     */
    bool contains(int x, int y, ATSPICoordType coordType) const;

    /**
     * Get accessible at screen point (for hit testing).
     * Params:
     *   x, y = Screen coordinates
     *   coordType = Coordinate system
     * Returns: Child accessible at point, or null if none.
     */
    IAccessible getAccessibleAtPoint(int x, int y, ATSPICoordType coordType) const;

    /**
     * Get component alpha (transparency).
     * Returns: Alpha value (0.0 = transparent, 1.0 = opaque).
     */
    double getAlpha() const;

    /**
     * Get component visibility state.
     * Returns: true if component is visible.
     */
    bool isVisible() const;
}

/**
 * Terminal text accessor (for integrating with terminal emulator text extraction).
 */
interface ITerminalTextAccessor {
    /**
     * Get visible terminal text (current viewport).
     * Returns: All visible terminal text.
     */
    string getVisibleText() const;

    /**
     * Get text at row and column offset.
     * Params:
     *   row = Terminal row (0-based, relative to viewport top)
     *   col = Terminal column (0-based)
     *   length = Number of characters to extract
     * Returns: Text substring.
     */
    string getTextAt(uint row, uint col, uint length) const;

    /**
     * Get current cursor position.
     * Returns: (row, col) tuple of cursor position.
     */
    void getCursorPosition(out uint row, out uint col) const;

    /**
     * Get terminal dimensions.
     * Returns: (rows, cols) tuple of terminal size.
     */
    void getTerminalSize(out uint rows, out uint cols) const;

    /**
     * Get text as linear character offset (flattened).
     * Params:
     *   row = Terminal row
     *   col = Terminal column
     * Returns: Linear character offset in flattened text.
     */
    uint getLinearOffset(uint row, uint col) const;

    /**
     * Convert linear character offset back to row/col.
     * Params:
     *   offset = Linear character offset
     * Params out:
     *   row, col = Terminal position
     */
    void getRowColFromOffset(uint offset, out uint row, out uint col) const;
}
