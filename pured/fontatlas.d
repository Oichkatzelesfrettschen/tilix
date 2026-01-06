/**
 * Font Atlas for Terminal Rendering
 *
 * Uses FreeType to render glyphs into a texture atlas for GPU-accelerated
 * terminal rendering. Supports ASCII and dynamic Unicode glyphs with LRU.
 *
 * Key features:
 * - FreeType font loading and rasterization
 * - Texture atlas grid packing
 * - Glyph metrics for proper positioning
 * - LRU cache for Unicode glyphs
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.fontatlas;

version (PURE_D_BACKEND):

import bindbc.opengl;
import bindbc.freetype;
import bindbc.fontconfig;
import bindbc.loader : LoadMsg;
import std.algorithm : min;
import std.file : exists;
import std.stdio : stderr, writefln;
import std.string : fromStringz, toStringz;

/**
 * Glyph metrics and atlas position.
 */
struct GlyphInfo {
    float u0, v0;
    float u1, v1;
    int width;
    int height;
    int bearingX;
    int bearingY;
    int advance;
    bool valid;
}

private enum ulong GlyphIndexFlag = 0x8000_0000_0000_0000UL;
private enum uint FaceIndexShift = 32;

/**
 * Font atlas for terminal glyph rendering.
 */
class FontAtlas {
private:
    FT_Library _ftLibrary;
    FT_Face _ftFace;
    FT_Face[] _fallbackFaces;
    string _primaryPath;
    GLuint _textureId;

    int _atlasWidth;
    int _atlasHeight;
    int _cellWidth;
    int _cellHeight;
    int _fontSize;
    int _atlasCols = 64;
    int _atlasRows = 64;
    int _reservedSlots = 256;
    int _slotCount;

    // ASCII glyph cache
    GlyphInfo[256] _glyphCache;

    // Dynamic glyph cache (Unicode + HarfBuzz glyph IDs)
    GlyphInfo[ulong] _glyphCacheMap;
    int[ulong] _glyphSlotMap;

    // LRU state for unicode slots
    ulong[] _slotKey;
    int[] _lruPrev;
    int[] _lruNext;
    int _lruHead = -1;
    int _lruTail = -1;
    int[] _freeSlots;

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

        if (fontPath is null || fontPath.length == 0) {
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
                    _primaryPath = path;
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
            _primaryPath = fontPath;
        }

        FT_Set_Pixel_Sizes(_ftFace, 0, fontSize);
        loadFallbackFaces(fontSize);

        _cellWidth = cast(int)(_ftFace.size.metrics.max_advance >> 6);
        _cellHeight = cast(int)((_ftFace.size.metrics.height >> 6) + 2);

        if (_cellWidth <= 0) {
            if (FT_Load_Char(_ftFace, 'M', FT_LOAD_RENDER) == 0) {
                _cellWidth = cast(int)(_ftFace.glyph.advance.x >> 6);
            } else {
                _cellWidth = fontSize;
            }
        }
        if (_cellHeight <= 0) {
            _cellHeight = cast(int)(fontSize * 1.5);
        }

        stderr.writefln("Font metrics: cell=%dx%d, fontSize=%d", _cellWidth, _cellHeight, fontSize);

        _slotCount = _atlasCols * _atlasRows;
        if (_reservedSlots > _slotCount) {
            _reservedSlots = _slotCount;
        }

        _atlasWidth = _cellWidth * _atlasCols;
        _atlasHeight = _cellHeight * _atlasRows;

        glGenTextures(1, &_textureId);
        glBindTexture(GL_TEXTURE_2D, _textureId);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, _atlasWidth, _atlasHeight, 0,
                     GL_RED, GL_UNSIGNED_BYTE, null);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

        initDynamicSlots();

        foreach (c; 32 .. 127) {
            renderAsciiGlyph(cast(dchar)c);
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
        foreach (face; _fallbackFaces) {
            if (face !is null) {
                FT_Done_Face(face);
            }
        }
        _fallbackFaces.length = 0;
        if (_ftLibrary !is null) {
            FT_Done_FreeType(_ftLibrary);
            _ftLibrary = null;
        }
    }

    /**
     * Get glyph info for a character.
     */
    GlyphInfo getGlyph(dchar codepoint) {
        if (codepoint < 256) {
            if (!_glyphCache[codepoint].valid && codepoint >= 32) {
                renderAsciiGlyph(codepoint);
            }
            return _glyphCache[codepoint];
        }

        uint faceIndex = resolveFaceIndex(codepoint);
        FT_Face face = faceForIndex(faceIndex);
        ulong key = codepointKey(faceIndex, codepoint);
        if (auto slotPtr = key in _glyphSlotMap) {
            auto slot = *slotPtr;
            lruTouch(slot);
            return _glyphCacheMap[key];
        }

        int slot = allocateSlot(key);
        if (slot < 0) {
            return _glyphCache[' '];
        }

        auto info = renderGlyphToSlot(face, codepoint, slot);
        if (!info.valid) {
            freeSlot(slot);
            return _glyphCache[' '];
        }

        _glyphCacheMap[key] = info;
        _glyphSlotMap[key] = slot;
        return info;
    }

    /**
     * Get glyph info without allocating or mutating caches.
     */
    GlyphInfo tryGetGlyph(dchar codepoint) @nogc nothrow {
        if (codepoint < 256) {
            return _glyphCache[codepoint];
        }

        uint faceIndex = resolveFaceIndex(codepoint);
        ulong key = codepointKey(faceIndex, codepoint);
        if (auto slotPtr = key in _glyphSlotMap) {
            auto slot = *slotPtr;
            lruTouch(slot);
            return _glyphCacheMap[key];
        }

        return _glyphCache[' '];
    }

    /**
     * Get glyph info by glyph index (HarfBuzz shaping).
     */
    GlyphInfo getGlyphByIndex(uint glyphIndex, uint faceIndex = 0) {
        FT_Face face = faceForIndex(faceIndex);
        ulong key = glyphIndexKey(faceIndex, glyphIndex);
        if (auto slotPtr = key in _glyphSlotMap) {
            auto slot = *slotPtr;
            lruTouch(slot);
            return _glyphCacheMap[key];
        }

        int slot = allocateSlot(key);
        if (slot < 0) {
            return _glyphCache[' '];
        }

        auto info = renderGlyphIndexToSlot(face, glyphIndex, slot);
        if (!info.valid) {
            freeSlot(slot);
            return _glyphCache[' '];
        }

        _glyphCacheMap[key] = info;
        _glyphSlotMap[key] = slot;
        return info;
    }

    /**
     * Get glyph info by index without allocating or mutating caches.
     */
    GlyphInfo tryGetGlyphByIndex(uint glyphIndex, uint faceIndex = 0) @nogc nothrow {
        ulong key = glyphIndexKey(faceIndex, glyphIndex);
        if (auto slotPtr = key in _glyphSlotMap) {
            auto slot = *slotPtr;
            lruTouch(slot);
            return _glyphCacheMap[key];
        }
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

    /// FreeType face (for HarfBuzz shaping)
    @property FT_Face ftFace() { return _ftFace; }

    /// Font size in pixels
    @property int fontSize() const { return _fontSize; }

    bool primaryHasGlyph(dchar codepoint) @nogc nothrow {
        return hasPrimaryGlyph(codepoint);
    }

    bool reloadFont(string fontPath, int fontSize) {
        terminate();
        return initialize(fontPath, fontSize);
    }

private:
    void initDynamicSlots() {
        _slotKey.length = _slotCount;
        _lruPrev.length = _slotCount;
        _lruNext.length = _slotCount;
        foreach (i; 0 .. _slotCount) {
            _slotKey[i] = ulong.max;
            _lruPrev[i] = -1;
            _lruNext[i] = -1;
        }
        _lruHead = -1;
        _lruTail = -1;
        _freeSlots.length = 0;
        foreach (i; _reservedSlots .. _slotCount) {
            _freeSlots ~= i;
        }
    }

    void loadFallbackFaces(int fontSize) {
        _fallbackFaces.length = 0;

        static immutable string[] fallbackFonts = [
            "/usr/share/fonts/TTF/NerdFontsSymbols.ttf",
            "/usr/share/fonts/TTF/NerdFontsSymbols2.ttf",
            "/usr/share/fonts/TTF/NotoSansSymbols-Regular.ttf",
            "/usr/share/fonts/TTF/NotoSansSymbols2-Regular.ttf",
            "/usr/share/fonts/TTF/NotoColorEmoji.ttf",
            "/usr/share/fonts/TTF/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/noto/NotoSansSymbols-Regular.ttf",
            "/usr/share/fonts/truetype/noto/NotoSansSymbols2-Regular.ttf",
            "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
        ];

        bool[string] seen;
        if (_primaryPath.length > 0) {
            seen[_primaryPath] = true;
        }

        foreach (path; fallbackFonts) {
            addFallbackFace(path, fontSize, seen);
        }

        auto fcRet = loadFontconfig();
        if (fcRet == LoadMsg.success) {
            FcConfig* config = FcInitLoadConfigAndFonts();
            if (config !is null) {
                FcPattern* pattern = FcPatternCreate();
                if (pattern !is null) {
                    FcPatternAddString(pattern, FC_FAMILY, cast(const(char)*)"monospace");
                    FcConfigSubstitute(config, pattern, FcMatchPattern);
                    FcDefaultSubstitute(pattern);

                    FcResult result = FcResultMatch;
                    FcFontSet* fonts = FcFontSort(config, pattern, FcFalse, null, &result);
                    if (fonts !is null) {
                        foreach (i; 0 .. min(fonts.nfont, 8)) {
                            char* filePath;
                            if (FcPatternGetString(fonts.fonts[i], FC_FILE, 0, &filePath) == FcResultMatch) {
                                string path = filePath is null ? "" : fromStringz(filePath).idup;
                                addFallbackFace(path, fontSize, seen);
                            }
                        }
                        FcFontSetDestroy(fonts);
                    }
                    FcPatternDestroy(pattern);
                }
            }
        } else if (fcRet == LoadMsg.noLibrary) {
            stderr.writefln("Warning: Fontconfig library not found (fallbacks limited)");
        }
    }

    void addFallbackFace(string path, int fontSize, ref bool[string] seen) {
        if (path.length == 0 || path in seen || !exists(path)) {
            return;
        }
        FT_Face face;
        if (FT_New_Face(_ftLibrary, path.toStringz, 0, &face) != 0) {
            return;
        }
        FT_Set_Pixel_Sizes(face, 0, fontSize);
        _fallbackFaces ~= face;
        seen[path] = true;
        stderr.writefln("Loaded fallback font: %s", path);
    }

    ulong codepointKey(uint faceIndex, dchar codepoint) @nogc nothrow {
        return (cast(ulong)faceIndex << FaceIndexShift) | cast(uint)codepoint;
    }

    ulong glyphIndexKey(uint faceIndex, uint glyphIndex) @nogc nothrow {
        return GlyphIndexFlag | (cast(ulong)faceIndex << FaceIndexShift) | glyphIndex;
    }

    uint resolveFaceIndex(dchar codepoint) @nogc nothrow {
        if (FT_Get_Char_Index(_ftFace, codepoint) != 0) {
            return 0;
        }
        foreach (i, face; _fallbackFaces) {
            if (FT_Get_Char_Index(face, codepoint) != 0) {
                return cast(uint)(i + 1);
            }
        }
        return 0;
    }

    FT_Face faceForIndex(uint faceIndex) @nogc nothrow {
        if (faceIndex == 0 || _fallbackFaces.length == 0) {
            return _ftFace;
        }
        uint idx = faceIndex - 1;
        if (idx >= _fallbackFaces.length) {
            return _ftFace;
        }
        return _fallbackFaces[idx];
    }

    bool hasPrimaryGlyph(dchar codepoint) @nogc nothrow {
        return FT_Get_Char_Index(_ftFace, codepoint) != 0;
    }

    void renderAsciiGlyph(dchar codepoint) {
        if (codepoint >= 256) {
            return;
        }
        auto info = renderGlyphToSlot(_ftFace, codepoint, cast(int)codepoint);
        _glyphCache[codepoint] = info;
    }

    GlyphInfo renderGlyphToSlot(FT_Face face, dchar codepoint, int slotIndex) {
        return renderGlyphInternal(face, slotIndex, false, codepoint, 0);
    }

    GlyphInfo renderGlyphIndexToSlot(FT_Face face, uint glyphIndex, int slotIndex) {
        return renderGlyphInternal(face, slotIndex, true, dchar.max, glyphIndex);
    }

    GlyphInfo renderGlyphInternal(FT_Face face, int slotIndex, bool byIndex, dchar codepoint, uint glyphIndex) {
        GlyphInfo info;
        int loadResult;
        if (byIndex) {
            loadResult = FT_Load_Glyph(face, glyphIndex, FT_LOAD_RENDER);
        } else {
            loadResult = FT_Load_Char(face, codepoint, FT_LOAD_RENDER);
        }
        if (loadResult != 0) {
            info.valid = false;
            return info;
        }

        auto glyph = face.glyph;
        auto bitmap = glyph.bitmap;

        int slotCol = slotIndex % _atlasCols;
        int slotRow = slotIndex / _atlasCols;
        int x = slotCol * _cellWidth;
        int y = slotRow * _cellHeight;

        if (bitmap.buffer !is null && bitmap.width > 0 && bitmap.rows > 0) {
            glBindTexture(GL_TEXTURE_2D, _textureId);
            glTexSubImage2D(GL_TEXTURE_2D, 0,
                           x, y,
                           bitmap.width, bitmap.rows,
                           GL_RED, GL_UNSIGNED_BYTE, bitmap.buffer);
        }

        info.u0 = cast(float)x / _atlasWidth;
        info.v0 = cast(float)y / _atlasHeight;
        info.u1 = cast(float)(x + bitmap.width) / _atlasWidth;
        info.v1 = cast(float)(y + bitmap.rows) / _atlasHeight;
        info.width = bitmap.width;
        info.height = bitmap.rows;
        info.bearingX = glyph.bitmap_left;
        info.bearingY = glyph.bitmap_top;
        info.advance = cast(int)(glyph.advance.x >> 6);
        info.valid = true;

        return info;
    }

    int allocateSlot(ulong key) {
        int slot;
        if (_freeSlots.length > 0) {
            slot = _freeSlots[$ - 1];
            _freeSlots.length -= 1;
        } else {
            slot = _lruTail;
            if (slot < 0) {
                return -1;
            }
            auto evicted = _slotKey[slot];
            if (evicted != ulong.max) {
                _glyphCacheMap.remove(evicted);
                _glyphSlotMap.remove(evicted);
            }
            lruRemove(slot);
        }

        _slotKey[slot] = key;
        lruInsertHead(slot);
        return slot;
    }

    void freeSlot(int slot) {
        auto evicted = _slotKey[slot];
        if (evicted != ulong.max) {
            _glyphCacheMap.remove(evicted);
            _glyphSlotMap.remove(evicted);
        }
        lruRemove(slot);
        _slotKey[slot] = ulong.max;
        _freeSlots ~= slot;
    }

    void lruInsertHead(int slot) @nogc nothrow {
        _lruPrev[slot] = -1;
        _lruNext[slot] = _lruHead;
        if (_lruHead != -1) {
            _lruPrev[_lruHead] = slot;
        }
        _lruHead = slot;
        if (_lruTail == -1) {
            _lruTail = slot;
        }
    }

    void lruRemove(int slot) @nogc nothrow {
        int prev = _lruPrev[slot];
        int next = _lruNext[slot];
        if (prev != -1) {
            _lruNext[prev] = next;
        } else {
            _lruHead = next;
        }
        if (next != -1) {
            _lruPrev[next] = prev;
        } else {
            _lruTail = prev;
        }
        _lruPrev[slot] = -1;
        _lruNext[slot] = -1;
    }

    void lruTouch(int slot) @nogc nothrow {
        if (_lruHead == slot) {
            return;
        }
        if (_lruPrev[slot] != -1 || _lruNext[slot] != -1) {
            lruRemove(slot);
            lruInsertHead(slot);
            return;
        }
        lruInsertHead(slot);
    }
}
