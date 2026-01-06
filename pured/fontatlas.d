/**
 * Font Atlas for Terminal Rendering
 *
 * Uses FreeType to render glyphs into a texture atlas for GPU-accelerated
 * terminal rendering. Supports ASCII and extended Unicode characters.
 *
 * Key features:
 * - FreeType font loading and rasterization
 * - Texture atlas packing for efficient GPU rendering
 * - Glyph metrics for proper positioning
 * - Dynamic glyph addition for Unicode support
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.fontatlas;

version (PURE_D_BACKEND):

import bindbc.opengl;
import bindbc.freetype;
import std.stdio : stderr, writefln;
import std.string : toStringz;

/**
 * Glyph metrics and atlas position.
 */
struct GlyphInfo {
    // Texture coordinates in atlas (normalized 0-1)
    float u0, v0;  // Top-left
    float u1, v1;  // Bottom-right

    // Glyph metrics in pixels
    int width;
    int height;
    int bearingX;  // Offset from baseline to left edge
    int bearingY;  // Offset from baseline to top edge
    int advance;   // Horizontal advance to next glyph

    bool valid;    // Whether this glyph was successfully loaded
}

/**
 * Font atlas for terminal glyph rendering.
 *
 * Renders font glyphs into a texture atlas for efficient GPU rendering.
 */
class FontAtlas {
private:
    FT_Library _ftLibrary;
    FT_Face _ftFace;
    GLuint _textureId;

    int _atlasWidth;
    int _atlasHeight;
    int _cellWidth;
    int _cellHeight;
    int _fontSize;

    // Glyph cache (ASCII + extended)
    GlyphInfo[256] _glyphCache;

    // Atlas packing state
    int _cursorX;
    int _cursorY;
    int _rowHeight;

public:
    /**
     * Initialize the font atlas.
     *
     * Params:
     *   fontPath = Path to TTF/OTF font file
     *   fontSize = Font size in pixels
     *
     * Returns: true if initialization succeeded
     */
    bool initialize(string fontPath = null, int fontSize = 16) {
        _fontSize = fontSize;

        // Initialize FreeType
        auto ftLoader = loadFreeType();
        if (ftLoader == FTSupport.noLibrary) {
            stderr.writefln("Warning: FreeType library not found");
        } else if (ftLoader == FTSupport.badLibrary) {
            stderr.writefln("Warning: FreeType library failed to load");
        }

        if (FT_Init_FreeType(&_ftLibrary) != 0) {
            stderr.writefln("Error: Failed to initialize FreeType");
            return false;
        }

        // Load font
        if (fontPath is null || fontPath.length == 0) {
            // Try common monospace fonts
            static immutable string[] defaultFonts = [
                "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
                "/usr/share/fonts/liberation-mono/LiberationMono-Regular.ttf",
                "/usr/share/fonts/TTF/LiberationMono-Regular.ttf",
                "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
                "/usr/share/fonts/noto/NotoSansMono-Regular.ttf",
                "/usr/share/fonts/TTF/Hack-Regular.ttf",
            ];

            foreach (path; defaultFonts) {
                if (FT_New_Face(_ftLibrary, path.toStringz, 0, &_ftFace) == 0) {
                    stderr.writefln("Loaded font: %s", path);
                    break;
                }
            }

            if (_ftFace is null) {
                stderr.writefln("Error: Could not find a monospace font");
                return false;
            }
        } else {
            if (FT_New_Face(_ftLibrary, fontPath.toStringz, 0, &_ftFace) != 0) {
                stderr.writefln("Error: Failed to load font: %s", fontPath);
                return false;
            }
        }

        // Set font size
        FT_Set_Pixel_Sizes(_ftFace, 0, fontSize);

        // Calculate cell dimensions from font metrics
        _cellWidth = cast(int)(_ftFace.size.metrics.max_advance >> 6);
        _cellHeight = cast(int)((_ftFace.size.metrics.height >> 6) + 2);

        // If max_advance is 0, estimate from 'M' glyph
        if (_cellWidth <= 0) {
            if (FT_Load_Char(_ftFace, 'M', FT_LOAD_RENDER) == 0) {
                _cellWidth = cast(int)(_ftFace.glyph.advance.x >> 6);
            } else {
                _cellWidth = fontSize;  // Fallback
            }
        }
        if (_cellHeight <= 0) {
            _cellHeight = cast(int)(fontSize * 1.5);
        }

        stderr.writefln("Font metrics: cell=%dx%d, fontSize=%d", _cellWidth, _cellHeight, fontSize);

        // Create texture atlas (16x16 grid of cells = 256 glyphs)
        _atlasWidth = _cellWidth * 16;
        _atlasHeight = _cellHeight * 16;

        // Create OpenGL texture
        glGenTextures(1, &_textureId);
        glBindTexture(GL_TEXTURE_2D, _textureId);

        // Allocate texture
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, _atlasWidth, _atlasHeight, 0,
                     GL_RED, GL_UNSIGNED_BYTE, null);

        // Set texture parameters
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

        // Disable byte-alignment restriction
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

        // Pre-render ASCII characters (32-126)
        _cursorX = 0;
        _cursorY = 0;
        _rowHeight = 0;

        foreach (c; 32 .. 127) {
            renderGlyph(cast(dchar)c);
        }

        glBindTexture(GL_TEXTURE_2D, 0);

        return true;
    }

    /**
     * Cleanup resources.
     */
    void terminate() {
        if (_textureId != 0) {
            glDeleteTextures(1, &_textureId);
            _textureId = 0;
        }
        if (_ftFace !is null) {
            FT_Done_Face(_ftFace);
            _ftFace = null;
        }
        if (_ftLibrary !is null) {
            FT_Done_FreeType(_ftLibrary);
            _ftLibrary = null;
        }
    }

    /**
     * Get glyph info for a character.
     *
     * Returns cached info or renders the glyph if not cached.
     */
    GlyphInfo getGlyph(dchar codepoint) {
        // For ASCII, use direct cache
        if (codepoint < 256) {
            if (!_glyphCache[codepoint].valid && codepoint >= 32) {
                renderGlyph(codepoint);
            }
            return _glyphCache[codepoint];
        }

        // For non-ASCII, return space glyph for now
        // TODO: Implement dynamic Unicode glyph caching
        return _glyphCache[' '];
    }

    /**
     * Bind the atlas texture.
     */
    void bind(int textureUnit = 0) {
        glActiveTexture(GL_TEXTURE0 + textureUnit);
        glBindTexture(GL_TEXTURE_2D, _textureId);
    }

    /// Cell width in pixels
    @property int cellWidth() const { return _cellWidth; }

    /// Cell height in pixels
    @property int cellHeight() const { return _cellHeight; }

    /// OpenGL texture ID
    @property GLuint textureId() const { return _textureId; }

private:
    /**
     * Render a glyph and add to atlas.
     */
    void renderGlyph(dchar codepoint) {
        if (codepoint >= 256) return;  // Only cache ASCII for now

        if (FT_Load_Char(_ftFace, codepoint, FT_LOAD_RENDER) != 0) {
            // Failed to load - mark as invalid
            _glyphCache[codepoint].valid = false;
            return;
        }

        auto glyph = _ftFace.glyph;
        auto bitmap = glyph.bitmap;

        // Check if we need to move to next row
        if (_cursorX + _cellWidth > _atlasWidth) {
            _cursorX = 0;
            _cursorY += _rowHeight;
            _rowHeight = 0;
        }

        // Upload glyph bitmap to texture
        if (bitmap.buffer !is null && bitmap.width > 0 && bitmap.rows > 0) {
            glBindTexture(GL_TEXTURE_2D, _textureId);
            glTexSubImage2D(GL_TEXTURE_2D, 0,
                           _cursorX, _cursorY,
                           bitmap.width, bitmap.rows,
                           GL_RED, GL_UNSIGNED_BYTE, bitmap.buffer);
        }

        // Store glyph info
        GlyphInfo info;
        info.u0 = cast(float)_cursorX / _atlasWidth;
        info.v0 = cast(float)_cursorY / _atlasHeight;
        info.u1 = cast(float)(_cursorX + bitmap.width) / _atlasWidth;
        info.v1 = cast(float)(_cursorY + bitmap.rows) / _atlasHeight;
        info.width = bitmap.width;
        info.height = bitmap.rows;
        info.bearingX = glyph.bitmap_left;
        info.bearingY = glyph.bitmap_top;
        info.advance = cast(int)(glyph.advance.x >> 6);
        info.valid = true;

        _glyphCache[codepoint] = info;

        // Advance cursor
        _cursorX += _cellWidth;
        if (bitmap.rows > _rowHeight) {
            _rowHeight = bitmap.rows;
        }
    }
}
