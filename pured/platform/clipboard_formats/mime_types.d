/**
 * MIME Type Registry and Format Support
 *
 * Defines supported MIME types, priority ordering, and capability detection.
 * Enables negotiation of clipboard formats between applications.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.platform.clipboard_formats.mime_types;

version (PURE_D_BACKEND):

import std.array : array;
import std.algorithm : sort, canFind;

/**
 * MIME type enumeration for supported clipboard formats.
 */
enum MimeType {
    /// Plain text (fallback format, always supported)
    TextPlain,

    /// HTML with formatting
    TextHtml,

    /// URI list (file paths, URLs)
    TextUriList,

    /// Rich text format
    TextRtf,

    /// Image in PNG format
    ImagePng,

    /// Image in JPEG format
    ImageJpeg,

    /// Application-specific terminal format
    ApplicationTerminalUrl,

    /// Unknown or unsupported format
    Unknown
}

/**
 * MIME type metadata and properties.
 */
struct MimeTypeInfo {
    /// MIME type enumeration
    MimeType type;

    /// IANA MIME type string (e.g., "text/plain")
    string mimeString;

    /// Human-readable name
    string displayName;

    /// Priority for negotiation (higher = preferred)
    int priority;

    /// Whether this format can be pasted as text
    bool isTextFormat;

    /// Whether this format can be pasted as file
    bool isFileFormat;

    /// Whether this format can be pasted as image
    bool isImageFormat;
}

/**
 * MIME type registry with metadata.
 */
immutable MimeTypeInfo[] MIME_TYPE_REGISTRY = [
    // Text formats (highest priority)
    MimeTypeInfo(
        MimeType.TextPlain,
        "text/plain",
        "Plain Text",
        100,
        true, false, false
    ),
    MimeTypeInfo(
        MimeType.TextHtml,
        "text/html",
        "HTML",
        90,
        true, false, false
    ),
    MimeTypeInfo(
        MimeType.TextRtf,
        "text/rtf",
        "Rich Text",
        85,
        true, false, false
    ),

    // URI and file formats
    MimeTypeInfo(
        MimeType.TextUriList,
        "text/uri-list",
        "URI List",
        80,
        false, true, false
    ),

    // Application-specific
    MimeTypeInfo(
        MimeType.ApplicationTerminalUrl,
        "application/x-tilix-terminal-url",
        "Terminal URL",
        95,
        true, false, false
    ),

    // Image formats (lower priority for terminal)
    MimeTypeInfo(
        MimeType.ImagePng,
        "image/png",
        "PNG Image",
        50,
        false, true, true
    ),
    MimeTypeInfo(
        MimeType.ImageJpeg,
        "image/jpeg",
        "JPEG Image",
        45,
        false, true, true
    ),

    // Unknown format
    MimeTypeInfo(
        MimeType.Unknown,
        "unknown",
        "Unknown",
        0,
        false, false, false
    )
];

/**
 * Get MIME type info by enumeration.
 * Params:
 *   type = MIME type enumeration
 * Returns: MIME type information, or Unknown if not found.
 */
MimeTypeInfo getMimeInfo(MimeType type) {
    foreach (info; MIME_TYPE_REGISTRY) {
        if (info.type == type) {
            return info;
        }
    }
    return MIME_TYPE_REGISTRY[$ - 1]; // Return Unknown
}

/**
 * Get MIME type by IANA string.
 * Params:
 *   mimeString = MIME type string (e.g., "text/plain")
 * Returns: MIME type enumeration, or Unknown if not recognized.
 */
MimeType getMimeType(string mimeString) {
    foreach (info; MIME_TYPE_REGISTRY) {
        if (info.mimeString == mimeString) {
            return info.type;
        }
    }
    return MimeType.Unknown;
}

/**
 * Get MIME string by enumeration.
 * Params:
 *   type = MIME type enumeration
 * Returns: IANA MIME type string.
 */
string getMimeString(MimeType type) {
    return getMimeInfo(type).mimeString;
}

/**
 * Terminal clipboard capability checker.
 * Determines what formats the terminal can paste.
 */
class TerminalClipboardCapabilities {
private:
    MimeType[] _supportedFormats;
    bool _canPasteText = true;
    bool _canPasteFiles = false;
    bool _canPasteImages = false;

public:
    this() {
        // Terminal can always paste plain text
        _supportedFormats = [MimeType.TextPlain];

        // Terminal can paste file paths as text (convert to string paths)
        _canPasteFiles = true;

        // Terminal can paste images as file references/URLs
        _canPasteImages = true;
    }

    /**
     * Check if terminal can handle this MIME type.
     * Params:
     *   type = MIME type to check
     * Returns: true if terminal can paste this format.
     */
    bool canHandle(MimeType type) {
        return _supportedFormats.canFind(type) || type == MimeType.TextPlain;
    }

    /**
     * Check if terminal can paste text formats.
     */
    bool canPasteText() const {
        return _canPasteText;
    }

    /**
     * Check if terminal can paste file paths.
     */
    bool canPasteFiles() const {
        return _canPasteFiles;
    }

    /**
     * Check if terminal can paste images (as paths/URLs).
     */
    bool canPasteImages() const {
        return _canPasteImages;
    }

    /**
     * Get all supported MIME types in priority order.
     * Returns: Array of supported MIME type strings.
     */
    string[] getSupportedMimes() {
        string[] result;

        // Collect all supported MIME types and sort by priority (descending)
        MimeTypeInfo[] infos;
        foreach (info; MIME_TYPE_REGISTRY) {
            if (info.type != MimeType.Unknown && canHandle(info.type)) {
                infos ~= info;
            }
        }

        // Sort by priority descending
        sort!((a, b) => a.priority > b.priority)(infos);

        foreach (info; infos) {
            result ~= info.mimeString;
        }

        return result;
    }

    /**
     * Advertise capability for clipboard negotiation.
     * Returns: Array of MIME types terminal can accept.
     */
    string[] advertiseCapabilities() {
        // Start with preferred formats
        string[] preferred = [
            "text/plain",
            "text/html",
            "text/uri-list",
            "application/x-tilix-terminal-url",
            "image/png",
            "image/jpeg"
        ];

        return preferred;
    }
}

/**
 * Format conversion capability checker.
 * Determines what format conversions are supported.
 */
class FormatConversionCapabilities {
private:
    /// Map of (from, to) supported conversions
    bool[string][string] _conversions;

public:
    this() {
        // Initialize supported conversions
        initConversions();
    }

private:
    void initConversions() {
        // HTML can be converted to plain text (strip tags)
        addConversion("text/html", "text/plain");

        // Plain text can be converted to HTML (escape + wrap)
        addConversion("text/plain", "text/html");

        // URI list can be converted to plain text (extract first URI)
        addConversion("text/uri-list", "text/plain");

        // Images can be converted to URI (file reference)
        addConversion("image/png", "text/plain");
        addConversion("image/png", "text/uri-list");
        addConversion("image/jpeg", "text/plain");
        addConversion("image/jpeg", "text/uri-list");

        // Terminal URLs can be converted to plain text
        addConversion("application/x-tilix-terminal-url", "text/plain");
    }

    void addConversion(string from, string to) {
        if (from !in _conversions) {
            _conversions[from] = (bool[string]).init;
        }
        _conversions[from][to] = true;
    }

public:
    /**
     * Check if format conversion is supported.
     * Params:
     *   from = Source MIME type
     *   to = Destination MIME type
     * Returns: true if conversion is possible.
     */
    bool canConvert(string from, string to) {
        if (from == to) {
            return true; // Same format, no conversion needed
        }

        if (from !in _conversions) {
            return false;
        }

        return _conversions[from].get(to, false);
    }

    /**
     * Get conversion priority (lower = more lossy).
     * Params:
     *   from = Source MIME type
     *   to = Destination MIME type
     * Returns: Quality score (100 = lossless, 0 = impossible).
     */
    int getConversionQuality(string from, string to) {
        if (from == to) {
            return 100; // No conversion
        }

        if (!canConvert(from, to)) {
            return 0;
        }

        // Lossless conversions
        if ((from == "text/plain" && to == "text/html") ||
            (from == "text/html" && to == "text/plain")) {
            return 90; // Minor information loss (HTML structure)
        }

        if ((from == "text/uri-list" && to == "text/plain") ||
            (from == "text/plain" && to == "text/uri-list")) {
            return 85; // May lose multiple URIs or formatting
        }

        if ((from == "image/png" || from == "image/jpeg") &&
            (to == "text/plain" || to == "text/uri-list")) {
            return 70; // Converts image to path reference
        }

        return 50; // Default quality for supported conversions
    }

    /**
     * Get best conversion path between formats.
     * Params:
     *   from = Source MIME type
     *   to = Destination MIME type
     * Returns: Array of intermediate MIME types (empty if direct conversion).
     */
    string[] getConversionPath(string from, string to) {
        if (from == to || canConvert(from, to)) {
            return [];
        }

        // Simple fallback path via text/plain
        if (canConvert(from, "text/plain") && canConvert("text/plain", to)) {
            return ["text/plain"];
        }

        return []; // No path found
    }
}
