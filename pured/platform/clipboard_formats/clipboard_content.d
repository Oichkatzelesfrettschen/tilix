/**
 * Clipboard Content Representation
 *
 * Represents clipboard data with MIME type, metadata, and conversion support.
 * Enables storage of multiple formats and automatic fallback.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.platform.clipboard_formats.clipboard_content;

version (PURE_D_BACKEND):

import pured.platform.clipboard_formats.mime_types;
import std.datetime : SysTime, Clock;

/**
 * Result type for operations that may fail.
 * Params: T = Success value type
 */
struct Result(T) {
    /// Whether operation succeeded
    bool success;

    /// Success value (if success == true)
    T value;

    /// Error message (if success == false)
    string error;

    /**
     * Create success result.
     */
    static Result!T ok(T value) {
        return Result!T(true, value, "");
    }

    /**
     * Create error result.
     */
    static Result!T err(string error) {
        return Result!T(false, T.init, error);
    }
}

/**
 * Clipboard content with MIME type and metadata.
 */
class ClipboardContent {
private:
    ubyte[] _data;
    string _mimeType;
    string _source;
    SysTime _timestamp;
    string[string] _metadata;
    int _precedence = 0;

public:
    /**
     * Create clipboard content.
     * Params:
     *   data = Binary content data
     *   mimeType = MIME type string (e.g., "text/plain")
     *   source = Origin of clipboard data (e.g., "selection", "clipboard")
     */
    this(ubyte[] data, string mimeType, string source = "clipboard") {
        _data = data.dup;
        _mimeType = mimeType;
        _source = source;
        _timestamp = Clock.currTime();
    }

    /**
     * Get raw data.
     */
    const(ubyte)[] getData() const {
        return cast(const(ubyte)[])_data;
    }

    /**
     * Get data as string (for text formats).
     * Returns: String representation, or empty if binary format.
     */
    string getAsString() const {
        if (_mimeType.startsWith("text/")) {
            return cast(string)_data.idup;
        }
        return "";
    }

    /**
     * Get MIME type.
     */
    string getMimeType() const {
        return _mimeType;
    }

    /**
     * Get source of clipboard data.
     */
    string getSource() const {
        return _source;
    }

    /**
     * Get timestamp of clipboard content.
     */
    SysTime getTimestamp() const {
        return _timestamp;
    }

    /**
     * Get size of clipboard content.
     */
    size_t getSize() const {
        return _data.length;
    }

    /**
     * Check if this is a text format.
     */
    bool isTextFormat() const {
        return _mimeType.startsWith("text/");
    }

    /**
     * Check if this is an image format.
     */
    bool isImageFormat() const {
        return _mimeType.startsWith("image/");
    }

    /**
     * Set metadata value.
     * Params:
     *   key = Metadata key
     *   value = Metadata value
     */
    void setMetadata(string key, string value) {
        _metadata[key] = value;
    }

    /**
     * Get metadata value.
     * Params:
     *   key = Metadata key
     *   defaultValue = Default if key not found
     * Returns: Metadata value or default.
     */
    string getMetadata(string key, string defaultValue = "") const {
        auto ptr = key in _metadata;
        return ptr ? *ptr : defaultValue;
    }

    /**
     * Set conversion precedence.
     * Higher precedence = preferred for conversion targets.
     */
    void setPrecedence(int precedence) {
        _precedence = precedence;
    }

    /**
     * Get conversion precedence.
     */
    int getPrecedence() const {
        return _precedence;
    }

    /**
     * Check if content equals another.
     */
    bool equals(ClipboardContent other) const {
        if (other is null) {
            return false;
        }
        return _data == other._data && _mimeType == other._mimeType;
    }

    /**
     * Create a copy of this content.
     */
    ClipboardContent dup() const {
        auto copy = new ClipboardContent(cast(ubyte[])_data.dup, _mimeType, _source);
        copy._timestamp = _timestamp;
        foreach (k, v; _metadata) copy._metadata[k] = v;
        copy._precedence = _precedence;
        return copy;
    }
}

/**
 * Multi-format clipboard content.
 * Stores same content in multiple MIME formats.
 */
class MultiFormatClipboardContent {
private:
    ClipboardContent[string] _formats;
    string _primaryFormat;

public:
    this() {
    }

    /**
     * Add format to clipboard content.
     * Params:
     *   content = Clipboard content in one format
     */
    void addFormat(ClipboardContent content) {
        if (content !is null) {
            _formats[content.getMimeType()] = content;

            // Set as primary if first format or text format
            if (_primaryFormat.length == 0 || content.isTextFormat()) {
                _primaryFormat = content.getMimeType();
            }
        }
    }

    /**
     * Get content for specific MIME type.
     * Params:
     *   mimeType = MIME type to retrieve
     * Returns: ClipboardContent or null if not available.
     */
    ClipboardContent getFormat(string mimeType) {
        auto ptr = mimeType in _formats;
        return ptr ? *ptr : null;
    }

    /**
     * Get primary format content.
     * Returns: ClipboardContent in primary format.
     */
    ClipboardContent getPrimary() {
        if (_primaryFormat.length > 0) {
            return getFormat(_primaryFormat);
        }
        if (_formats.length > 0) {
            return _formats.byValue.front;
        }
        return null;
    }

    /**
     * Get all available MIME types.
     * Returns: Array of MIME type strings.
     */
    string[] getAvailableMimes() {
        return _formats.keys;
    }

    /**
     * Check if format is available.
     */
    bool hasFormat(string mimeType) {
        return (mimeType in _formats) !is null;
    }

    /**
     * Get number of formats.
     */
    size_t getFormatCount() {
        return _formats.length;
    }

    /**
     * Clear all formats.
     */
    void clear() {
        _formats.clear();
        _primaryFormat = "";
    }
}

/**
 * Helper function to create text clipboard content.
 */
ClipboardContent createTextContent(string text, string source = "clipboard") {
    return new ClipboardContent(cast(ubyte[])text.dup, "text/plain", source);
}

/**
 * Helper function to create HTML clipboard content.
 */
ClipboardContent createHtmlContent(string html, string source = "clipboard") {
    return new ClipboardContent(cast(ubyte[])html.dup, "text/html", source);
}

/**
 * Helper function to create binary clipboard content.
 */
ClipboardContent createBinaryContent(ubyte[] data, string mimeType, string source = "clipboard") {
    return new ClipboardContent(data, mimeType, source);
}

private:
    bool startsWith(string str, string prefix) {
        return str.length >= prefix.length && str[0 .. prefix.length] == prefix;
    }
