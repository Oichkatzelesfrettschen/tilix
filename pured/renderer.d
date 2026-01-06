/**
 * Terminal Cell Renderer
 *
 * Batched OpenGL renderer for terminal cells. Uses instanced rendering
 * to draw all cells in minimal draw calls.
 *
 * Key features:
 * - Batched quad rendering for cells
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
import pured.emulator;
import arsd.terminalemulator : TerminalEmulator;
import std.stdio : stderr, writefln;

/**
 * Vertex data for a single cell quad.
 *
 * Each cell is rendered as a quad with:
 * - Position (2 floats)
 * - Texture coordinate (2 floats)
 * - Foreground color (4 floats)
 * - Background color (4 floats)
 *
 * Total: 12 floats per vertex, 4 vertices per cell = 48 floats per cell
 */
struct CellVertex {
    float x, y;           // Position
    float u, v;           // Texture coordinate
    float fgR, fgG, fgB, fgA;  // Foreground color
    float bgR, bgG, bgB, bgA;  // Background color
}

/**
 * Terminal cell renderer using OpenGL.
 *
 * Renders terminal cells as textured quads with proper colors.
 */
class CellRenderer {
private:
    FontAtlas _fontAtlas;
    GLuint _vao;
    GLuint _vbo;
    GLuint _ebo;
    GLuint _shaderProgram;

    // Uniform locations
    GLint _projectionLoc;
    GLint _fontAtlasLoc;

    // Vertex buffer
    CellVertex[] _vertices;
    uint[] _indices;
    int _maxCells;

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

        // Create font atlas
        _fontAtlas = new FontAtlas();
        if (!_fontAtlas.initialize(null, 16)) {
            stderr.writefln("Error: Failed to initialize font atlas");
            return false;
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
        if (_shaderProgram != 0) {
            glDeleteProgram(_shaderProgram);
            _shaderProgram = 0;
        }
        if (_vao != 0) {
            glDeleteVertexArrays(1, &_vao);
            _vao = 0;
        }
        if (_vbo != 0) {
            glDeleteBuffers(1, &_vbo);
            _vbo = 0;
        }
        if (_ebo != 0) {
            glDeleteBuffers(1, &_ebo);
            _ebo = 0;
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
     *   emulator = Terminal emulator with cell data
     *   cursorVisible = Whether to render cursor
     */
    void render(PureDEmulator emulator, bool cursorVisible = true) {
        if (emulator is null) return;

        int cols = emulator.cols;
        int rows = emulator.rows;
        int cellW = _fontAtlas.cellWidth;
        int cellH = _fontAtlas.cellHeight;

        // Build vertex data
        _vertices.length = 0;
        _indices.length = 0;

        uint vertexIndex = 0;

        foreach (row; 0 .. rows) {
            foreach (col; 0 .. cols) {
                auto cell = emulator.getCell(col, row);

                // Get character
                dchar ch = ' ';
                if (!cell.hasNonCharacterData) {
                    ch = cell.ch;
                    if (ch == 0) ch = ' ';
                }

                // Get colors
                float[4] fg, bg;
                if (!cell.hasNonCharacterData) {
                    attributesToColors(cell.attributes, fg, bg);
                } else {
                    fg = [0.9f, 0.9f, 0.9f, 1.0f];
                    bg = [0.1f, 0.1f, 0.15f, 1.0f];
                }

                // Check if cursor position
                bool isCursor = cursorVisible &&
                               col == emulator.cursorCol &&
                               row == emulator.cursorRow;

                if (isCursor) {
                    // Invert colors for cursor
                    auto tmp = fg;
                    fg = bg;
                    bg = tmp;
                    bg[3] = 1.0f;  // Ensure cursor is opaque
                }

                // Calculate cell position
                float x0 = col * cellW;
                float y0 = row * cellH;
                float x1 = x0 + cellW;
                float y1 = y0 + cellH;

                // Add background quad (UV=0 so shader uses bg color directly)
                addQuad(x0, y0, x1, y1, 0, 0, 0, 0, fg, bg, true);

                // Add glyph quad if character is visible
                if (ch != ' ' && ch != 0) {
                    auto glyph = _fontAtlas.getGlyph(ch);
                    if (glyph.valid && glyph.width > 0 && glyph.height > 0) {
                        // Position glyph within cell using bearing
                        float gx0 = x0 + glyph.bearingX;
                        float gy0 = y0 + (cellH - glyph.bearingY);
                        float gx1 = gx0 + glyph.width;
                        float gy1 = gy0 + glyph.height;

                        addQuad(gx0, gy0, gx1, gy1,
                               glyph.u0, glyph.v0, glyph.u1, glyph.v1,
                               fg, bg, false);
                    }
                }
            }
        }

        // Upload and render
        if (_vertices.length > 0) {
            glUseProgram(_shaderProgram);

            // Enable blending for proper alpha compositing
            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

            // Set projection matrix (orthographic)
            float[16] projection = orthoMatrix(0, _viewportWidth, _viewportHeight, 0);
            glUniformMatrix4fv(_projectionLoc, 1, GL_FALSE, projection.ptr);

            // Bind font atlas
            _fontAtlas.bind(0);
            glUniform1i(_fontAtlasLoc, 0);

            // Upload vertex data
            glBindVertexArray(_vao);
            glBindBuffer(GL_ARRAY_BUFFER, _vbo);
            glBufferData(GL_ARRAY_BUFFER, _vertices.length * CellVertex.sizeof,
                        _vertices.ptr, GL_DYNAMIC_DRAW);

            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _ebo);
            glBufferData(GL_ELEMENT_ARRAY_BUFFER, _indices.length * uint.sizeof,
                        _indices.ptr, GL_DYNAMIC_DRAW);

            // Draw
            glDrawElements(GL_TRIANGLES, cast(int)_indices.length, GL_UNSIGNED_INT, null);

            glBindVertexArray(0);
            glDisable(GL_BLEND);
        }
    }

    /// Cell width in pixels
    @property int cellWidth() const {
        return _fontAtlas !is null ? _fontAtlas.cellWidth : 10;
    }

    /// Cell height in pixels
    @property int cellHeight() const {
        return _fontAtlas !is null ? _fontAtlas.cellHeight : 20;
    }

private:
    /**
     * Add a quad to the vertex buffer.
     */
    void addQuad(float x0, float y0, float x1, float y1,
                 float u0, float v0, float u1, float v1,
                 float[4] fg, float[4] bg, bool isBackground) {
        uint baseIdx = cast(uint)(_vertices.length);

        // For background quads, use zero UV (will sample solid color)
        // For glyph quads, use actual UV

        // Bottom-left
        _vertices ~= CellVertex(x0, y1, u0, v1,
                                fg[0], fg[1], fg[2], fg[3],
                                bg[0], bg[1], bg[2], bg[3]);
        // Bottom-right
        _vertices ~= CellVertex(x1, y1, u1, v1,
                                fg[0], fg[1], fg[2], fg[3],
                                bg[0], bg[1], bg[2], bg[3]);
        // Top-right
        _vertices ~= CellVertex(x1, y0, u1, v0,
                                fg[0], fg[1], fg[2], fg[3],
                                bg[0], bg[1], bg[2], bg[3]);
        // Top-left
        _vertices ~= CellVertex(x0, y0, u0, v0,
                                fg[0], fg[1], fg[2], fg[3],
                                bg[0], bg[1], bg[2], bg[3]);

        // Two triangles
        _indices ~= baseIdx;
        _indices ~= baseIdx + 1;
        _indices ~= baseIdx + 2;
        _indices ~= baseIdx;
        _indices ~= baseIdx + 2;
        _indices ~= baseIdx + 3;
    }

    /**
     * Compile shader program for cell rendering.
     */
    bool compileShaders() {
        // Vertex shader
        immutable string vertexSource = `#version 450 core

layout(location = 0) in vec2 a_position;
layout(location = 1) in vec2 a_texcoord;
layout(location = 2) in vec4 a_fg_color;
layout(location = 3) in vec4 a_bg_color;

out vec2 v_texcoord;
out vec4 v_fg_color;
out vec4 v_bg_color;

uniform mat4 u_projection;

void main() {
    gl_Position = u_projection * vec4(a_position, 0.0, 1.0);
    v_texcoord = a_texcoord;
    v_fg_color = a_fg_color;
    v_bg_color = a_bg_color;
}
`;

        // Fragment shader
        immutable string fragmentSource = `#version 450 core

in vec2 v_texcoord;
in vec4 v_fg_color;
in vec4 v_bg_color;

out vec4 fragColor;

uniform sampler2D u_font_atlas;

void main() {
    // First render background color
    vec3 color = v_bg_color.rgb;

    // If we have valid UV coords (not at origin), sample glyph
    if (v_texcoord.x > 0.001 || v_texcoord.y > 0.001) {
        float alpha = texture(u_font_atlas, v_texcoord).r;
        color = mix(v_bg_color.rgb, v_fg_color.rgb, alpha);
    }

    fragColor = vec4(color, 1.0);
}
`;

        // Compile vertex shader
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

        // Compile fragment shader
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

        // Link program
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

        // Get uniform locations
        _projectionLoc = glGetUniformLocation(_shaderProgram, "u_projection");
        _fontAtlasLoc = glGetUniformLocation(_shaderProgram, "u_font_atlas");

        return true;
    }

    /**
     * Create VAO/VBO/EBO for rendering.
     */
    bool createBuffers() {
        glGenVertexArrays(1, &_vao);
        glBindVertexArray(_vao);

        glGenBuffers(1, &_vbo);
        glBindBuffer(GL_ARRAY_BUFFER, _vbo);

        glGenBuffers(1, &_ebo);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _ebo);

        // Vertex layout
        immutable size_t stride = CellVertex.sizeof;

        // Position
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, cast(GLint)stride,
                             cast(void*)CellVertex.x.offsetof);
        glEnableVertexAttribArray(0);

        // Texcoord
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, cast(GLint)stride,
                             cast(void*)CellVertex.u.offsetof);
        glEnableVertexAttribArray(1);

        // Foreground color
        glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, cast(GLint)stride,
                             cast(void*)CellVertex.fgR.offsetof);
        glEnableVertexAttribArray(2);

        // Background color
        glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE, cast(GLint)stride,
                             cast(void*)CellVertex.bgR.offsetof);
        glEnableVertexAttribArray(3);

        glBindVertexArray(0);

        return true;
    }
}

/**
 * Create orthographic projection matrix.
 */
float[16] orthoMatrix(float left, float right, float bottom, float top) {
    float[16] m = 0.0f;
    m[0] = 2.0f / (right - left);
    m[5] = 2.0f / (top - bottom);
    m[10] = -1.0f;
    m[12] = -(right + left) / (right - left);
    m[13] = -(top + bottom) / (top - bottom);
    m[15] = 1.0f;
    return m;
}
