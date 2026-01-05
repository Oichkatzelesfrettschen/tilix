/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.backend.atlas;

import core.atomic : atomicOp, atomicLoad, MemoryOrder;
import core.sync.mutex : Mutex;
import std.algorithm : min, max;
import std.experimental.logger;
import std.format : format;
import std.typecons : Nullable;

version (Have_bindbc_opengl) {
    import bindbc.opengl;
    enum HaveBindBCOpenGL = true;

    // GL_R8 is OpenGL 3.0+ but may not be in all bindbc configurations
    static if (!is(typeof(GL_R8))) {
        enum GL_R8 = 0x8229;
    }
} else {
    enum HaveBindBCOpenGL = false;
}

version (Have_bindbc_freetype) {
    import bindbc.freetype;
    enum HaveBindBCFreeType = true;
} else {
    enum HaveBindBCFreeType = false;
}

/**
 * Glyph metrics and atlas location.
 */
struct GlyphInfo {
    // Atlas texture coordinates (normalized 0-1)
    float u0, v0;  // Top-left
    float u1, v1;  // Bottom-right

    // Glyph metrics in pixels
    short width;
    short height;
    short bearingX;  // Offset from baseline
    short bearingY;
    short advance;   // Horizontal advance

    // Character this glyph represents
    dchar codepoint;

    // Cache status
    bool valid;
}

/**
 * Rectangle in the atlas for packing.
 */
struct AtlasRect {
    ushort x, y;
    ushort width, height;
}

/**
 * Simple row-based packing for atlas.
 * Allocates glyphs in horizontal rows, starting new rows as needed.
 */
struct RowPacker {
    ushort atlasWidth;
    ushort atlasHeight;
    ushort currentX;
    ushort currentY;
    ushort rowHeight;
    ushort padding;

    void initialize(ushort width, ushort height, ushort pad = 1) {
        atlasWidth = width;
        atlasHeight = height;
        currentX = pad;
        currentY = pad;
        rowHeight = 0;
        padding = pad;
    }

    /**
     * Allocate space for a glyph.
     * Returns null if atlas is full.
     */
    Nullable!AtlasRect allocate(ushort width, ushort height) {
        // Check if fits in current row
        if (currentX + width + padding > atlasWidth) {
            // Start new row
            currentX = padding;
            currentY += rowHeight + padding;
            rowHeight = 0;
        }

        // Check if fits in atlas
        if (currentY + height + padding > atlasHeight) {
            return Nullable!AtlasRect.init;  // Atlas full
        }

        auto rect = AtlasRect(currentX, currentY, width, height);
        currentX += width + padding;
        rowHeight = max(rowHeight, height);

        return Nullable!AtlasRect(rect);
    }

    void reset() {
        currentX = padding;
        currentY = padding;
        rowHeight = 0;
    }
}

/**
 * Font texture atlas for GPU text rendering.
 *
 * Uses atomic versioning for lock-free GPU synchronization (Ghostty pattern).
 * Glyphs are rasterized on-demand and cached in the atlas texture.
 */
class FontAtlas {
private:
    // Atlas dimensions (power of 2 for efficiency)
    enum DEFAULT_SIZE = 1024;
    ushort _width;
    ushort _height;

    // GPU texture handle
    uint _textureId;

    // Glyph cache
    GlyphInfo[dchar] _glyphCache;

    // Packing state
    RowPacker _packer;

    // Atomic version counter for GPU sync
    shared ulong _version;

    // Thread safety for cache updates
    Mutex _mutex;

    // CPU-side pixel buffer for uploads
    ubyte[] _pixelBuffer;

    // Dirty region for partial updates
    AtlasRect _dirtyRegion;
    bool _hasDirty;

    // FreeType handles (conditionally compiled)
    static if (HaveBindBCFreeType) {
        FT_Library _ftLibrary;
        FT_Face _ftFace;
        uint _pixelSize = 16;
        bool _ftInitialized;
    }

public:
    /**
     * Create a font atlas with specified dimensions.
     */
    this(ushort width = DEFAULT_SIZE, ushort height = DEFAULT_SIZE) {
        _width = width;
        _height = height;
        _packer.initialize(width, height);
        _mutex = new Mutex();
        _pixelBuffer = new ubyte[width * height];
        _version = 0;

        static if (HaveBindBCOpenGL) {
            createTexture();
        }

        tracef("FontAtlas created: %dx%d", width, height);
    }

    // Note: No destructor - use dispose() explicitly before GC collects
    // Destructors can cause issues during GC finalization (no allocations allowed)

    /**
     * Initialize FreeType library.
     * Returns true on success, false on failure.
     */
    bool initFreeType() {
        static if (HaveBindBCFreeType) {
            if (_ftInitialized) return true;

            FTSupport ftRet = bindbc.freetype.loadFreeType();
            if (ftRet == FTSupport.noLibrary) {
                error("Failed to load FreeType shared library");
                return false;
            }
            if (ftRet == FTSupport.badLibrary) {
                warning("FreeType library version mismatch, some functions may fail");
            }

            if (FT_Init_FreeType(&_ftLibrary) != FT_Err_Ok) {
                error("FT_Init_FreeType failed");
                return false;
            }

            _ftInitialized = true;
            trace("FreeType initialized");
            return true;
        } else {
            warning("FreeType support not compiled in");
            return false;
        }
    }

    /**
     * Load a font file with specified pixel size.
     * Returns true on success, false on failure.
     */
    bool loadFontFile(string path, uint pixelSize = 16) {
        static if (HaveBindBCFreeType) {
            if (!_ftInitialized) {
                if (!initFreeType()) return false;
            }

            // Free existing face if any
            if (_ftFace !is null) {
                FT_Done_Face(_ftFace);
                _ftFace = null;
            }

            import std.string : toStringz;
            if (FT_New_Face(_ftLibrary, path.toStringz, 0, &_ftFace) != FT_Err_Ok) {
                errorf("Failed to load font: %s", path);
                return false;
            }

            if (FT_Set_Pixel_Sizes(_ftFace, 0, pixelSize) != FT_Err_Ok) {
                errorf("Failed to set pixel size: %d", pixelSize);
                FT_Done_Face(_ftFace);
                _ftFace = null;
                return false;
            }

            _pixelSize = pixelSize;
            tracef("Font loaded: %s at %d px", path, pixelSize);
            return true;
        } else {
            warning("FreeType support not compiled in");
            return false;
        }
    }

    /**
     * Get glyph info, rasterizing if necessary.
     */
    GlyphInfo getGlyph(dchar codepoint) {
        // Fast path: check cache without locking
        if (auto cached = codepoint in _glyphCache) {
            return *cached;
        }

        // Slow path: rasterize and cache
        synchronized (_mutex) {
            // Double-check after acquiring lock
            if (auto cached = codepoint in _glyphCache) {
                return *cached;
            }

            return rasterizeGlyph(codepoint);
        }
    }

    /**
     * Bind the atlas texture for rendering.
     */
    void bind(uint textureUnit = 0) {
        static if (HaveBindBCOpenGL) {
            glActiveTexture(GL_TEXTURE0 + textureUnit);
            glBindTexture(GL_TEXTURE_2D, _textureId);
        }
    }

    /**
     * Upload any dirty regions to GPU.
     */
    void sync() {
        if (!_hasDirty) return;

        static if (HaveBindBCOpenGL) {
            glBindTexture(GL_TEXTURE_2D, _textureId);
            glTexSubImage2D(
                GL_TEXTURE_2D, 0,
                _dirtyRegion.x, _dirtyRegion.y,
                _dirtyRegion.width, _dirtyRegion.height,
                GL_RED, GL_UNSIGNED_BYTE,
                &_pixelBuffer[_dirtyRegion.y * _width + _dirtyRegion.x]
            );
        }

        _hasDirty = false;
        atomicOp!"+="(_version, 1);
    }

    /**
     * Get atlas version for cache invalidation.
     */
    @property ulong ver() const {
        return atomicLoad!(MemoryOrder.acq)(_version);
    }

    /**
     * Get atlas dimensions.
     */
    @property ushort width() const { return _width; }
    @property ushort height() const { return _height; }

    /**
     * Get texture handle.
     */
    @property uint textureId() const { return _textureId; }

    /**
     * Clear the atlas and reset packing.
     */
    void clear() {
        synchronized (_mutex) {
            _glyphCache.clear();
            _packer.reset();
            _pixelBuffer[] = 0;

            static if (HaveBindBCOpenGL) {
                glBindTexture(GL_TEXTURE_2D, _textureId);
                glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, _width, _height,
                    GL_RED, GL_UNSIGNED_BYTE, _pixelBuffer.ptr);
            }

            atomicOp!"+="(_version, 1);
        }
        trace("FontAtlas cleared");
    }

    /**
     * Release GPU and FreeType resources.
     */
    void dispose() {
        static if (HaveBindBCOpenGL) {
            if (_textureId != 0) {
                glDeleteTextures(1, &_textureId);
                _textureId = 0;
            }
        }

        static if (HaveBindBCFreeType) {
            if (_ftFace !is null) {
                FT_Done_Face(_ftFace);
                _ftFace = null;
            }
            if (_ftInitialized && _ftLibrary !is null) {
                FT_Done_FreeType(_ftLibrary);
                _ftLibrary = null;
                _ftInitialized = false;
            }
        }

        _pixelBuffer = null;
        trace("FontAtlas disposed");
    }

private:
    void createTexture() {
        static if (HaveBindBCOpenGL) {
            glGenTextures(1, &_textureId);
            glBindTexture(GL_TEXTURE_2D, _textureId);

            // Single-channel texture for glyph alpha
            glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, _width, _height, 0,
                GL_RED, GL_UNSIGNED_BYTE, null);

            // Filtering for smooth text
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

            // Clamp to edge to avoid bleeding
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

            tracef("FontAtlas texture created: id=%d", _textureId);
        }
    }

    GlyphInfo rasterizeGlyph(dchar codepoint) {
        GlyphInfo info;
        info.codepoint = codepoint;

        ushort glyphWidth;
        ushort glyphHeight;
        ubyte[] bitmapData;

        static if (HaveBindBCFreeType) {
            // Use FreeType to rasterize the glyph
            if (_ftInitialized && _ftFace !is null) {
                if (FT_Load_Char(_ftFace, codepoint, FT_LOAD_RENDER) == FT_Err_Ok) {
                    auto glyph = _ftFace.glyph;
                    auto bitmap = glyph.bitmap;

                    glyphWidth = cast(ushort)bitmap.width;
                    glyphHeight = cast(ushort)bitmap.rows;

                    // Extract metrics from FreeType
                    info.bearingX = cast(short)(glyph.bitmap_left);
                    info.bearingY = cast(short)(glyph.bitmap_top);
                    info.advance = cast(short)(glyph.advance.x >> 6);  // 26.6 fixed-point

                    // Copy bitmap data (FreeType uses pitch for row stride)
                    if (glyphWidth > 0 && glyphHeight > 0 && bitmap.buffer !is null) {
                        bitmapData = new ubyte[glyphWidth * glyphHeight];
                        foreach (y; 0 .. glyphHeight) {
                            auto srcRow = bitmap.buffer + y * bitmap.pitch;
                            auto dstRow = bitmapData.ptr + y * glyphWidth;
                            dstRow[0 .. glyphWidth] = srcRow[0 .. glyphWidth];
                        }
                    }
                } else {
                    tracef("FT_Load_Char failed for U+%04X", cast(uint)codepoint);
                }
            }
        }

        // Fallback to placeholder if FreeType failed or unavailable
        if (glyphWidth == 0 || glyphHeight == 0) {
            glyphWidth = 8;
            glyphHeight = 16;
            info.bearingX = 0;
            info.bearingY = cast(short)glyphHeight;
            info.advance = cast(short)glyphWidth;

            // Generate placeholder pattern
            bitmapData = new ubyte[glyphWidth * glyphHeight];
            foreach (y; 0 .. glyphHeight) {
                foreach (x; 0 .. glyphWidth) {
                    bitmapData[y * glyphWidth + x] =
                        cast(ubyte)(((codepoint + x + y) * 37) % 256);
                }
            }
        }

        // Allocate space in atlas
        auto rect = _packer.allocate(glyphWidth, glyphHeight);
        if (rect.isNull) {
            warning("FontAtlas full, cannot allocate glyph");
            return info;
        }

        auto r = rect.get;

        // Copy glyph bitmap to atlas pixel buffer
        foreach (y; 0 .. glyphHeight) {
            foreach (x; 0 .. glyphWidth) {
                auto srcIdx = y * glyphWidth + x;
                auto dstIdx = (r.y + y) * _width + (r.x + x);
                _pixelBuffer[dstIdx] = bitmapData[srcIdx];
            }
        }

        // Calculate texture coordinates
        info.u0 = cast(float)r.x / _width;
        info.v0 = cast(float)r.y / _height;
        info.u1 = cast(float)(r.x + glyphWidth) / _width;
        info.v1 = cast(float)(r.y + glyphHeight) / _height;

        info.width = cast(short)glyphWidth;
        info.height = cast(short)glyphHeight;
        info.valid = true;

        // Mark dirty region
        if (!_hasDirty) {
            _dirtyRegion = r;
            _hasDirty = true;
        } else {
            // Expand dirty region
            auto minX = min(_dirtyRegion.x, r.x);
            auto minY = min(_dirtyRegion.y, r.y);
            auto maxX = max(_dirtyRegion.x + _dirtyRegion.width, r.x + r.width);
            auto maxY = max(_dirtyRegion.y + _dirtyRegion.height, r.y + r.height);
            _dirtyRegion.x = cast(ushort)minX;
            _dirtyRegion.y = cast(ushort)minY;
            _dirtyRegion.width = cast(ushort)(maxX - minX);
            _dirtyRegion.height = cast(ushort)(maxY - minY);
        }

        // Cache the glyph
        _glyphCache[codepoint] = info;

        return info;
    }
}

@system
unittest {
    // Test RowPacker
    RowPacker packer;
    packer.initialize(256, 256, 1);

    auto r1 = packer.allocate(10, 20);
    assert(!r1.isNull);
    assert(r1.get.x == 1);
    assert(r1.get.y == 1);

    auto r2 = packer.allocate(10, 20);
    assert(!r2.isNull);
    assert(r2.get.x == 12);  // After first + padding

    // Test GlyphInfo initialization
    GlyphInfo info;
    assert(!info.valid);

    // Test FontAtlas creation (without GL context)
    static if (!HaveBindBCOpenGL) {
        auto atlas = new FontAtlas(512, 512);
        assert(atlas.width == 512);
        assert(atlas.height == 512);
        atlas.dispose();
    }
}

// FreeType glyph rasterization test
@system
unittest {
    static if (HaveBindBCFreeType && !HaveBindBCOpenGL) {
        import std.file : exists;

        auto atlas = new FontAtlas(512, 512);
        scope(exit) atlas.dispose();

        // Try to initialize FreeType
        bool ftOk = atlas.initFreeType();
        if (!ftOk) {
            // FreeType shared library not available - skip test
            return;
        }

        // Try common system fonts
        string[] fontPaths = [
            "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
            "/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf",
            "/usr/share/fonts/liberation-mono/LiberationMono-Regular.ttf",
        ];

        string fontPath;
        foreach (path; fontPaths) {
            if (exists(path)) {
                fontPath = path;
                break;
            }
        }

        if (fontPath.length == 0) {
            // No suitable font found - skip test
            return;
        }

        // Load font
        bool fontOk = atlas.loadFontFile(fontPath, 16);
        assert(fontOk, "Failed to load font");

        // Rasterize 'A' and verify
        auto glyphA = atlas.getGlyph('A');
        assert(glyphA.valid, "Glyph 'A' should be valid");
        assert(glyphA.width > 0, "Glyph 'A' should have width");
        assert(glyphA.height > 0, "Glyph 'A' should have height");
        assert(glyphA.advance > 0, "Glyph 'A' should have advance");

        // Verify some pixels are non-zero (glyph has actual content)
        bool hasContent = false;
        foreach (y; 0 .. glyphA.height) {
            foreach (x; 0 .. glyphA.width) {
                auto atlasX = cast(ushort)(glyphA.u0 * atlas.width) + x;
                auto atlasY = cast(ushort)(glyphA.v0 * atlas.height) + y;
                auto idx = atlasY * atlas.width + atlasX;
                if (atlas._pixelBuffer[idx] > 0) {
                    hasContent = true;
                    break;
                }
            }
            if (hasContent) break;
        }
        assert(hasContent, "Glyph 'A' should have non-zero pixels");
    }
}
