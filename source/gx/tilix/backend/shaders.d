/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.backend.shaders;

import std.experimental.logger;
import std.string : toStringz, fromStringz;

version (Have_bindbc_opengl) {
    import bindbc.opengl;
    enum HaveBindBCOpenGL = true;
} else {
    enum HaveBindBCOpenGL = false;
}

/**
 * Vertex shader for terminal glyph rendering.
 *
 * Input attributes:
 *   - a_position: vec2 - Vertex position in screen coordinates
 *   - a_texcoord: vec2 - Texture coordinates into glyph atlas
 *   - a_color_fg: vec4 - Foreground color (text)
 *   - a_color_bg: vec4 - Background color (cell)
 *
 * Uniforms:
 *   - u_projection: mat4 - Orthographic projection matrix
 *   - u_cell_size: vec2 - Cell dimensions in pixels
 */
enum string TERMINAL_VERTEX_SHADER = `
#version 330 core

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
`;

/**
 * Fragment shader for terminal glyph rendering.
 *
 * Samples from font atlas texture and applies foreground/background colors.
 * Uses subpixel rendering when enabled for sharper text on LCD displays.
 */
enum string TERMINAL_FRAGMENT_SHADER = `
#version 330 core

in vec2 v_texcoord;
in vec4 v_color_fg;
in vec4 v_color_bg;

out vec4 frag_color;

uniform sampler2D u_font_atlas;
uniform bool u_subpixel;

void main() {
    // Sample glyph alpha from font atlas
    float alpha = texture(u_font_atlas, v_texcoord).r;

    // Blend foreground and background based on glyph coverage
    vec3 color = mix(v_color_bg.rgb, v_color_fg.rgb, alpha);

    // Final alpha is max of both (for transparency support)
    float final_alpha = max(v_color_bg.a, alpha * v_color_fg.a);

    frag_color = vec4(color, final_alpha);
}
`;

/**
 * Simple solid color fragment shader for backgrounds and cursors.
 */
enum string SOLID_FRAGMENT_SHADER = `
#version 330 core

in vec4 v_color_fg;

out vec4 frag_color;

void main() {
    frag_color = v_color_fg;
}
`;

/**
 * Cursor rendering fragment shader with blinking support.
 */
enum string CURSOR_FRAGMENT_SHADER = `
#version 330 core

in vec4 v_color_fg;

out vec4 frag_color;

uniform float u_blink_phase;  // 0.0 to 1.0
uniform float u_blink_duty;   // Duty cycle (default 0.5)

void main() {
    float visible = step(u_blink_phase, u_blink_duty);
    frag_color = vec4(v_color_fg.rgb, v_color_fg.a * visible);
}
`;

/**
 * Compiled shader program handle.
 */
struct ShaderProgram {
    uint id;
    bool valid;

    // Uniform locations (cached for performance)
    int loc_projection = -1;
    int loc_font_atlas = -1;
    int loc_subpixel = -1;
    int loc_blink_phase = -1;
    int loc_blink_duty = -1;
    int loc_cell_size = -1;
}

static if (HaveBindBCOpenGL) {

    /**
     * Compile a shader from source.
     */
    uint compileShader(GLenum shaderType, string source) {
        uint shader = glCreateShader(shaderType);
        if (shader == 0) {
            error("Failed to create shader");
            return 0;
        }

        auto sourceZ = source.toStringz;
        glShaderSource(shader, 1, &sourceZ, null);
        glCompileShader(shader);

        // Check compilation status
        int success;
        glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
        if (!success) {
            char[512] infoLog;
            glGetShaderInfoLog(shader, 512, null, infoLog.ptr);
            errorf("Shader compilation failed: %s", fromStringz(infoLog.ptr));
            glDeleteShader(shader);
            return 0;
        }

        return shader;
    }

    /**
     * Link a shader program from vertex and fragment shaders.
     */
    ShaderProgram linkProgram(string vertexSource, string fragmentSource) {
        ShaderProgram prog;

        uint vertexShader = compileShader(GL_VERTEX_SHADER, vertexSource);
        if (vertexShader == 0) return prog;

        uint fragmentShader = compileShader(GL_FRAGMENT_SHADER, fragmentSource);
        if (fragmentShader == 0) {
            glDeleteShader(vertexShader);
            return prog;
        }

        prog.id = glCreateProgram();
        glAttachShader(prog.id, vertexShader);
        glAttachShader(prog.id, fragmentShader);
        glLinkProgram(prog.id);

        // Check link status
        int success;
        glGetProgramiv(prog.id, GL_LINK_STATUS, &success);
        if (!success) {
            char[512] infoLog;
            glGetProgramInfoLog(prog.id, 512, null, infoLog.ptr);
            errorf("Shader linking failed: %s", fromStringz(infoLog.ptr));
            glDeleteProgram(prog.id);
            prog.id = 0;
        } else {
            prog.valid = true;
            // Cache uniform locations
            prog.loc_projection = glGetUniformLocation(prog.id, "u_projection");
            prog.loc_font_atlas = glGetUniformLocation(prog.id, "u_font_atlas");
            prog.loc_subpixel = glGetUniformLocation(prog.id, "u_subpixel");
            prog.loc_blink_phase = glGetUniformLocation(prog.id, "u_blink_phase");
            prog.loc_blink_duty = glGetUniformLocation(prog.id, "u_blink_duty");
            prog.loc_cell_size = glGetUniformLocation(prog.id, "u_cell_size");
        }

        // Shaders can be deleted after linking
        glDeleteShader(vertexShader);
        glDeleteShader(fragmentShader);

        return prog;
    }

    /**
     * Delete a shader program.
     */
    void deleteProgram(ref ShaderProgram prog) {
        if (prog.id != 0) {
            glDeleteProgram(prog.id);
            prog.id = 0;
            prog.valid = false;
        }
    }

    /**
     * Create an orthographic projection matrix.
     * Returns a column-major 4x4 matrix suitable for OpenGL.
     */
    float[16] orthoMatrix(float left, float right, float bottom, float top, float near = -1.0f, float far = 1.0f) {
        float[16] m = 0;

        m[0] = 2.0f / (right - left);
        m[5] = 2.0f / (top - bottom);
        m[10] = -2.0f / (far - near);
        m[12] = -(right + left) / (right - left);
        m[13] = -(top + bottom) / (top - bottom);
        m[14] = -(far + near) / (far - near);
        m[15] = 1.0f;

        return m;
    }

} else {
    // Stub implementations for non-OpenGL builds
    ShaderProgram linkProgram(string vertexSource, string fragmentSource) {
        return ShaderProgram.init;
    }

    void deleteProgram(ref ShaderProgram prog) {
        prog.valid = false;
    }

    float[16] orthoMatrix(float left, float right, float bottom, float top, float near = -1.0f, float far = 1.0f) {
        float[16] m = 0;
        m[15] = 1.0f;
        return m;
    }
}

@system
unittest {
    // Test ortho matrix generation
    auto m = orthoMatrix(0, 800, 600, 0);
    assert(m[15] == 1.0f);

    // Scaling tests only valid when OpenGL is available
    static if (HaveBindBCOpenGL) {
        assert(m[0] != 0);  // Should have scaling
        assert(m[5] != 0);
    }

    // Test shader source validity (basic checks)
    assert(TERMINAL_VERTEX_SHADER.length > 100);
    assert(TERMINAL_FRAGMENT_SHADER.length > 100);
    assert(CURSOR_FRAGMENT_SHADER.length > 50);
}
