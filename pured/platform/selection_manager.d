/**
 * Selection and Clipboard Manager
 *
 * Manages PRIMARY (highlight/selection) and CLIPBOARD (copy/paste) independently
 * with configurable synchronization modes.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.platform.selection_manager;

version (PURE_D_BACKEND):

import std.datetime : SysTime, Clock;
import std.conv : to;

/**
 * Selection target enumeration.
 */
enum SelectionTarget {
    /// X11 PRIMARY selection (highlight-to-copy)
    Primary,

    /// System clipboard (Ctrl+C/Ctrl+V)
    Clipboard,

    /// Both PRIMARY and CLIPBOARD
    Both
}

/**
 * Selection synchronization mode.
 */
enum SelectionSyncMode {
    /// PRIMARY and CLIPBOARD are independent
    Separate,

    /// Highlight automatically copies to both PRIMARY and CLIPBOARD
    AutoCopyPrimary,

    /// Only PRIMARY selection is used, CLIPBOARD ignored
    PrimaryOnly,

    /// Only CLIPBOARD is used, PRIMARY ignored
    ClipboardOnly
}

/**
 * Selection content with metadata.
 */
struct SelectionContent {
    /// Text content
    string text;

    /// Source of selection (user, app, system)
    string source;

    /// Time when selection was made
    SysTime timestamp;

    /// Whether this is current/valid
    bool valid;

    /// Size of content in bytes
    size_t size() const {
        return text.length;
    }

    /// Check if content is empty
    bool isEmpty() const {
        return text.length == 0;
    }

    /// Check if content is stale (older than timeout)
    bool isStale(uint timeoutSeconds) const {
        auto elapsed = Clock.currTime() - timestamp;
        return elapsed.total!"seconds"() > timeoutSeconds;
    }
}

/**
 * Selection manager handling dual clipboard with synchronization.
 */
class SelectionManager {
private:
    SelectionContent _primary;
    SelectionContent _clipboard;
    SelectionSyncMode _syncMode = SelectionSyncMode.Separate;
    uint _staleTimeout = 300; // 5 minutes

public:
    /**
     * Create selection manager.
     * Params:
     *   syncMode = Initial synchronization mode
     */
    this(SelectionSyncMode syncMode = SelectionSyncMode.Separate) {
        _syncMode = syncMode;
        _primary.valid = false;
        _clipboard.valid = false;
    }

    /**
     * Set synchronization mode.
     * Params:
     *   mode = New synchronization mode
     */
    void setSyncMode(SelectionSyncMode mode) {
        _syncMode = mode;
    }

    /**
     * Get current synchronization mode.
     */
    SelectionSyncMode getSyncMode() const {
        return _syncMode;
    }

    /**
     * Set PRIMARY selection (highlight).
     * Params:
     *   text = Selection text
     *   source = Origin of selection
     */
    void setPrimary(string text, string source = "terminal") {
        _primary.text = text;
        _primary.source = source;
        _primary.timestamp = Clock.currTime();
        _primary.valid = text.length > 0;

        // Handle synchronization
        if (_syncMode == SelectionSyncMode.AutoCopyPrimary && text.length > 0) {
            setClipboard(text, "primary-sync");
        }
    }

    /**
     * Set CLIPBOARD selection (copy/paste).
     * Params:
     *   text = Clipboard text
     *   source = Origin of clipboard text
     */
    void setClipboard(string text, string source = "terminal") {
        if (_syncMode == SelectionSyncMode.PrimaryOnly) {
            return; // CLIPBOARD disabled in this mode
        }

        _clipboard.text = text;
        _clipboard.source = source;
        _clipboard.timestamp = Clock.currTime();
        _clipboard.valid = text.length > 0;
    }

    /**
     * Get PRIMARY selection with optional validation.
     * Returns: PRIMARY selection content, or empty if not available.
     */
    string getPrimary() {
        if (!_primary.valid) {
            return "";
        }

        if (_primary.isStale(_staleTimeout)) {
            _primary.valid = false;
            return "";
        }

        return _primary.text;
    }

    /**
     * Get CLIPBOARD selection with optional validation.
     * Returns: CLIPBOARD content, or empty if not available.
     */
    string getClipboard() {
        if (_syncMode == SelectionSyncMode.PrimaryOnly) {
            return ""; // CLIPBOARD disabled
        }

        if (!_clipboard.valid) {
            return "";
        }

        if (_clipboard.isStale(_staleTimeout)) {
            _clipboard.valid = false;
            return "";
        }

        return _clipboard.text;
    }

    /**
     * Middle-click paste behavior.
     * Returns: Text to paste on middle-click based on sync mode.
     */
    string getMiddleClickPaste() {
        // Primary modes: prefer PRIMARY
        if (_syncMode == SelectionSyncMode.PrimaryOnly ||
            _syncMode == SelectionSyncMode.Separate ||
            _syncMode == SelectionSyncMode.AutoCopyPrimary) {
            string primary = getPrimary();
            if (primary.length > 0) {
                return primary;
            }
        }

        // Fallback to CLIPBOARD
        return getClipboard();
    }

    /**
     * Ctrl+V paste behavior.
     * Returns: Text to paste on Ctrl+V based on sync mode.
     */
    string getCtrlVPaste() {
        if (_syncMode == SelectionSyncMode.PrimaryOnly) {
            // In PrimaryOnly mode, Ctrl+V uses PRIMARY
            return getPrimary();
        }

        // Standard mode: use CLIPBOARD, fallback to PRIMARY
        string clipboard = getClipboard();
        if (clipboard.length > 0) {
            return clipboard;
        }

        return getPrimary();
    }

    /**
     * Clear PRIMARY selection.
     */
    void clearPrimary() {
        _primary.valid = false;
        _primary.text = "";
    }

    /**
     * Clear CLIPBOARD selection.
     */
    void clearClipboard() {
        _clipboard.valid = false;
        _clipboard.text = "";
    }

    /**
     * Clear both selections.
     */
    void clearAll() {
        clearPrimary();
        clearClipboard();
    }

    /**
     * Check if PRIMARY is available and valid.
     */
    bool hasPrimary() const {
        return _primary.valid && _primary.text.length > 0;
    }

    /**
     * Check if CLIPBOARD is available and valid.
     */
    bool hasClipboard() const {
        if (_syncMode == SelectionSyncMode.PrimaryOnly) {
            return false;
        }
        return _clipboard.valid && _clipboard.text.length > 0;
    }

    /**
     * Get size of PRIMARY selection in bytes.
     */
    size_t getPrimarySize() const {
        return _primary.size();
    }

    /**
     * Get size of CLIPBOARD in bytes.
     */
    size_t getClipboardSize() const {
        return _clipboard.size();
    }

    /**
     * Get metadata about PRIMARY selection.
     */
    SelectionContent getPrimaryMetadata() const {
        return _primary;
    }

    /**
     * Get metadata about CLIPBOARD.
     */
    SelectionContent getClipboardMetadata() const {
        return _clipboard;
    }

    /**
     * Detect if selections conflict (different content).
     * Returns: true if PRIMARY and CLIPBOARD differ significantly.
     */
    bool hasConflict() const {
        if (!hasPrimary() || !hasClipboard()) {
            return false; // No conflict if either is empty
        }

        // Conflict if different text (allow minor differences like whitespace)
        return _primary.text != _clipboard.text;
    }

    /**
     * Resolve conflict by preferring one selection.
     * Params:
     *   preferPrimary = true to use PRIMARY, false to use CLIPBOARD
     */
    void resolveConflict(bool preferPrimary) {
        if (preferPrimary) {
            if (hasPrimary()) {
                _clipboard.text = _primary.text;
                _clipboard.timestamp = _primary.timestamp;
            }
        } else {
            if (hasClipboard()) {
                _primary.text = _clipboard.text;
                _primary.timestamp = _clipboard.timestamp;
            }
        }
    }

    /**
     * Set stale timeout in seconds.
     * Selections older than this are considered invalid.
     */
    void setStaleTimeout(uint seconds) {
        _staleTimeout = seconds;
    }

    /**
     * Get current stale timeout.
     */
    uint getStaleTimeout() const {
        return _staleTimeout;
    }

    /**
     * Synchronize PRIMARY to CLIPBOARD (copy).
     */
    void syncPrimaryToClipboard() {
        if (hasPrimary()) {
            setClipboard(_primary.text, "primary-sync");
        }
    }

    /**
     * Synchronize CLIPBOARD to PRIMARY.
     */
    void syncClipboardToPrimary() {
        if (hasClipboard()) {
            setPrimary(_clipboard.text, "clipboard-sync");
        }
    }

    /**
     * Get selection statistics for debugging.
     */
    string getStats() {
        string stats = "Selection Manager Stats:\n";
        stats ~= "  Mode: " ~ syncModeToString(_syncMode) ~ "\n";
        stats ~= "  PRIMARY: " ~ (hasPrimary() ? "valid" : "empty") ~ " (" ~ getPrimarySize().to!string ~ " bytes)\n";
        stats ~= "  CLIPBOARD: " ~ (hasClipboard() ? "valid" : "empty") ~ " (" ~ getClipboardSize().to!string ~ " bytes)\n";
        stats ~= "  Conflict: " ~ (hasConflict() ? "yes" : "no") ~ "\n";
        return stats;
    }

private:
    string syncModeToString(SelectionSyncMode mode) const {
        final switch (mode) {
            case SelectionSyncMode.Separate:
                return "Separate";
            case SelectionSyncMode.AutoCopyPrimary:
                return "AutoCopyPrimary";
            case SelectionSyncMode.PrimaryOnly:
                return "PrimaryOnly";
            case SelectionSyncMode.ClipboardOnly:
                return "ClipboardOnly";
        }
    }
}
