/**
 * Terminal Cell Renderer
 *
 * Instanced OpenGL renderer for terminal cells. Uses a single draw call
 * with per-instance data for background and glyph quads.
 *
 * Key features:
 * - Instanced quad rendering (single draw)
 * - Per-cell foreground/background colors
 * - Font atlas texture mapping
 * - Cursor rendering
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.renderer;

version (PURE_D_BACKEND):

import bindbc.opengl;
import pured.fontatlas;
import pured.emulator : attributesToColors;
import pured.config : ResolvedTheme, defaultResolvedTheme;
import pured.text.shaper;
import pured.terminal.selection : Selection;
import pured.terminal.search : SearchRange;
import pured.terminal.hyperlink : HyperlinkRange;
import pured.terminal.frame : TerminalFrame;
import core.stdc.string : memcpy;
import std.math : pow;
import std.algorithm : min;
import std.stdio : stderr, writefln;

/**
 * Quad vertex (unit quad).
 */
struct QuadVertex {
    float x, y;
}

/**
 * Per-instance cell data.
 */
struct CellInstance {
    float x, y, w, h;      // Position and size
    float u0, v0, u1, v1;  // Glyph UVs
    float fgR, fgG, fgB, fgA;
    float bgR, bgG, bgB, bgA;
    float glyphEnabled;   // 1.0 for glyph quad, 0.0 for background
}

enum CursorRenderStyle {
    block,
    underline,
    bar,
    outline,
}

/**
 * Terminal cell renderer using OpenGL instancing.
 */
class CellRenderer {
private:
    FontAtlas _fontAtlas;
    GLuint _vao;
    GLuint _quadVbo;
    GLuint _instanceVbo;
    GLuint _shaderProgram;

    // Uniform locations
    GLint _projectionLoc;
    GLint _fontAtlasLoc;
    GLint _bellLoc;

    // Instance buffer
    CellInstance[] _instances;
    size_t _instanceCapacityBytes;
    void* _instanceMap;
    bool _instancePersistent;
    size_t _instanceCount;
    size_t _lastInstanceCount;
    int _maxCells;
    float _contentScale = 1.0f;
    TextShaper _shaper;
    ShapedGlyph[] _shapeBuffer;
    dchar[] _lineBuffer;
    float[4][] _fgRow;
    float[4][] _bgRow;
    ResolvedTheme _theme;
    float _bellIntensity;

    // Viewport
    int _viewportWidth;
    int _viewportHeight;

public:
    /**
     * Initialize the renderer.
     *
     * Params:
     *   maxCells = Maximum number of cells to render
     *
     * Returns: true if initialization succeeded
     */
    bool initialize(int maxCells = 80 * 50) {
        _maxCells = maxCells;
        _theme = *defaultResolvedTheme();

        // Create font atlas
        _fontAtlas = new FontAtlas();
        if (!_fontAtlas.initialize(null, 16)) {
            stderr.writefln("Error: Failed to initialize font atlas");
            return false;
        }

        _shaper = new TextShaper();
        if (!_shaper.initialize(_fontAtlas.ftFace, _fontAtlas.fontSize)) {
            stderr.writefln("Warning: HarfBuzz shaping disabled");
        }

        // Compile shaders
        if (!compileShaders()) {
            stderr.writefln("Error: Failed to compile cell shaders");
            return false;
        }

        // Create buffers
        if (!createBuffers()) {
            stderr.writefln("Error: Failed to create cell buffers");
            return false;
        }

        return true;
    }

    /**
     * Cleanup resources.
     */
    void terminate() {
        if (_fontAtlas !is null) {
            _fontAtlas.terminate();
            _fontAtlas = null;
        }
        if (_shaper !is null) {
            _shaper.terminate();
            _shaper = null;
        }
        if (_shaderProgram != 0) {
            glDeleteProgram(_shaderProgram);
            _shaderProgram = 0;
        }
        if (_vao != 0) {
            glDeleteVertexArrays(1, &_vao);
            _vao = 0;
        }
        if (_quadVbo != 0) {
            glDeleteBuffers(1, &_quadVbo);
            _quadVbo = 0;
        }
        if (_instanceVbo != 0) {
            if (_instanceMap !is null) {
                glBindBuffer(GL_ARRAY_BUFFER, _instanceVbo);
                glUnmapBuffer(GL_ARRAY_BUFFER);
                _instanceMap = null;
                _instancePersistent = false;
            }
            glDeleteBuffers(1, &_instanceVbo);
            _instanceVbo = 0;
        }
    }

    /**
     * Set viewport dimensions.
     */
    void setViewport(int width, int height) {
        _viewportWidth = width;
        _viewportHeight = height;
    }

    /**
     * Render terminal cells.
     *
     * Params:
     *   frame = Terminal frame snapshot
     *   cursorVisible = Whether to render cursor
     */
    void render(ref TerminalFrame frame, bool cursorVisible = true,
            Selection selection = null, int selectionOffset = 0,
            float[4] selectionBg = [0.2f, 0.6f, 0.8f, 1.0f],
            float[4] selectionFg = [1.0f, 1.0f, 1.0f, 1.0f],
            const(SearchRange)[] searchRanges = null,
            float[4] searchBg = [0.85f, 0.7f, 0.2f, 1.0f],
            float[4] searchFg = [0.0f, 0.0f, 0.0f, 1.0f],
            const(HyperlinkRange)[] linkRanges = null,
            float[4] linkFg = [0.2f, 0.6f, 1.0f, 1.0f],
            HyperlinkRange hoverLink = HyperlinkRange.init,
            bool hoverLinkActive = false,
            CursorRenderStyle cursorStyle = CursorRenderStyle.block,
            float cursorThickness = 0.0f,
            const(dchar)[] overlayText = null,
            int overlayRow = -1,
            float[4] overlayBg = [0.15f, 0.15f, 0.2f, 0.9f],
            float[4] overlayFg = [1.0f, 1.0f, 1.0f, 1.0f]) {
        if (frame.cols <= 0 || frame.rows <= 0 || frame.cells.length == 0) {
            return;
        }

        int cols = frame.cols;
        int rows = frame.rows;
        float cellW = _fontAtlas.cellWidth * _contentScale;
        float cellH = _fontAtlas.cellHeight * _contentScale;

        if (!buffersReady(cols, rows)) {
            return;
        }
        _instanceCount = 0;
        bool useShaping = _shaper !is null && _shaper.available;

        bool hasSelection = selection !is null && selection.hasSelection;
        bool hasSearch = searchRanges !is null && searchRanges.length > 0;
        size_t rangeIndex = 0;
        bool hasLinks = linkRanges !is null && linkRanges.length > 0;
        size_t linkIndex = 0;
        bool hasOverlay = overlayText !is null && overlayText.length > 0 &&
            overlayRow >= 0 && overlayRow < rows;
        int overlayCols = hasOverlay
            ? min(cast(int)overlayText.length, cols)
            : 0;
        float cursorThicknessPx = cursorThickness > 0.0f ?
            cursorThickness * _contentScale : maxf(2.0f, cellH * 0.1f);
        if (cursorThicknessPx > cellH) {
            cursorThicknessPx = cellH;
        }
        if (cursorThicknessPx > cellW) {
            cursorThicknessPx = cellW;
        }

        foreach (row; 0 .. rows) {
            bool rowShaping = useShaping;
            size_t rowRangeIndex = rangeIndex;
            SearchRange currentRange;
            bool hasRange = false;
            size_t rowLinkIndex = linkIndex;
            HyperlinkRange currentLink;
            bool hasLink = false;
            bool overlayRowActive = hasOverlay && row == overlayRow;

            if (hasSearch) {
                while (rowRangeIndex < searchRanges.length &&
                       searchRanges[rowRangeIndex].row < row) {
                    rowRangeIndex++;
                }
                if (rowRangeIndex < searchRanges.length &&
                    searchRanges[rowRangeIndex].row == row) {
                    currentRange = searchRanges[rowRangeIndex];
                    hasRange = true;
                }
            }
            if (hasLinks) {
                while (rowLinkIndex < linkRanges.length &&
                       linkRanges[rowLinkIndex].row < row) {
                    rowLinkIndex++;
                }
                if (rowLinkIndex < linkRanges.length &&
                    linkRanges[rowLinkIndex].row == row) {
                    currentLink = linkRanges[rowLinkIndex];
                    hasLink = true;
                }
            }
            foreach (col; 0 .. cols) {
                if (overlayRowActive) {
                    dchar ch = col < overlayCols ? overlayText[col] : ' ';
                    float[4] fg = overlayFg;
                    float[4] bg = overlayBg;

                    _lineBuffer[col] = ch;
                    _fgRow[col] = fg;
                    _bgRow[col] = bg;
                    float x0 = col * cellW;
                    float y0 = row * cellH;
                    addInstance(x0, y0, cellW, cellH,
                                0, 0, 0, 0,
                                fg, bg, 0.0f);
                    continue;
                }
                auto idx = row * cols + col;
                if (idx >= frame.cells.length) {
                    continue;
                }
                auto cell = frame.cells[idx];

                dchar ch = ' ';
                if (!cell.hasNonCharacterData) {
                    ch = cell.ch;
                    if (ch == 0) ch = ' ';
                }

                float[4] fg = _theme.foreground;
                float[4] bg = _theme.background;
                if (!cell.hasNonCharacterData) {
                    attributesToColors(cell.attributes, fg, bg, &_theme);
                }

                if (hasLink) {
                    while (hasLink && col > currentLink.endCol) {
                        rowLinkIndex++;
                        if (rowLinkIndex < linkRanges.length &&
                            linkRanges[rowLinkIndex].row == row) {
                            currentLink = linkRanges[rowLinkIndex];
                        } else {
                            hasLink = false;
                        }
                    }
                    if (hasLink &&
                        col >= currentLink.startCol &&
                        col <= currentLink.endCol) {
                        fg = linkFg;
                    }
                }

                if (hoverLinkActive &&
                    row == hoverLink.row &&
                    col >= hoverLink.startCol &&
                    col <= hoverLink.endCol) {
                    float blend = 0.35f;
                    bg = [
                        bg[0] * (1.0f - blend) + linkFg[0] * blend,
                        bg[1] * (1.0f - blend) + linkFg[1] * blend,
                        bg[2] * (1.0f - blend) + linkFg[2] * blend,
                        bg[3]
                    ];
                }

                if (hasRange) {
                    while (hasRange && col > currentRange.endCol) {
                        rowRangeIndex++;
                        if (rowRangeIndex < searchRanges.length &&
                            searchRanges[rowRangeIndex].row == row) {
                            currentRange = searchRanges[rowRangeIndex];
                        } else {
                            hasRange = false;
                        }
                    }
                    if (hasRange &&
                        col >= currentRange.startCol &&
                        col <= currentRange.endCol) {
                        bg = searchBg;
                        fg = searchFg;
                    }
                }

                if (hasSelection) {
                    int bufferRow = row - selectionOffset;
                    if (selection.isSelected(col, bufferRow)) {
                        bg = selectionBg;
                        fg = selectionFg;
                    }
                }

                bool isCursor = cursorVisible &&
                               col == frame.cursorCol &&
                               row == frame.cursorRow;
                float[4] cursorColor;

                if (isCursor) {
                    cursorColor = highContrastCursor(bg);
                    final switch (cursorStyle) {
                        case CursorRenderStyle.block:
                            fg = cursorTextColor(cursorColor);
                            bg = cursorColor;
                            break;
                        case CursorRenderStyle.underline:
                        case CursorRenderStyle.bar:
                        case CursorRenderStyle.outline:
                            break;
                    }
                }

                _lineBuffer[col] = ch;
                _fgRow[col] = fg;
                _bgRow[col] = bg;
                if (rowShaping && ch != ' ' && !_fontAtlas.primaryHasGlyph(ch)) {
                    rowShaping = false;
                }

                float x0 = col * cellW;
                float y0 = row * cellH;
                addInstance(x0, y0, cellW, cellH,
                            0, 0, 0, 0,
                            fg, bg, 0.0f);

                if (isCursor) {
                    final switch (cursorStyle) {
                        case CursorRenderStyle.block:
                            break;
                        case CursorRenderStyle.underline:
                            addInstance(x0, y0 + cellH - cursorThicknessPx,
                                        cellW, cursorThicknessPx,
                                        0, 0, 0, 0,
                                        cursorColor, cursorColor, 0.0f);
                            break;
                        case CursorRenderStyle.bar:
                            addInstance(x0, y0, cursorThicknessPx, cellH,
                                        0, 0, 0, 0,
                                        cursorColor, cursorColor, 0.0f);
                            break;
                        case CursorRenderStyle.outline:
                            addInstance(x0, y0, cellW, cursorThicknessPx,
                                        0, 0, 0, 0,
                                        cursorColor, cursorColor, 0.0f);
                            addInstance(x0, y0 + cellH - cursorThicknessPx,
                                        cellW, cursorThicknessPx,
                                        0, 0, 0, 0,
                                        cursorColor, cursorColor, 0.0f);
                            addInstance(x0, y0, cursorThicknessPx, cellH,
                                        0, 0, 0, 0,
                                        cursorColor, cursorColor, 0.0f);
                            addInstance(x0 + cellW - cursorThicknessPx, y0,
                                        cursorThicknessPx, cellH,
                                        0, 0, 0, 0,
                                        cursorColor, cursorColor, 0.0f);
                            break;
                    }
                }
            }

            if (hasSearch) {
                rangeIndex = rowRangeIndex;
            }
            if (hasLinks) {
                linkIndex = rowLinkIndex;
            }

            bool shaped = false;
            uint shapedCount = 0;
            if (rowShaping) {
                shaped = _shaper.shapeLine(_lineBuffer, _shapeBuffer, shapedCount);
            }

            if (shaped && shapedCount > 0) {
                float penX = 0.0f;
                float penY = 0.0f;
                float baselineY = row * cellH + cellH;

                foreach (glyph; _shapeBuffer[0 .. shapedCount]) {
                    if (glyph.glyphIndex == 0) {
                        penX += (glyph.xAdvance / 64.0f) * _contentScale;
                        penY += (glyph.yAdvance / 64.0f) * _contentScale;
                        continue;
                    }

                    uint cluster = glyph.cluster;
                    if (cluster >= cols) {
                        cluster = cols - 1;
                    }

                    auto fg = _fgRow[cluster];
                    auto bg = _bgRow[cluster];
                    if (_lineBuffer[cluster] == ' ') {
                        penX += (glyph.xAdvance / 64.0f) * _contentScale;
                        penY += (glyph.yAdvance / 64.0f) * _contentScale;
                        continue;
                    }

                    GlyphInfo info;
                    version (PURE_D_STRICT_NOGC) {
                        info = _fontAtlas.tryGetGlyphByIndex(glyph.glyphIndex);
                    } else {
                        info = _fontAtlas.getGlyphByIndex(glyph.glyphIndex);
                    }
                    if (info.valid && info.width > 0 && info.height > 0) {
                        float xOffset = (glyph.xOffset / 64.0f) * _contentScale;
                        float yOffset = (glyph.yOffset / 64.0f) * _contentScale;
                        float bearingX = info.bearingX * _contentScale;
                        float bearingY = info.bearingY * _contentScale;
                        float glyphW = info.width * _contentScale;
                        float glyphH = info.height * _contentScale;
                        float gx0 = penX + xOffset + bearingX;
                        float gy0 = baselineY - bearingY - yOffset;
                        addInstance(gx0, gy0, glyphW, glyphH,
                                    info.u0, info.v0, info.u1, info.v1,
                                    fg, bg, 1.0f);
                    }

                    penX += (glyph.xAdvance / 64.0f) * _contentScale;
                    penY += (glyph.yAdvance / 64.0f) * _contentScale;
                }
            } else {
                foreach (col; 0 .. cols) {
                    dchar ch = _lineBuffer[col];
                    if (ch == ' ' || ch == 0) {
                        continue;
                    }
                    GlyphInfo glyphInfo;
                    version (PURE_D_STRICT_NOGC) {
                        glyphInfo = _fontAtlas.tryGetGlyph(ch);
                    } else {
                        glyphInfo = _fontAtlas.getGlyph(ch);
                    }
                    if (glyphInfo.valid && glyphInfo.width > 0 && glyphInfo.height > 0) {
                        float bearingX = glyphInfo.bearingX * _contentScale;
                        float bearingY = glyphInfo.bearingY * _contentScale;
                        float glyphW = glyphInfo.width * _contentScale;
                        float glyphH = glyphInfo.height * _contentScale;
                        float x0 = col * cellW;
                        float y0 = row * cellH;
                        float gx0 = x0 + bearingX;
                        float gy0 = y0 + (cellH - bearingY);
                        addInstance(gx0, gy0, glyphW, glyphH,
                                    glyphInfo.u0, glyphInfo.v0, glyphInfo.u1, glyphInfo.v1,
                                    _fgRow[col], _bgRow[col], 1.0f);
                    }
                }
            }
        }

        _lastInstanceCount = _instanceCount;
        if (_instanceCount == 0) {
            return;
        }

        glUseProgram(_shaderProgram);

        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        float[16] projection = orthoMatrix(0, _viewportWidth, _viewportHeight, 0);
        glUniformMatrix4fv(_projectionLoc, 1, GL_FALSE, projection.ptr);
        glUniform1f(_bellLoc, _bellIntensity);

        _fontAtlas.bind(0);
        glUniform1i(_fontAtlasLoc, 0);

        glBindVertexArray(_vao);
        uploadInstances();

        glDrawArraysInstanced(GL_TRIANGLES, 0, 6, cast(int)_instanceCount);

        glBindVertexArray(0);
        glDisable(GL_BLEND);
    }

    /// Cell width in pixels
    @property int cellWidth() const {
        return _fontAtlas !is null ? cast(int)(_fontAtlas.cellWidth * _contentScale) : 10;
    }

    /// Cell height in pixels
    @property int cellHeight() const {
        return _fontAtlas !is null ? cast(int)(_fontAtlas.cellHeight * _contentScale) : 20;
    }

    /// Font atlas (shared with widget renderer)
    @property FontAtlas fontAtlas() { return _fontAtlas; }

    void setTheme(in ResolvedTheme theme) {
        _theme = theme;
    }

    void setBellIntensity(float intensity) @nogc nothrow {
        if (intensity < 0.0f) {
            _bellIntensity = 0.0f;
        } else if (intensity > 1.0f) {
            _bellIntensity = 1.0f;
        } else {
            _bellIntensity = intensity;
        }
    }

    void setContentScale(float scale) {
        if (scale <= 0) {
            _contentScale = 1.0f;
        } else {
            _contentScale = scale;
        }
    }

    bool buffersReady(int cols, int rows) @nogc nothrow {
        if (cols <= 0 || rows <= 0) {
            return false;
        }
        size_t baseCells = cast(size_t)cols * cast(size_t)rows;
        size_t required = baseCells * 4 + 256;
        if (_instances.length < required) {
            return false;
        }
        if (_lineBuffer.length != cols || _fgRow.length != cols || _bgRow.length != cols) {
            return false;
        }
        size_t shapedCapacity = cast(size_t)cols * 8;
        if (_shapeBuffer.length < shapedCapacity) {
            return false;
        }
        return true;
    }

    void prepareBuffers(int cols, int rows) {
        if (cols <= 0 || rows <= 0) {
            return;
        }
        size_t baseCells = cast(size_t)cols * cast(size_t)rows;
        size_t required = baseCells * 4 + 256;
        if (_instances.length < required) {
            _instances.length = required;
        }
        if (_lineBuffer.length != cols) {
            _lineBuffer.length = cols;
            _fgRow.length = cols;
            _bgRow.length = cols;
        }
        size_t shapedCapacity = cast(size_t)cols * 8;
        if (_shapeBuffer.length < shapedCapacity) {
            _shapeBuffer.length = shapedCapacity;
        }
    }

    @property size_t lastInstanceCount() const {
        return _lastInstanceCount;
    }

    bool reloadFont(string fontPath, int fontSize) {
        if (_fontAtlas is null) {
            return false;
        }
        if (!_fontAtlas.reloadFont(fontPath, fontSize)) {
            return false;
        }
        if (_shaper !is null) {
            _shaper.terminate();
            _shaper.initialize(_fontAtlas.ftFace, _fontAtlas.fontSize);
        }
        return true;
    }

private:
    void addInstance(float x, float y, float w, float h,
                     float u0, float v0, float u1, float v1,
                     float[4] fg, float[4] bg, float glyphEnabled) @nogc nothrow {
        if (_instanceCount >= _instances.length) {
            return;
        }
        _instances[_instanceCount++] = CellInstance(x, y, w, h,
                                                    u0, v0, u1, v1,
                                                    fg[0], fg[1], fg[2], fg[3],
                                                    bg[0], bg[1], bg[2], bg[3],
                                                    glyphEnabled);
    }

    void uploadInstances() {
        size_t bytes = _instanceCount * CellInstance.sizeof;
        if (bytes == 0) {
            return;
        }
        ensureInstanceCapacity(bytes);
        glBindBuffer(GL_ARRAY_BUFFER, _instanceVbo);

        if (_instancePersistent && _instanceMap !is null) {
            memcpy(_instanceMap, _instances.ptr, bytes);
        } else {
            auto mapped = glMapBufferRange(GL_ARRAY_BUFFER, 0, bytes,
                                           GL_MAP_WRITE_BIT | GL_MAP_INVALIDATE_RANGE_BIT);
            if (mapped !is null) {
                memcpy(mapped, _instances.ptr, bytes);
                glUnmapBuffer(GL_ARRAY_BUFFER);
            } else {
                glBufferSubData(GL_ARRAY_BUFFER, 0, bytes, _instances.ptr);
            }
        }
    }

    void ensureInstanceCapacity(size_t bytes) {
        if (bytes <= _instanceCapacityBytes) {
            return;
        }
        glBindBuffer(GL_ARRAY_BUFFER, _instanceVbo);

        if (_instanceMap !is null) {
            glUnmapBuffer(GL_ARRAY_BUFFER);
            _instanceMap = null;
            _instancePersistent = false;
        }

        _instanceCapacityBytes = bytes;

        if (glBufferStorage is null) {
            glBufferData(GL_ARRAY_BUFFER, _instanceCapacityBytes, null, GL_STREAM_DRAW);
            return;
        }

        glBufferStorage(GL_ARRAY_BUFFER, _instanceCapacityBytes, null,
            GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT);
        _instanceMap = glMapBufferRange(GL_ARRAY_BUFFER, 0, _instanceCapacityBytes,
            GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT);
        _instancePersistent = _instanceMap !is null;

        if (!_instancePersistent) {
            glBufferData(GL_ARRAY_BUFFER, _instanceCapacityBytes, null, GL_STREAM_DRAW);
        }
    }

    /**
     * Compile shader program for cell rendering.
     */
    bool compileShaders() {
        immutable string vertexSource = `#version 450 core

layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec4 a_rect;
layout(location = 2) in vec4 a_uv;
layout(location = 3) in vec4 a_fg;
layout(location = 4) in vec4 a_bg;
layout(location = 5) in float a_glyph;

out vec2 v_texcoord;
out vec4 v_fg;
out vec4 v_bg;
out float v_glyph;

uniform mat4 u_projection;

void main() {
    vec2 pos = a_rect.xy + a_pos * a_rect.zw;
    gl_Position = u_projection * vec4(pos, 0.0, 1.0);
    v_texcoord = mix(a_uv.xy, a_uv.zw, a_pos);
    v_fg = a_fg;
    v_bg = a_bg;
    v_glyph = a_glyph;
}
`;

        immutable string fragmentSource = `#version 450 core

in vec2 v_texcoord;
in vec4 v_fg;
in vec4 v_bg;
in float v_glyph;

out vec4 fragColor;

uniform sampler2D u_font_atlas;
uniform float u_bell;

void main() {
    float flash = clamp(u_bell, 0.0, 1.0);
    if (v_glyph > 0.5) {
        float alpha = texture(u_font_atlas, v_texcoord).r;
        vec3 color = mix(v_fg.rgb, vec3(1.0), flash);
        fragColor = vec4(color, alpha);
    } else {
        vec3 color = mix(v_bg.rgb, vec3(1.0), flash);
        fragColor = vec4(color, 1.0);
    }
}
`;

        GLuint vertexShader = glCreateShader(GL_VERTEX_SHADER);
        auto vertexPtr = vertexSource.ptr;
        GLint vertexLen = cast(GLint)vertexSource.length;
        glShaderSource(vertexShader, 1, &vertexPtr, &vertexLen);
        glCompileShader(vertexShader);

        GLint status;
        glGetShaderiv(vertexShader, GL_COMPILE_STATUS, &status);
        if (status != GL_TRUE) {
            char[512] log;
            glGetShaderInfoLog(vertexShader, 512, null, log.ptr);
            stderr.writefln("Vertex shader error: %s", log);
            return false;
        }

        GLuint fragmentShader = glCreateShader(GL_FRAGMENT_SHADER);
        auto fragmentPtr = fragmentSource.ptr;
        GLint fragmentLen = cast(GLint)fragmentSource.length;
        glShaderSource(fragmentShader, 1, &fragmentPtr, &fragmentLen);
        glCompileShader(fragmentShader);

        glGetShaderiv(fragmentShader, GL_COMPILE_STATUS, &status);
        if (status != GL_TRUE) {
            char[512] log;
            glGetShaderInfoLog(fragmentShader, 512, null, log.ptr);
            stderr.writefln("Fragment shader error: %s", log);
            glDeleteShader(vertexShader);
            return false;
        }

        _shaderProgram = glCreateProgram();
        glAttachShader(_shaderProgram, vertexShader);
        glAttachShader(_shaderProgram, fragmentShader);
        glLinkProgram(_shaderProgram);

        glGetProgramiv(_shaderProgram, GL_LINK_STATUS, &status);
        if (status != GL_TRUE) {
            char[512] log;
            glGetProgramInfoLog(_shaderProgram, 512, null, log.ptr);
            stderr.writefln("Shader link error: %s", log);
            glDeleteShader(vertexShader);
            glDeleteShader(fragmentShader);
            return false;
        }

        glDeleteShader(vertexShader);
        glDeleteShader(fragmentShader);

        _projectionLoc = glGetUniformLocation(_shaderProgram, "u_projection");
        _fontAtlasLoc = glGetUniformLocation(_shaderProgram, "u_font_atlas");
        _bellLoc = glGetUniformLocation(_shaderProgram, "u_bell");

        return true;
    }

    /**
     * Create VAO/VBO for instanced rendering.
     */
    bool createBuffers() {
        glGenVertexArrays(1, &_vao);
        glBindVertexArray(_vao);

        glGenBuffers(1, &_quadVbo);
        glBindBuffer(GL_ARRAY_BUFFER, _quadVbo);

        QuadVertex[6] quad = [
            QuadVertex(0.0f, 0.0f),
            QuadVertex(1.0f, 0.0f),
            QuadVertex(1.0f, 1.0f),
            QuadVertex(0.0f, 0.0f),
            QuadVertex(1.0f, 1.0f),
            QuadVertex(0.0f, 1.0f),
        ];

        glBufferData(GL_ARRAY_BUFFER, quad.sizeof, quad.ptr, GL_STATIC_DRAW);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, QuadVertex.sizeof, cast(void*)0);
        glEnableVertexAttribArray(0);

        glGenBuffers(1, &_instanceVbo);
        glBindBuffer(GL_ARRAY_BUFFER, _instanceVbo);
        glBufferData(GL_ARRAY_BUFFER, _maxCells * 2 * CellInstance.sizeof, null, GL_DYNAMIC_DRAW);

        immutable size_t stride = CellInstance.sizeof;

        glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, cast(GLint)stride,
                             cast(void*)CellInstance.x.offsetof);
        glEnableVertexAttribArray(1);
        glVertexAttribDivisor(1, 1);

        glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, cast(GLint)stride,
                             cast(void*)CellInstance.u0.offsetof);
        glEnableVertexAttribArray(2);
        glVertexAttribDivisor(2, 1);

        glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE, cast(GLint)stride,
                             cast(void*)CellInstance.fgR.offsetof);
        glEnableVertexAttribArray(3);
        glVertexAttribDivisor(3, 1);

        glVertexAttribPointer(4, 4, GL_FLOAT, GL_FALSE, cast(GLint)stride,
                             cast(void*)CellInstance.bgR.offsetof);
        glEnableVertexAttribArray(4);
        glVertexAttribDivisor(4, 1);

        glVertexAttribPointer(5, 1, GL_FLOAT, GL_FALSE, cast(GLint)stride,
                             cast(void*)CellInstance.glyphEnabled.offsetof);
        glEnableVertexAttribArray(5);
        glVertexAttribDivisor(5, 1);

        glBindVertexArray(0);
        return true;
    }
}

/**
 * Create orthographic projection matrix.
 */
float[16] orthoMatrix(float left, float right, float bottom, float top) @nogc nothrow {
    float[16] m = 0.0f;
    m[0] = 2.0f / (right - left);
    m[5] = 2.0f / (top - bottom);
    m[10] = -1.0f;
    m[12] = -(right + left) / (right - left);
    m[13] = -(top + bottom) / (top - bottom);
    m[15] = 1.0f;
    return m;
}

private float toLinear(float channel) @nogc nothrow {
    if (channel <= 0.03928f) {
        return channel / 12.92f;
    }
    return cast(float)pow((channel + 0.055f) / 1.055f, 2.4f);
}

private float maxf(float a, float b) @nogc nothrow {
    return a > b ? a : b;
}

private float relativeLuminance(in float[4] color) @nogc nothrow {
    float r = toLinear(color[0]);
    float g = toLinear(color[1]);
    float b = toLinear(color[2]);
    return 0.2126f * r + 0.7152f * g + 0.0722f * b;
}

private float[4] highContrastCursor(in float[4] background) @nogc nothrow {
    float lum = relativeLuminance(background);
    float contrastWhite = 1.05f / (lum + 0.05f);
    float contrastBlack = (lum + 0.05f) / 0.05f;
    return contrastWhite >= contrastBlack ? [1.0f, 1.0f, 1.0f, 1.0f]
                                          : [0.0f, 0.0f, 0.0f, 1.0f];
}

private float[4] cursorTextColor(in float[4] cursorColor) @nogc nothrow {
    return cursorColor[0] > 0.5f ? [0.0f, 0.0f, 0.0f, 1.0f]
                                 : [1.0f, 1.0f, 1.0f, 1.0f];
}
