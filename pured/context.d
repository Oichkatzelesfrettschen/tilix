/**
 * OpenGL Context and Rendering Setup
 *
 * Provides OpenGL 4.5 context initialization, shader compilation,
 * and basic rendering utilities for the Pure D terminal backend.
 *
 * Key features:
 * - OpenGL 4.5 Core Profile initialization
 * - Shader program compilation and linking
 * - VAO/VBO management for instanced rendering
 * - Error checking and debug output
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.context;

version (PURE_D_BACKEND):

import bindbc.opengl;
import std.string : toStringz, fromStringz;
import std.stdio : stderr, writefln;
import std.conv : to;

/**
 * OpenGL rendering context for terminal.
 *
 * Manages shader programs, vertex arrays, and rendering state.
 */
class GLContext {
private:
    GLuint _shaderProgram;
    GLuint _vao;
    GLuint _vbo;
    GLuint _ebo;

    int _viewportWidth;
    int _viewportHeight;

    // Uniform locations
    GLint _projectionLoc;
    GLint _fontAtlasLoc;
    GLint _cellSizeLoc;

public:
    /**
     * Initialize OpenGL state for terminal rendering.
     *
     * Returns: true if initialization succeeded
     */
    bool initialize() {
        // Check OpenGL version
        auto versionStr = cast(const(char)*)glGetString(GL_VERSION);
        if (versionStr is null) {
            stderr.writefln("Error: Failed to get OpenGL version");
            return false;
        }
        stderr.writefln("OpenGL Version: %s", fromStringz(versionStr));

        auto rendererStr = cast(const(char)*)glGetString(GL_RENDERER);
        if (rendererStr !is null) {
            stderr.writefln("OpenGL Renderer: %s", fromStringz(rendererStr));
        }

        // Enable blending for font rendering
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        // Disable depth testing (2D rendering)
        glDisable(GL_DEPTH_TEST);

        // Set clear color (terminal background)
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);

        // Compile shaders
        if (!compileShaders()) {
            stderr.writefln("Error: Failed to compile shaders");
            return false;
        }

        // Create VAO/VBO for quad rendering
        if (!createBuffers()) {
            stderr.writefln("Error: Failed to create buffers");
            return false;
        }

        return true;
    }

    /**
     * Cleanup OpenGL resources.
     */
    void terminate() {
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
     * Update viewport size.
     */
    void setViewport(int width, int height) {
        _viewportWidth = width;
        _viewportHeight = height;
        glViewport(0, 0, width, height);
    }

    /**
     * Clear the framebuffer.
     */
    void clear() {
        glClear(GL_COLOR_BUFFER_BIT);
    }

    /**
     * Set background color.
     */
    void setClearColor(float r, float g, float b, float a = 1.0f) {
        glClearColor(r, g, b, a);
    }

    /**
     * Use the terminal shader program.
     */
    void useProgram() {
        glUseProgram(_shaderProgram);
    }

    /**
     * Bind the VAO for rendering.
     */
    void bindVAO() {
        glBindVertexArray(_vao);
    }

    /**
     * Get shader program handle.
     */
    @property GLuint shaderProgram() const {
        return _shaderProgram;
    }

    /**
     * Get uniform location by name.
     */
    GLint getUniformLocation(string name) {
        return glGetUniformLocation(_shaderProgram, name.toStringz);
    }

    /**
     * Check for OpenGL errors.
     *
     * Returns: true if no errors
     */
    static bool checkError(string context = "") {
        GLenum err = glGetError();
        if (err != GL_NO_ERROR) {
            string errStr;
            switch (err) {
                case GL_INVALID_ENUM: errStr = "GL_INVALID_ENUM"; break;
                case GL_INVALID_VALUE: errStr = "GL_INVALID_VALUE"; break;
                case GL_INVALID_OPERATION: errStr = "GL_INVALID_OPERATION"; break;
                case GL_OUT_OF_MEMORY: errStr = "GL_OUT_OF_MEMORY"; break;
                case GL_INVALID_FRAMEBUFFER_OPERATION: errStr = "GL_INVALID_FRAMEBUFFER_OPERATION"; break;
                default: errStr = "Unknown error " ~ err.to!string; break;
            }
            stderr.writefln("OpenGL Error [%s]: %s", context, errStr);
            return false;
        }
        return true;
    }

private:
    /**
     * Compile and link shader program.
     */
    bool compileShaders() {
        // Vertex shader for terminal cell rendering
        immutable string vertexSource = q{
            #version 450 core

            layout(location = 0) in vec2 a_position;
            layout(location = 1) in vec2 a_texcoord;
            layout(location = 2) in vec4 a_color_fg;
            layout(location = 3) in vec4 a_color_bg;

            out vec2 v_texcoord;
            out vec4 v_color_fg;
            out vec4 v_color_bg;

            uniform mat4 u_projection;

            void main() {
                gl_Position = u_projection * vec4(a_position, 0.0, 1.0);
                v_texcoord = a_texcoord;
                v_color_fg = a_color_fg;
                v_color_bg = a_color_bg;
            }
        };

        // Fragment shader for glyph rendering
        immutable string fragmentSource = q{
            #version 450 core

            in vec2 v_texcoord;
            in vec4 v_color_fg;
            in vec4 v_color_bg;

            out vec4 fragColor;

            uniform sampler2D u_font_atlas;

            void main() {
                // Sample glyph alpha from font atlas (R channel)
                float alpha = texture(u_font_atlas, v_texcoord).r;

                // Blend foreground and background based on glyph coverage
                vec3 color = mix(v_color_bg.rgb, v_color_fg.rgb, alpha);

                // Output with full opacity (background already blended)
                fragColor = vec4(color, 1.0);
            }
        };

        // Compile vertex shader
        GLuint vertexShader = glCreateShader(GL_VERTEX_SHADER);
        auto vertexPtr = vertexSource.ptr;
        GLint vertexLen = cast(GLint)vertexSource.length;
        glShaderSource(vertexShader, 1, &vertexPtr, &vertexLen);
        glCompileShader(vertexShader);

        if (!checkShaderCompile(vertexShader, "vertex")) {
            glDeleteShader(vertexShader);
            return false;
        }

        // Compile fragment shader
        GLuint fragmentShader = glCreateShader(GL_FRAGMENT_SHADER);
        auto fragmentPtr = fragmentSource.ptr;
        GLint fragmentLen = cast(GLint)fragmentSource.length;
        glShaderSource(fragmentShader, 1, &fragmentPtr, &fragmentLen);
        glCompileShader(fragmentShader);

        if (!checkShaderCompile(fragmentShader, "fragment")) {
            glDeleteShader(vertexShader);
            glDeleteShader(fragmentShader);
            return false;
        }

        // Link program
        _shaderProgram = glCreateProgram();
        glAttachShader(_shaderProgram, vertexShader);
        glAttachShader(_shaderProgram, fragmentShader);
        glLinkProgram(_shaderProgram);

        // Check link status
        GLint linkStatus;
        glGetProgramiv(_shaderProgram, GL_LINK_STATUS, &linkStatus);
        if (linkStatus != GL_TRUE) {
            GLint logLength;
            glGetProgramiv(_shaderProgram, GL_INFO_LOG_LENGTH, &logLength);
            if (logLength > 0) {
                char[] log = new char[logLength];
                glGetProgramInfoLog(_shaderProgram, logLength, null, log.ptr);
                stderr.writefln("Shader link error: %s", log);
            }
            glDeleteShader(vertexShader);
            glDeleteShader(fragmentShader);
            glDeleteProgram(_shaderProgram);
            _shaderProgram = 0;
            return false;
        }

        // Cleanup shader objects (now linked into program)
        glDeleteShader(vertexShader);
        glDeleteShader(fragmentShader);

        // Get uniform locations
        _projectionLoc = glGetUniformLocation(_shaderProgram, "u_projection");
        _fontAtlasLoc = glGetUniformLocation(_shaderProgram, "u_font_atlas");

        return true;
    }

    /**
     * Check shader compilation status.
     */
    bool checkShaderCompile(GLuint shader, string shaderType) {
        GLint compileStatus;
        glGetShaderiv(shader, GL_COMPILE_STATUS, &compileStatus);
        if (compileStatus != GL_TRUE) {
            GLint logLength;
            glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
            if (logLength > 0) {
                char[] log = new char[logLength];
                glGetShaderInfoLog(shader, logLength, null, log.ptr);
                stderr.writefln("Shader compile error (%s): %s", shaderType, log);
            }
            return false;
        }
        return true;
    }

    /**
     * Create VAO/VBO for rendering.
     */
    bool createBuffers() {
        // Create VAO
        glGenVertexArrays(1, &_vao);
        glBindVertexArray(_vao);

        // Create VBO
        glGenBuffers(1, &_vbo);
        glBindBuffer(GL_ARRAY_BUFFER, _vbo);

        // Vertex layout: position (2), texcoord (2), fg_color (4), bg_color (4)
        // Total: 12 floats per vertex, 4 vertices per quad = 48 floats per cell
        immutable size_t stride = 12 * float.sizeof;

        // Position attribute
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, cast(GLint)stride, cast(void*)0);
        glEnableVertexAttribArray(0);

        // Texcoord attribute
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, cast(GLint)stride, cast(void*)(2 * float.sizeof));
        glEnableVertexAttribArray(1);

        // Foreground color attribute
        glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, cast(GLint)stride, cast(void*)(4 * float.sizeof));
        glEnableVertexAttribArray(2);

        // Background color attribute
        glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE, cast(GLint)stride, cast(void*)(8 * float.sizeof));
        glEnableVertexAttribArray(3);

        // Create EBO for indexed rendering
        glGenBuffers(1, &_ebo);

        glBindVertexArray(0);

        return checkError("createBuffers");
    }
}

/**
 * Create an orthographic projection matrix for 2D rendering.
 *
 * Params:
 *   left = Left boundary
 *   right = Right boundary
 *   bottom = Bottom boundary
 *   top = Top boundary
 *
 * Returns: 4x4 projection matrix as column-major array
 */
float[16] orthoProjection(float left, float right, float bottom, float top) {
    float[16] m = 0.0f;

    m[0] = 2.0f / (right - left);
    m[5] = 2.0f / (top - bottom);
    m[10] = -1.0f;
    m[12] = -(right + left) / (right - left);
    m[13] = -(top + bottom) / (top - bottom);
    m[15] = 1.0f;

    return m;
}
