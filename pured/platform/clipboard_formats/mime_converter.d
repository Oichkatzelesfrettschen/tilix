/**
 * MIME Type Format Converters
 *
 * Implements conversion between different clipboard formats:
 * - HTML to plain text (strip tags)
 * - Plain text to HTML (escape and wrap)
 * - URI list parsing and generation
 * - Image format detection and path extraction
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.platform.clipboard_formats.mime_converter;

version (PURE_D_BACKEND):

import pured.platform.clipboard_formats.mime_types;
import pured.platform.clipboard_formats.clipboard_content;
import std.string : startsWith, endsWith, strip, split, join;
import std.algorithm : filter, map, find;
import std.array : appender;
import std.path : isAbsolute;
import std.uri : encode, decode;

/**
 * MIME format converter.
 */
interface IMimeConverter {
    /**
     * Convert content from one format to another.
     * Params:
     *   source = Source content with MIME type
     *   targetMimeType = Target MIME type
     * Returns: Result with converted content.
     */
    Result!ClipboardContent convert(ClipboardContent source, string targetMimeType);

    /**
     * Check if this converter can handle conversion.
     */
    bool canConvert(string fromMimeType, string toMimeType);
}

/**
 * HTML to Plain Text converter.
 * Strips HTML tags and decodes entities.
 */
class HtmlToPlainConverter : IMimeConverter {
    override bool canConvert(string from, string to) {
        return from == "text/html" && to == "text/plain";
    }

    override Result!ClipboardContent convert(ClipboardContent source, string targetMimeType) {
        if (!canConvert(source.getMimeType(), targetMimeType)) {
            return Result!ClipboardContent.err("Cannot convert HTML to " ~ targetMimeType);
        }

        string html = source.getAsString();
        string plainText = stripHtmlTags(html);
        plainText = decodeHtmlEntities(plainText);

        auto result = new ClipboardContent(cast(ubyte[])plainText.dup, "text/plain", source.getSource());
        return Result!ClipboardContent.ok(result);
    }

private:
    string stripHtmlTags(string html) {
        auto buf = appender!string();
        bool inTag = false;

        foreach (char c; html) {
            if (c == '<') {
                inTag = true;
                // Preserve newline-like behavior for block elements
                if (buf.data.length > 0 && buf.data[$ - 1] != '\n') {
                    buf.put(' ');
                }
            } else if (c == '>') {
                inTag = false;
            } else if (!inTag) {
                buf.put(c);
            }
        }

        string result = buf.data;
        // Clean up multiple spaces
        while (result.find("  ").length > 0) {
            result = replaceAll(result, "  ", " ");
        }
        return result.strip();
    }

    string decodeHtmlEntities(string text) {
        string result = text;
        result = replaceAll(result, "&lt;", "<");
        result = replaceAll(result, "&gt;", ">");
        result = replaceAll(result, "&amp;", "&");
        result = replaceAll(result, "&quot;", "\"");
        result = replaceAll(result, "&apos;", "'");
        result = replaceAll(result, "&nbsp;", " ");
        return result;
    }
}

/**
 * Plain Text to HTML converter.
 * Escapes special characters and wraps in <pre> tag.
 */
class PlainToHtmlConverter : IMimeConverter {
    override bool canConvert(string from, string to) {
        return from == "text/plain" && to == "text/html";
    }

    override Result!ClipboardContent convert(ClipboardContent source, string targetMimeType) {
        if (!canConvert(source.getMimeType(), targetMimeType)) {
            return Result!ClipboardContent.err("Cannot convert plain text to " ~ targetMimeType);
        }

        string plain = source.getAsString();
        string html = escapeHtml(plain);
        html = "<pre style=\"font-family: monospace; white-space: pre-wrap;\">" ~ html ~ "</pre>";

        auto result = new ClipboardContent(cast(ubyte[])html.dup, "text/html", source.getSource());
        return Result!ClipboardContent.ok(result);
    }

private:
    string escapeHtml(string text) {
        string result = text;
        result = replaceAll(result, "&", "&amp;");
        result = replaceAll(result, "<", "&lt;");
        result = replaceAll(result, ">", "&gt;");
        result = replaceAll(result, "\"", "&quot;");
        result = replaceAll(result, "'", "&apos;");
        return result;
    }
}

/**
 * URI List to Plain Text converter.
 * Extracts first URI or concatenates all URIs.
 */
class UriListToPlainConverter : IMimeConverter {
    override bool canConvert(string from, string to) {
        return from == "text/uri-list" && to == "text/plain";
    }

    override Result!ClipboardContent convert(ClipboardContent source, string targetMimeType) {
        if (!canConvert(source.getMimeType(), targetMimeType)) {
            return Result!ClipboardContent.err("Cannot convert URI list to " ~ targetMimeType);
        }

        string uriList = source.getAsString();
        auto uris = parseUriList(uriList);

        string plainText;
        if (uris.length > 0) {
            plainText = uris[0]; // Use first URI
        }

        auto result = new ClipboardContent(cast(ubyte[])plainText.dup, "text/plain", source.getSource());
        return Result!ClipboardContent.ok(result);
    }

private:
    string[] parseUriList(string uriListText) {
        auto result = appender!(string[])();

        foreach (line; uriListText.split("\n")) {
            line = line.strip();
            if (line.length == 0 || line.startsWith("#")) {
                continue; // Skip empty lines and comments
            }

            // Convert file:// URI to local path
            if (line.startsWith("file://")) {
                try {
                    line = decode(line[7 .. $]); // Remove file:// prefix and decode
                } catch (Exception e) {
                    // Keep original if decode fails
                }
            }

            result.put(line);
        }

        return result.data;
    }
}

/**
 * Plain Text to URI List converter.
 * Wraps text as file:// URI if it's a path.
 */
class PlainToUriListConverter : IMimeConverter {
    override bool canConvert(string from, string to) {
        return from == "text/plain" && to == "text/uri-list";
    }

    override Result!ClipboardContent convert(ClipboardContent source, string targetMimeType) {
        if (!canConvert(source.getMimeType(), targetMimeType)) {
            return Result!ClipboardContent.err("Cannot convert plain text to " ~ targetMimeType);
        }

        string text = source.getAsString().strip();
        string uriList;

        // If text is a path, convert to file:// URI
        if (isAbsolute(text)) {
            try {
                uriList = "file://" ~ encode(text) ~ "\n";
            } catch (Exception e) {
                uriList = "file://" ~ text ~ "\n"; // Fallback to unencoded
            }
        } else if (text.startsWith("http://") || text.startsWith("https://")) {
            uriList = text ~ "\n";
        } else {
            // Otherwise treat as a local path
            uriList = "file://" ~ text ~ "\n";
        }

        auto result = new ClipboardContent(cast(ubyte[])uriList.dup, "text/uri-list", source.getSource());
        return Result!ClipboardContent.ok(result);
    }
}

/**
 * Image to URI List converter.
 * Converts image data to file:// URI referencing temp file.
 */
class ImageToUriConverter : IMimeConverter {
    override bool canConvert(string from, string to) {
        return (from == "image/png" || from == "image/jpeg") && to == "text/uri-list";
    }

    override Result!ClipboardContent convert(ClipboardContent source, string targetMimeType) {
        if (!canConvert(source.getMimeType(), targetMimeType)) {
            return Result!ClipboardContent.err("Cannot convert image to " ~ targetMimeType);
        }

        // Generate a temp file path for the image
        string tmpPath = generateTempImagePath(source.getMimeType());

        // Note: Actual file writing would happen in clipboard integration
        // Here we just generate the URI reference
        string uriList = "file://" ~ tmpPath ~ "\n";

        auto result = new ClipboardContent(cast(ubyte[])uriList.dup, "text/uri-list", source.getSource());
        result.setMetadata("imageData", "true");
        result.setMetadata("imageTempPath", tmpPath);
        return Result!ClipboardContent.ok(result);
    }

private:
    string generateTempImagePath(string mimeType) {
        import std.random : uniform;
        import std.conv : to;

        string ext = mimeType == "image/png" ? ".png" : ".jpg";
        uint rand = uniform!uint();
        string filename = "clipboard_" ~ rand.to!string ~ ext;
        return "/tmp/" ~ filename;
    }
}

/**
 * Image to Plain Text converter.
 * Converts image to file path reference.
 */
class ImageToPlainConverter : IMimeConverter {
    override bool canConvert(string from, string to) {
        return (from == "image/png" || from == "image/jpeg") && to == "text/plain";
    }

    override Result!ClipboardContent convert(ClipboardContent source, string targetMimeType) {
        if (!canConvert(source.getMimeType(), targetMimeType)) {
            return Result!ClipboardContent.err("Cannot convert image to " ~ targetMimeType);
        }

        string tmpPath = generateTempImagePath(source.getMimeType());
        string plainText = tmpPath;

        auto result = new ClipboardContent(cast(ubyte[])plainText.dup, "text/plain", source.getSource());
        result.setMetadata("imageData", "true");
        result.setMetadata("imageTempPath", tmpPath);
        return Result!ClipboardContent.ok(result);
    }

private:
    string generateTempImagePath(string mimeType) {
        import std.random : uniform;
        import std.conv : to;

        string ext = mimeType == "image/png" ? ".png" : ".jpg";
        uint rand = uniform!uint();
        string filename = "clipboard_" ~ rand.to!string ~ ext;
        return "/tmp/" ~ filename;
    }
}

/**
 * MIME format converter manager.
 * Coordinates format conversion with fallbacks.
 */
class MimeConverterManager {
private:
    IMimeConverter[] _converters;
    FormatConversionCapabilities _capabilities;

public:
    this() {
        _capabilities = new FormatConversionCapabilities();
        registerConverters();
    }

private:
    void registerConverters() {
        _converters ~= new HtmlToPlainConverter();
        _converters ~= new PlainToHtmlConverter();
        _converters ~= new UriListToPlainConverter();
        _converters ~= new PlainToUriListConverter();
        _converters ~= new ImageToUriConverter();
        _converters ~= new ImageToPlainConverter();
    }

public:
    /**
     * Convert clipboard content to target MIME type.
     * Params:
     *   source = Source content
     *   targetMimeType = Target MIME type
     * Returns: Converted content or error.
     */
    Result!ClipboardContent convert(ClipboardContent source, string targetMimeType) {
        if (source.getMimeType() == targetMimeType) {
            return Result!ClipboardContent.ok(source); // Already target format
        }

        // Find matching converter
        foreach (converter; _converters) {
            if (converter.canConvert(source.getMimeType(), targetMimeType)) {
                return converter.convert(source, targetMimeType);
            }
        }

        return Result!ClipboardContent.err(
            "No converter available for " ~ source.getMimeType() ~ " -> " ~ targetMimeType
        );
    }

    /**
     * Find best format for terminal to paste.
     * Params:
     *   availableMimes = MIME types available in clipboard
     * Returns: Best format for terminal to paste.
     */
    string findBestFormat(string[] availableMimes) {
        // Prefer plain text (always supported)
        foreach (mime; availableMimes) {
            if (mime == "text/plain") {
                return mime;
            }
        }

        // Otherwise pick first available
        if (availableMimes.length > 0) {
            return availableMimes[0];
        }

        return "text/plain"; // Fallback
    }
}

/**
 * Helper function to replace all occurrences of substring.
 */
private string replaceAll(string str, string from, string to) {
    import std.string : indexOf;
    string result = str;
    size_t pos = 0;

    while ((pos = result.indexOf(from, pos)) != size_t.max) {
        result = result[0 .. pos] ~ to ~ result[pos + from.length .. $];
        pos += to.length;
    }

    return result;
}
