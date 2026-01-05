/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.backend.container;

import gdk.RGBA;
import gdk.Pixbuf;
import gtk.Widget;
import gtk.Adjustment;
import pango.PgFontDescription;
import vte.Pty;
import vtec.vtetypes : VtePtyFlags, VteCursorShape, VteCursorBlinkMode;
import glib.c.types : GSpawnFlags;

import gx.tilix.backend.render;

/**
 * Abstraction layer between Terminal and rendering backends.
 *
 * Purpose:
 * - Decouple Terminal logic from VTE-specific operations
 * - Enable backend switching (VTE3 vs OpenGL)
 * - Support testing with mock implementations
 * - Abstract PTY operations, font/color application, and rendering
 *
 * This interface provides a unified API that both VTE3Container and
 * OpenGLContainer implement, allowing Terminal.d to remain backend-agnostic.
 */
interface IRenderingContainer {

    // === WIDGET HIERARCHY ===

    /**
     * Get the GTK Widget for embedding in container hierarchy.
     * For VTE3: returns the VTE Terminal widget
     * For OpenGL: returns the GtkGLArea widget
     */
    @property Widget widget();

    /**
     * Get the underlying render backend.
     * Exposes IRenderBackend for advanced operations (snapshot, capabilities).
     */
    @property IRenderBackend backend();


    // === PTY AND PROCESS MANAGEMENT ===

    /**
     * Spawn a child process with PTY.
     *
     * Params:
     *   ptyFlags = VTE PTY flags
     *   workingDir = Working directory for child process
     *   argv = Command and arguments
     *   envv = Environment variables
     *   spawnFlags = GLib spawn flags
     *   childPid = Output parameter for child PID
     *
     * Returns: true if spawn succeeded
     */
    bool spawnSync(
        VtePtyFlags ptyFlags,
        string workingDir,
        string[] argv,
        string[] envv,
        GSpawnFlags spawnFlags,
        out int childPid
    );

    /**
     * Get the PTY associated with this container.
     * Returns null if no PTY is active.
     */
    Pty getPty();

    /**
     * Feed data to the child process.
     * Used for sending keyboard input and paste operations.
     */
    void feedChild(string data);

    /**
     * Get the child PID running in the terminal.
     * Returns -1 if no child process is running.
     */
    int getChildPid();


    // === TERMINAL STATE QUERIES ===

    /**
     * Get current terminal dimensions.
     */
    @property ulong columnCount();
    @property ulong rowCount();

    /**
     * Get cursor position.
     */
    void getCursorPosition(out long column, out long row);

    /**
     * Check if terminal has selected text.
     */
    @property bool hasSelection();

    /**
     * Get text from terminal buffer.
     *
     * Params:
     *   startRow = Starting row
     *   startCol = Starting column
     *   endRow = Ending row
     *   endCol = Ending column
     *
     * Returns: Selected text
     */
    string getText(
        long startRow, long startCol,
        long endRow, long endCol
    );


    // === WINDOW TITLE AND METADATA ===

    /**
     * Get window title set by child process (e.g., via OSC 0).
     */
    @property string windowTitle();

    /**
     * Get current directory URI (if VTE configured correctly).
     * Returns null if not available.
     */
    @property string currentDirectoryUri();


    // === FONT AND COLORS ===

    /**
     * Set terminal font.
     */
    void setFont(PgFontDescription font);

    /**
     * Get current font scale factor.
     */
    @property double fontScale();

    /**
     * Set font scale factor (zoom level).
     */
    @property void fontScale(double scale);

    /**
     * Apply color palette to terminal.
     *
     * Params:
     *   foreground = Foreground color
     *   background = Background color
     *   palette = 16-color ANSI palette
     */
    void setColors(RGBA foreground, RGBA background, RGBA[] palette);

    /**
     * Set cursor colors (foreground and background).
     */
    void setColorCursor(RGBA bg, RGBA fg);

    /**
     * Set highlight/selection colors.
     */
    void setColorHighlight(RGBA bg, RGBA fg);

    /**
     * Set cursor shape.
     */
    void setCursorShape(VteCursorShape shape);

    /**
     * Set cursor blink mode.
     */
    void setCursorBlinkMode(VteCursorBlinkMode mode);

    /**
     * Get character cell dimensions in pixels.
     */
    @property uint charWidth();
    @property uint charHeight();


    // === TERMINAL BEHAVIOR ===

    /**
     * Enable or disable input to terminal.
     * Used for read-only mode.
     */
    @property void inputEnabled(bool enabled);
    @property bool inputEnabled();

    /**
     * Enable or disable audible bell.
     */
    void setAudibleBell(bool enabled);

    /**
     * Enable or disable bold text.
     */
    void setAllowBold(bool enabled);

    /**
     * Enable or disable text rewrapping on resize.
     */
    void setRewrapOnResize(bool enabled);

    /**
     * Set character encoding (e.g., "UTF-8").
     */
    void setEncoding(string encoding);

    /**
     * Get current character encoding.
     */
    @property string encoding();


    // === SCROLLING ===

    /**
     * Get scrollback adjustment for scrollbar integration.
     */
    Adjustment getAdjustment();

    /**
     * Scroll by specified number of lines.
     * Positive values scroll down, negative scroll up.
     */
    void scrollLines(int lines);

    /**
     * Scroll by specified number of pages.
     */
    void scrollPages(int pages);


    // === CLIPBOARD ===

    /**
     * Copy selected text to clipboard.
     */
    void copyClipboard();

    /**
     * Copy selected text to primary selection.
     */
    void copyPrimary();

    /**
     * Paste from clipboard.
     */
    void pasteClipboard();

    /**
     * Paste from primary selection.
     */
    void pastePrimary();


    // === SEARCH ===

    /**
     * Set search wrap-around behavior.
     */
    void searchSetWrapAround(bool wrap);

    /**
     * Get search wrap-around behavior.
     */
    bool searchGetWrapAround();

    /**
     * Search for next occurrence of current pattern.
     */
    bool searchFindNext();

    /**
     * Search for previous occurrence of current pattern.
     */
    bool searchFindPrevious();


    // === RENDERING AND SNAPSHOTS ===

    /**
     * Queue a redraw of the terminal.
     */
    void queueDraw();

    /**
     * Capture snapshot of terminal as Pixbuf for tab previews.
     *
     * Params:
     *   scale = Scale factor (e.g., 0.2 for 20% size)
     *
     * Returns: Pixbuf snapshot or null on failure
     */
    Pixbuf captureSnapshot(double scale);


    // === SIGNAL CONNECTION ===

    /**
     * Connect signal handlers.
     * Returns handler ID for disconnection.
     *
     * Signals:
     * - onBell()
     * - onChildExited(int status)
     * - onWindowTitleChanged()
     * - onCurrentDirectoryUriChanged()
     * - onContentsChanged()
     * - onSelectionChanged()
     * - onCommit(string text, uint length)
     */

    alias BellHandler = void delegate();
    alias ChildExitedHandler = void delegate(int status);
    alias StringHandler = void delegate();
    alias CommitHandler = void delegate(string text, uint length);

    gulong addOnBell(BellHandler handler);
    gulong addOnChildExited(ChildExitedHandler handler);
    gulong addOnWindowTitleChanged(StringHandler handler);
    gulong addOnCurrentDirectoryUriChanged(StringHandler handler);
    gulong addOnContentsChanged(StringHandler handler);
    gulong addOnSelectionChanged(StringHandler handler);
    gulong addOnCommit(CommitHandler handler);

    /**
     * Disconnect a signal handler.
     */
    void disconnect(gulong handlerId);


    // === LIFECYCLE ===

    /**
     * Initialize the container.
     * Called after construction to set up rendering context.
     */
    void initialize();

    /**
     * Check if container is ready for operations.
     */
    @property bool isReady();

    /**
     * Clean up resources.
     */
    void dispose();
}
