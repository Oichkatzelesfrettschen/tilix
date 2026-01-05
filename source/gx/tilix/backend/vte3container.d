/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.backend.vte3container;

import gdk.RGBA;
import gdk.Pixbuf;
import gtk.Widget;
import gtk.Adjustment;
import pango.PgFontDescription;
import vte.Pty;
import vte.Terminal;
import vtec.vtetypes : VtePtyFlags, VteCursorShape, VteCursorBlinkMode;
import glib.c.types : GSpawnFlags;

import gx.tilix.backend.container;
import gx.tilix.backend.render;
import gx.tilix.terminal.exvte;

/**
 * VTE3-based implementation of IRenderingContainer.
 *
 * Wraps ExtendedVTE (VTE3 terminal widget) to provide the standard
 * IRenderingContainer interface. This allows Terminal.d to remain
 * backend-agnostic while using the mature VTE3 rendering engine.
 *
 * Design Notes:
 * - Delegates all operations directly to underlying ExtendedVTE
 * - Minimal overhead - just method forwarding
 * - Signal handlers registered on construction, cleaned up on dispose
 * - Backend property returns null (VTE3 doesn't use IRenderBackend)
 */
class VTE3Container : IRenderingContainer {
private:
    ExtendedVTE _vte;
    IRenderBackend _backend;  // null for VTE3 (uses native rendering)
    bool _isReady;

public:

    /**
     * Construct container wrapping an ExtendedVTE widget.
     */
    this(ExtendedVTE vte) {
        _vte = vte;
        _backend = null;  // VTE3 doesn't use IRenderBackend
        _isReady = false;
    }

    /**
     * Construct with new ExtendedVTE instance.
     */
    this() {
        this(new ExtendedVTE());
    }


    // === WIDGET HIERARCHY ===

    @property Widget widget() {
        return _vte;
    }

    @property IRenderBackend backend() {
        return _backend;  // null for VTE3
    }


    // === PTY AND PROCESS MANAGEMENT ===

    bool spawnSync(
        VtePtyFlags ptyFlags,
        string workingDir,
        string[] argv,
        string[] envv,
        GSpawnFlags spawnFlags,
        out int childPid
    ) {
        return _vte.spawnSync(
            ptyFlags,
            workingDir,
            argv,
            envv,
            spawnFlags,
            null,  // child setup function
            null,  // child setup data
            childPid,
            null   // cancellable
        );
    }

    Pty getPty() {
        return _vte.getPty();
    }

    void feedChild(string data) {
        _vte.feedChild(data);
    }

    int getChildPid() {
        return _vte.getChildPid();
    }


    // === TERMINAL STATE QUERIES ===

    @property ulong columnCount() {
        return _vte.getColumnCount();
    }

    @property ulong rowCount() {
        return _vte.getRowCount();
    }

    void getCursorPosition(out long column, out long row) {
        _vte.getCursorPosition(column, row);
    }

    @property bool hasSelection() {
        return _vte.getHasSelection();
    }

    string getText(
        long startRow, long startCol,
        long endRow, long endCol
    ) {
        import glib.ArrayG;
        ArrayG attrs;
        // VTE getText requires callback - use null to get all text
        return _vte.getText(null, null, attrs);
    }


    // === WINDOW TITLE AND METADATA ===

    @property string windowTitle() {
        return _vte.getWindowTitle();
    }

    @property string currentDirectoryUri() {
        return _vte.getCurrentDirectoryUri();
    }


    // === FONT AND COLORS ===

    void setFont(PgFontDescription font) {
        _vte.setFont(font);
    }

    @property double fontScale() {
        return _vte.getFontScale();
    }

    @property void fontScale(double scale) {
        _vte.setFontScale(scale);
    }

    void setColors(RGBA foreground, RGBA background, RGBA[] palette) {
        _vte.setColors(foreground, background, palette);
    }

    void setColorCursor(RGBA bg, RGBA fg) {
        _vte.setColorCursor(bg);
        _vte.setColorCursorForeground(fg);
    }

    void setColorHighlight(RGBA bg, RGBA fg) {
        _vte.setColorHighlight(bg);
        _vte.setColorHighlightForeground(fg);
    }

    void setCursorShape(VteCursorShape shape) {
        _vte.setCursorShape(shape);
    }

    void setCursorBlinkMode(VteCursorBlinkMode mode) {
        _vte.setCursorBlinkMode(mode);
    }

    @property uint charWidth() {
        return cast(uint)_vte.getCharWidth();
    }

    @property uint charHeight() {
        return cast(uint)_vte.getCharHeight();
    }


    // === TERMINAL BEHAVIOR ===

    @property void inputEnabled(bool enabled) {
        _vte.setInputEnabled(enabled);
    }

    @property bool inputEnabled() {
        return _vte.getInputEnabled();
    }

    void setAudibleBell(bool enabled) {
        _vte.setAudibleBell(enabled);
    }

    void setAllowBold(bool enabled) {
        _vte.setAllowBold(enabled);
    }

    void setRewrapOnResize(bool enabled) {
        _vte.setRewrapOnResize(enabled);
    }

    void setEncoding(string encoding) {
        _vte.setEncoding(encoding);
    }

    @property string encoding() {
        return _vte.getEncoding();
    }


    // === SCROLLING ===

    Adjustment getAdjustment() {
        return _vte.getVadjustment();
    }

    void scrollLines(int lines) {
        auto adj = _vte.getVadjustment();
        if (adj is null) return;

        double value = adj.getValue();
        double newValue = value + (lines * _vte.getCharHeight());
        adj.setValue(newValue);
    }

    void scrollPages(int pages) {
        auto adj = _vte.getVadjustment();
        if (adj is null) return;

        double pageSize = adj.getPageSize();
        double value = adj.getValue();
        double newValue = value + (pages * pageSize);
        adj.setValue(newValue);
    }


    // === CLIPBOARD ===

    void copyClipboard() {
        _vte.copyClipboard();
    }

    void copyPrimary() {
        _vte.copyPrimary();
    }

    void pasteClipboard() {
        _vte.pasteClipboard();
    }

    void pastePrimary() {
        _vte.pastePrimary();
    }


    // === SEARCH ===

    void searchSetWrapAround(bool wrap) {
        _vte.searchSetWrapAround(wrap);
    }

    bool searchGetWrapAround() {
        return _vte.searchGetWrapAround();
    }

    bool searchFindNext() {
        return _vte.searchFindNext();
    }

    bool searchFindPrevious() {
        return _vte.searchFindPrevious();
    }


    // === RENDERING AND SNAPSHOTS ===

    void queueDraw() {
        _vte.queueDraw();
    }

    Pixbuf captureSnapshot(double scale) {
        // VTE3 doesn't expose direct snapshot API
        // Would need to implement via Cairo surface capture
        // For now, return null (to be implemented)
        return null;
    }


    // === SIGNAL CONNECTION ===

    gulong addOnBell(BellHandler handler) {
        // Adapt: VTE expects Terminal parameter, our interface doesn't
        return _vte.addOnBell((Terminal t) { handler(); });
    }

    gulong addOnChildExited(ChildExitedHandler handler) {
        // Adapt: VTE passes Terminal as second parameter
        return _vte.addOnChildExited((int status, Terminal t) { handler(status); });
    }

    gulong addOnWindowTitleChanged(StringHandler handler) {
        return _vte.addOnWindowTitleChanged((Terminal t) { handler(); });
    }

    gulong addOnCurrentDirectoryUriChanged(StringHandler handler) {
        return _vte.addOnCurrentDirectoryUriChanged((Terminal t) { handler(); });
    }

    gulong addOnContentsChanged(StringHandler handler) {
        return _vte.addOnContentsChanged((Terminal t) { handler(); });
    }

    gulong addOnSelectionChanged(StringHandler handler) {
        return _vte.addOnSelectionChanged((Terminal t) { handler(); });
    }

    gulong addOnCommit(CommitHandler handler) {
        // Adapt: VTE passes Terminal as third parameter
        return _vte.addOnCommit((string text, uint length, Terminal t) {
            handler(text, length);
        });
    }

    void disconnect(gulong handlerId) {
        import gobject.Signals;
        Signals.handlerDisconnect(_vte, handlerId);
    }


    // === LIFECYCLE ===

    void initialize() {
        _isReady = true;
    }

    @property bool isReady() {
        return _isReady;
    }

    void dispose() {
        _isReady = false;
        // ExtendedVTE cleanup handled by GObject reference counting
        _vte = null;
    }
}
