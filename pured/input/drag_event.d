/**
 * Drag and Drop Event Handling
 *
 * Defines drag event structures and state management for drag-drop operations.
 * Coordinates drag enter/motion/leave/drop events with MIME type negotiation.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.input.drag_event;

version (PURE_D_BACKEND):

/**
 * Drag state enumeration.
 */
enum DragState {
    None,           /// No drag in progress
    Entered,        /// Drag source entered drop target
    Motion,         /// Drag source is moving over drop target
    Left,           /// Drag source left drop target
    Dropped,        /// Drop was performed
}

/**
 * Modifier keys during drag.
 */
struct DragModifiers {
    bool shift;
    bool control;
    bool alt;
    bool super_;    /// Windows/Meta key

    /**
     * Check if any modifier is pressed.
     */
    bool anyPressed() const {
        return shift || control || alt || super_;
    }

    /**
     * Check if copy modifier is pressed (Ctrl).
     */
    bool isCopy() const {
        return control;
    }

    /**
     * Check if move modifier is pressed (Shift).
     */
    bool isMove() const {
        return shift;
    }
}

/**
 * Drag event data.
 */
struct DragEvent {
    /// Current drag state
    DragState state;

    /// Mouse coordinates (screen relative)
    int x;
    int y;

    /// MIME types available in drag data
    string[] mimeTypes;

    /// Suggested action (copy, move, link)
    string suggestedAction = "copy";

    /// Keyboard modifiers
    DragModifiers modifiers;

    /// Time of event (milliseconds)
    ulong timestamp = 0;

    /// Whether drop is accepted
    bool accepted = false;

    /// Target MIME type for drop (if multiple types available)
    string targetMime = "";

    /**
     * Check if drag contains specific MIME type.
     */
    bool hasMimeType(string mimeType) const {
        foreach (mime; mimeTypes) {
            if (mime == mimeType) {
                return true;
            }
        }
        return false;
    }

    /**
     * Get best MIME type for terminal (prefers text/plain).
     */
    string getBestMimeType() const {
        // Prefer plain text
        foreach (mime; mimeTypes) {
            if (mime == "text/plain") {
                return mime;
            }
        }

        // Then prefer text formats
        foreach (mime; mimeTypes) {
            if (mime.length > 5 && mime[0 .. 5] == "text/") {
                return mime;
            }
        }

        // Otherwise file/URI types
        foreach (mime; mimeTypes) {
            if (mime == "text/uri-list") {
                return mime;
            }
        }

        // Finally images
        foreach (mime; mimeTypes) {
            if (mime.length > 6 && mime[0 .. 6] == "image/") {
                return mime;
            }
        }

        // Return first available
        return mimeTypes.length > 0 ? mimeTypes[0] : "";
    }
}

/**
 * Drag-drop target interface.
 */
interface IDragDropTarget {
    /**
     * Handle drag enter.
     * Params:
     *   event = Drag event with MIME types
     * Returns: true if drop is accepted.
     */
    bool onDragEnter(DragEvent event);

    /**
     * Handle drag motion.
     * Params:
     *   event = Drag event with current position
     * Returns: true if drop is still accepted.
     */
    bool onDragMotion(DragEvent event);

    /**
     * Handle drag leave.
     * Params:
     *   event = Drag event
     */
    void onDragLeave(DragEvent event);

    /**
     * Handle drop.
     * Params:
     *   event = Drag event
     *   data = Dropped data as byte array
     * Returns: true if drop was processed.
     */
    bool onDragDrop(DragEvent event, ubyte[] data);
}

/**
 * Drag-drop source interface.
 */
interface IDragDropSource {
    /**
     * Get available MIME types for drag.
     * Returns: Array of supported MIME types.
     */
    string[] getDragMimeTypes();

    /**
     * Get drag data for MIME type.
     * Params:
     *   mimeType = Requested MIME type
     * Returns: Data for the MIME type, or empty if not available.
     */
    ubyte[] getDragData(string mimeType);

    /**
     * Notify that drag has started.
     */
    void onDragStart();

    /**
     * Notify that drag has ended.
     * Params:
     *   action = Action that was performed (copy, move, link, or "")
     */
    void onDragEnd(string action);
}

/**
 * Drag-drop manager.
 * Coordinates drag-drop operations between source and target.
 */
class DragDropManager {
private:
    IDragDropSource _source;
    IDragDropTarget _target;
    DragState _currentState = DragState.None;
    string _targetMime = "";
    bool _isValid = false;

public:
    /**
     * Start drag operation from source.
     * Params:
     *   source = Drag source providing data
     */
    void startDrag(IDragDropSource source) {
        if (source is null) {
            return;
        }

        _source = source;
        _currentState = DragState.None;
        _targetMime = "";
        _isValid = false;

        _source.onDragStart();
    }

    /**
     * Handle drag enter on target.
     * Params:
     *   target = Drop target
     *   event = Drag event
     * Returns: true if drop is accepted.
     */
    bool handleDragEnter(IDragDropTarget target, DragEvent event) {
        _target = target;
        _currentState = DragState.Entered;

        if (target is null) {
            _isValid = false;
            return false;
        }

        _isValid = target.onDragEnter(event);
        if (_isValid && event.mimeTypes.length > 0) {
            _targetMime = event.getBestMimeType();
        }

        return _isValid;
    }

    /**
     * Handle drag motion on target.
     * Params:
     *   event = Drag event with new position
     * Returns: true if drop is still accepted.
     */
    bool handleDragMotion(DragEvent event) {
        if (_target is null) {
            return false;
        }

        _currentState = DragState.Motion;
        return _target.onDragMotion(event);
    }

    /**
     * Handle drag leave from target.
     * Params:
     *   event = Drag event
     */
    void handleDragLeave(DragEvent event) {
        if (_target !is null) {
            _currentState = DragState.Left;
            _target.onDragLeave(event);
        }
        _isValid = false;
    }

    /**
     * Handle drop on target.
     * Params:
     *   event = Drag event
     * Returns: true if drop was processed.
     */
    bool handleDragDrop(DragEvent event) {
        if (_target is null || _source is null || !_isValid) {
            return false;
        }

        _currentState = DragState.Dropped;

        // Get data from source for target MIME type
        string mimeType = event.targetMime.length > 0 ? event.targetMime : _targetMime;
        ubyte[] data = _source.getDragData(mimeType);

        if (data.length == 0) {
            return false;
        }

        // Deliver to target
        event.targetMime = mimeType;
        bool processed = _target.onDragDrop(event, data);

        // Notify source
        if (processed) {
            _source.onDragEnd(event.suggestedAction);
        } else {
            _source.onDragEnd("");
        }

        return processed;
    }

    /**
     * Get current drag state.
     */
    DragState getCurrentState() const {
        return _currentState;
    }

    /**
     * Check if drop is currently valid.
     */
    bool isValid() const {
        return _isValid;
    }

    /**
     * Cancel drag operation.
     */
    void cancel() {
        if (_source !is null) {
            _source.onDragEnd("");
        }

        _currentState = DragState.None;
        _source = null;
        _target = null;
        _isValid = false;
    }
}

/**
 * Helper to detect if MIME type is file-like.
 */
bool isMimeTypeFileFormat(string mimeType) {
    return mimeType == "text/uri-list" ||
           mimeType == "text/x-moz-url" ||
           mimeType.startsWith("application/");
}

/**
 * Helper to detect if MIME type is text format.
 */
bool isMimeTypeTextFormat(string mimeType) {
    return mimeType.startsWith("text/");
}

/**
 * Helper to detect if MIME type is image format.
 */
bool isMimeTypeImageFormat(string mimeType) {
    return mimeType.startsWith("image/");
}

private:
    bool startsWith(string str, string prefix) {
        return str.length >= prefix.length && str[0 .. prefix.length] == prefix;
    }
