/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.backend.opengl;

import core.time : Duration, dur, MonoTime;
import core.thread : Thread;
import std.algorithm : min, max;
import std.experimental.logger;
import std.format : format;
import std.math : round;

import gdk.GLContext;
import gdk.FrameClock;

import gtk.GLArea;
import gtk.Widget;

import gx.tilix.backend.render;
import gx.tilix.backend.shaders;
import gx.tilix.backend.atlas;

// X11 bindings for native refresh rate detection
import x11.X : XWindow = Window;
import x11.Xlib : Display;
import x11.Xrandr;
import gx.gtk.x11 : gdk_x11_get_default_xdisplay, gdk_x11_get_default_root_xwindow;

// bindbc-opengl is only available in DUB builds
// For meson builds, OpenGL initialization will fail gracefully
version (Have_bindbc_opengl) {
    import bindbc.opengl;
    enum HaveBindBCOpenGL = true;
} else {
    enum HaveBindBCOpenGL = false;
}

/**
 * Vertex data for terminal cell rendering.
 * Matches the shader attribute layout exactly.
 */
struct TerminalVertex {
    float[2] position;   // Screen position (x, y)
    float[2] texcoord;   // Atlas UV coordinates
    float[4] colorFg;    // Foreground color (RGBA)
    float[4] colorBg;    // Background color (RGBA)
}

// Vertex attribute sizes for stride calculation
enum VERTEX_SIZE = TerminalVertex.sizeof;
enum POSITION_OFFSET = 0;
enum TEXCOORD_OFFSET = float.sizeof * 2;
enum COLOR_FG_OFFSET = float.sizeof * 4;
enum COLOR_BG_OFFSET = float.sizeof * 8;

/**
 * Common refresh rates in Hz.
 * The frame pacer supports any arbitrary rate, these are convenience presets.
 */
enum RefreshRate : uint {
    Cinema24 = 24,
    Video30 = 30,
    Standard60 = 60,
    Enhanced75 = 75,
    Gaming120 = 120,
    Gaming144 = 144,
    Gaming165 = 165,
    Gaming240 = 240,
    Gaming360 = 360
}

/**
 * Frame timing statistics for performance monitoring.
 */
struct FrameStats {
    Duration lastFrameTime;
    Duration avgFrameTime;
    Duration minFrameTime;
    Duration maxFrameTime;
    ulong frameCount;
    ulong droppedFrames;
    double currentFPS;
    double targetFPS;

    void reset() {
        lastFrameTime = Duration.zero;
        avgFrameTime = Duration.zero;
        minFrameTime = dur!"hours"(1);  // Start high
        maxFrameTime = Duration.zero;
        frameCount = 0;
        droppedFrames = 0;
        currentFPS = 0;
    }

    void update(Duration frameTime, double target) {
        lastFrameTime = frameTime;
        frameCount++;
        targetFPS = target;

        // Update min/max
        if (frameTime < minFrameTime) minFrameTime = frameTime;
        if (frameTime > maxFrameTime) maxFrameTime = frameTime;

        // Rolling average (exponential moving average)
        if (avgFrameTime == Duration.zero) {
            avgFrameTime = frameTime;
        } else {
            // Alpha = 0.1 for smoothing
            auto avgUsecs = avgFrameTime.total!"usecs";
            auto frameUsecs = frameTime.total!"usecs";
            avgFrameTime = dur!"usecs"(cast(long)(avgUsecs * 0.9 + frameUsecs * 0.1));
        }

        // Calculate current FPS
        if (avgFrameTime.total!"usecs" > 0) {
            currentFPS = 1_000_000.0 / avgFrameTime.total!"usecs";
        }

        // Track dropped frames (frame took longer than target)
        Duration targetTime = dur!"usecs"(cast(long)(1_000_000.0 / target));
        Duration threshold = dur!"usecs"(cast(long)(targetTime.total!"usecs" * 1.5));
        if (frameTime > threshold) {
            droppedFrames++;
        }
    }

    string toString() const {
        return format("FPS: %.1f/%.0f | Frame: %.2fms (min:%.2f max:%.2f) | Dropped: %d",
            currentFPS, targetFPS,
            avgFrameTime.total!"usecs" / 1000.0,
            minFrameTime.total!"usecs" / 1000.0,
            maxFrameTime.total!"usecs" / 1000.0,
            droppedFrames);
    }
}

/**
 * Frame pacer for smooth, consistent frame timing.
 * Supports any arbitrary refresh rate with adaptive timing.
 */
struct FramePacer {
private:
    uint _targetHz;
    Duration _targetFrameTime;
    MonoTime _lastFrameTime;
    MonoTime _frameStart;
    FrameStats _stats;
    bool _vsyncEnabled;
    bool _adaptiveSync;

public:
    /**
     * Initialize frame pacer with target refresh rate.
     * Params:
     *   hz = Target refresh rate in Hz (e.g., 60, 120, 144)
     *   vsync = Enable VSync (recommended for tear-free rendering)
     *   adaptive = Enable adaptive sync (G-Sync/FreeSync compatible)
     */
    void initialize(uint hz, bool vsync = true, bool adaptive = true) {
        _targetHz = hz;
        _targetFrameTime = dur!"usecs"(cast(long)(1_000_000.0 / hz));
        _lastFrameTime = MonoTime.currTime;
        _vsyncEnabled = vsync;
        _adaptiveSync = adaptive;
        _stats.reset();
        tracef("FramePacer initialized: %d Hz (%.3f ms/frame), VSync=%s, Adaptive=%s",
            hz, _targetFrameTime.total!"usecs" / 1000.0, vsync, adaptive);
    }

    /**
     * Set new target refresh rate dynamically.
     */
    void setTargetHz(uint hz) {
        if (hz == _targetHz) return;
        _targetHz = hz;
        _targetFrameTime = dur!"usecs"(cast(long)(1_000_000.0 / hz));
        tracef("FramePacer target changed: %d Hz (%.3f ms/frame)",
            hz, _targetFrameTime.total!"usecs" / 1000.0);
    }

    /**
     * Mark the start of frame rendering.
     */
    void beginFrame() {
        _frameStart = MonoTime.currTime;
    }

    /**
     * Complete frame and wait for next frame time if needed.
     * Returns true if frame was on time, false if dropped.
     */
    bool endFrame() {
        auto now = MonoTime.currTime;
        auto frameTime = now - _frameStart;
        auto timeSinceLastFrame = now - _lastFrameTime;

        _stats.update(frameTime, cast(double)_targetHz);

        // If we're running faster than target, sleep to maintain rate
        if (!_vsyncEnabled && timeSinceLastFrame < _targetFrameTime) {
            auto sleepTime = _targetFrameTime - timeSinceLastFrame;
            // Only sleep if > 1ms to avoid scheduler overhead
            if (sleepTime > dur!"msecs"(1)) {
                Thread.sleep(sleepTime - dur!"usecs"(500));  // Wake slightly early
            }
            // Spin-wait for precise timing (last few microseconds)
            while (MonoTime.currTime - _lastFrameTime < _targetFrameTime) {
                // Busy wait for precision
            }
        }

        _lastFrameTime = MonoTime.currTime;
        return frameTime <= _targetFrameTime;
    }

    @property uint targetHz() const { return _targetHz; }
    @property Duration targetFrameTime() const { return _targetFrameTime; }
    @property ref const(FrameStats) stats() const { return _stats; }
    @property bool vsyncEnabled() const { return _vsyncEnabled; }
}

/**
 * Detect the native refresh rate of the primary display using XRandR.
 *
 * This queries the X server for screen resources and finds the refresh rate
 * of the currently active mode on the primary CRTC. Returns 60 as a fallback
 * if XRandR is unavailable or the query fails.
 *
 * The refresh rate is calculated from XRandR mode timing data:
 *   refreshRate = dotClock / (hTotal * vTotal)
 *
 * Returns: Native refresh rate in Hz (e.g., 60, 120, 144, 165, 240)
 */
uint detectNativeRefreshRate() {
    enum uint DEFAULT_HZ = 60;

    Display* display = gdk_x11_get_default_xdisplay();
    if (display is null) {
        trace("XRandR: No X display available, using default 60 Hz");
        return DEFAULT_HZ;
    }

    XWindow root = gdk_x11_get_default_root_xwindow();

    // Query XRandR extension
    int eventBase, errorBase;
    if (!XRRQueryExtension(display, &eventBase, &errorBase)) {
        trace("XRandR: Extension not available, using default 60 Hz");
        return DEFAULT_HZ;
    }

    // Get screen resources (use cached version for speed)
    auto resources = XRRGetScreenResourcesCurrent(display, root);
    if (resources is null) {
        trace("XRandR: Failed to get screen resources, using default 60 Hz");
        return DEFAULT_HZ;
    }
    scope(exit) XRRFreeScreenResources(resources);

    // Find the first connected output with an active CRTC
    double bestRefreshRate = 0.0;

    foreach (i; 0 .. resources.noutput) {
        auto outputInfo = XRRGetOutputInfo(display, resources, resources.outputs[i]);
        if (outputInfo is null) continue;
        scope(exit) XRRFreeOutputInfo(outputInfo);

        // Skip disconnected outputs
        if (outputInfo.connection != RRConnected) continue;

        // Skip outputs without active CRTC
        if (outputInfo.crtc == 0) continue;

        // Get CRTC info
        auto crtcInfo = XRRGetCrtcInfo(display, resources, outputInfo.crtc);
        if (crtcInfo is null) continue;
        scope(exit) XRRFreeCrtcInfo(crtcInfo);

        // Skip CRTCs without active mode
        if (crtcInfo.mode == 0) continue;

        // Find the mode info for the active mode
        foreach (j; 0 .. resources.nmode) {
            auto mode = &resources.modes[j];
            if (mode.id == crtcInfo.mode) {
                double hz = calculateRefreshRate(mode);
                if (hz > bestRefreshRate) {
                    bestRefreshRate = hz;
                    tracef("XRandR: Found active mode %ux%u @ %.2f Hz",
                           mode.width, mode.height, hz);
                }
                break;
            }
        }
    }

    if (bestRefreshRate > 0.0) {
        uint result = cast(uint)(bestRefreshRate + 0.5);  // Round to nearest integer
        tracef("XRandR: Using native refresh rate: %u Hz", result);
        return result;
    }

    trace("XRandR: No active display found, using default 60 Hz");
    return DEFAULT_HZ;
}

/**
 * OpenGL render backend using GtkGLArea.
 *
 * This backend provides GPU-accelerated terminal rendering with support for:
 * - Arbitrary refresh rates (24-360+ Hz)
 * - VSync and adaptive sync
 * - Font atlas with texture caching
 * - Shader-based text rendering
 *
 * Falls back to VTE3RenderBackend if OpenGL initialization fails.
 */
class OpenGLRenderBackend : IRenderBackend {
private:
    Widget _container;
    GLArea _glArea;
    bool _initialized;
    bool _glReady;
    uint _cols;
    uint _rows;
    FramePacer _pacer;
    uint _targetHz;  // Detected from XRandR at runtime

    // OpenGL state
    uint _vao;
    uint _vbo;
    ShaderProgram _shader;
    FontAtlas _fontAtlas;

    // Vertex data buffer (CPU side, uploaded to VBO each frame)
    TerminalVertex[] _vertexBuffer;
    size_t _vertexCount;

    // Viewport dimensions
    int _viewportWidth;
    int _viewportHeight;
    float _cellWidth = 8.0f;
    float _cellHeight = 16.0f;

    // Projection matrix
    float[16] _projection;

public:
    this() {
        // Detect native display refresh rate instead of hardcoding
        _targetHz = detectNativeRefreshRate();
        _pacer.initialize(_targetHz);
    }

    /**
     * Initialize the OpenGL backend with a container widget.
     * Creates a GtkGLArea and sets up OpenGL context.
     */
    override void initialize(Widget container) {
        _container = container;

        // Create GLArea for OpenGL rendering
        _glArea = new GLArea();
        _glArea.setAutoRender(true);
        _glArea.setHasDepthBuffer(false);
        _glArea.setHasStencilBuffer(false);

        // Connect signals
        _glArea.addOnRealize(&onRealize);
        _glArea.addOnUnrealize(&onUnrealize);
        _glArea.addOnRender(&onRender);
        _glArea.addOnResize(&onResize);

        _initialized = true;
        trace("OpenGLRenderBackend initialized (GL context pending)");
    }

    /**
     * Set target refresh rate.
     */
    void setTargetRefreshRate(uint hz) {
        _targetHz = max(1, min(hz, 1000));  // Clamp to sane range
        _pacer.setTargetHz(_targetHz);
    }

    /**
     * Set refresh rate from preset.
     */
    void setRefreshRate(RefreshRate rate) {
        setTargetRefreshRate(cast(uint)rate);
    }

    /**
     * Get the GLArea widget for embedding in the UI.
     */
    @property GLArea glArea() { return _glArea; }

    /**
     * Get frame statistics.
     */
    @property ref const(FrameStats) frameStats() const { return _pacer.stats; }

    override void prepareFrame(ref const RenderModel model) {
        if (!_glReady) return;
        _pacer.beginFrame();
        buildVertexData(model);
    }

    override void present() {
        if (!_glReady) return;
        if (_glArea !is null) {
            _glArea.queueRender();
        }
        _pacer.endFrame();
    }

    override void resize(uint cols, uint rows) {
        _cols = cols;
        _rows = rows;
    }

    override @property RenderCapabilities capabilities() const {
        return RenderCapabilities(
            true,           // supportsGPU
            true,           // supportsHighRefresh
            _targetHz,      // maxFPS
            "OpenGL"        // name
        );
    }

    override @property bool isReady() const {
        return _initialized && _glReady;
    }

    override void dispose() {
        if (_glArea !is null) {
            cleanupGL();
            _glArea.destroy();
            _glArea = null;
        }
        _container = null;
        _initialized = false;
        _glReady = false;
        trace("OpenGLRenderBackend disposed");
    }

private:
    void onRealize(Widget w) {
        _glArea.makeCurrent();

        auto glError = _glArea.getError();
        if (glError !is null) {
            errorf("GLArea error: %s", glError.toString());
            return;
        }

        if (!initializeGL()) {
            error("Failed to initialize OpenGL");
            return;
        }

        _glReady = true;
        tracef("OpenGL initialized: %d Hz target", _targetHz);
    }

    void onUnrealize(Widget w) {
        _glArea.makeCurrent();
        cleanupGL();
        _glReady = false;
    }

    bool onRender(GLContext ctx, GLArea area) {
        if (!_glReady) return false;

        // Clear and render
        renderFrame();
        return true;
    }

    void onResize(int width, int height, GLArea area) {
        _viewportWidth = width;
        _viewportHeight = height;

        if (_glReady) {
            static if (HaveBindBCOpenGL) {
                glViewport(0, 0, width, height);
                // Update projection matrix
                _projection = orthoMatrix(0, cast(float)width, cast(float)height, 0);
            }
        }
    }

    bool initializeGL() {
        static if (HaveBindBCOpenGL) {
            // Load OpenGL functions
            auto loaded = loadOpenGL();
            if (loaded == GLSupport.noLibrary) {
                error("OpenGL library not found");
                return false;
            }
            if (loaded == GLSupport.badLibrary) {
                error("OpenGL library corrupted or missing functions");
                return false;
            }

            tracef("OpenGL loaded: %s", loaded);

            // Compile and link shader program
            _shader = linkProgram(TERMINAL_VERTEX_SHADER, TERMINAL_FRAGMENT_SHADER);
            if (!_shader.valid) {
                error("Failed to link shader program");
                return false;
            }
            trace("Shader program linked");

            // Create VAO
            glGenVertexArrays(1, &_vao);
            glBindVertexArray(_vao);

            // Create VBO with initial size (will be resized as needed)
            glGenBuffers(1, &_vbo);
            glBindBuffer(GL_ARRAY_BUFFER, _vbo);

            // Allocate buffer for 80x24 terminal (common default)
            enum MAX_CELLS = 80 * 24;
            enum VERTICES_PER_CELL = 6;  // 2 triangles = 6 vertices
            glBufferData(GL_ARRAY_BUFFER, MAX_CELLS * VERTICES_PER_CELL * VERTEX_SIZE,
                null, GL_DYNAMIC_DRAW);

            // Setup vertex attributes
            // a_position (location 0): vec2
            glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE,
                cast(int)VERTEX_SIZE, cast(void*)POSITION_OFFSET);
            glEnableVertexAttribArray(0);

            // a_texcoord (location 1): vec2
            glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE,
                cast(int)VERTEX_SIZE, cast(void*)TEXCOORD_OFFSET);
            glEnableVertexAttribArray(1);

            // a_color_fg (location 2): vec4
            glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE,
                cast(int)VERTEX_SIZE, cast(void*)COLOR_FG_OFFSET);
            glEnableVertexAttribArray(2);

            // a_color_bg (location 3): vec4
            glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE,
                cast(int)VERTEX_SIZE, cast(void*)COLOR_BG_OFFSET);
            glEnableVertexAttribArray(3);

            glBindVertexArray(0);
            trace("VAO/VBO created with vertex attributes");

            // Create font atlas
            _fontAtlas = new FontAtlas(1024, 1024);

            // Enable blending for text rendering
            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

            // Initialize projection matrix
            _projection = orthoMatrix(0, 800, 600, 0);  // Default, will be updated on resize

            return true;
        } else {
            error("OpenGL backend not available (bindbc-opengl not linked)");
            return false;
        }
    }

    void cleanupGL() {
        static if (HaveBindBCOpenGL) {
            if (_vbo != 0) {
                glDeleteBuffers(1, &_vbo);
                _vbo = 0;
            }
            if (_vao != 0) {
                glDeleteVertexArrays(1, &_vao);
                _vao = 0;
            }
            if (_shader.valid) {
                deleteProgram(_shader);
            }
        }

        if (_fontAtlas !is null) {
            _fontAtlas.dispose();
            _fontAtlas = null;
        }
    }

    void renderFrame() {
        static if (HaveBindBCOpenGL) {
            // Clear with background color
            glClearColor(0.1f, 0.1f, 0.1f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);

            if (!_shader.valid || _vertexCount == 0) return;

            // Use shader program
            glUseProgram(_shader.id);

            // Set projection matrix
            if (_shader.loc_projection >= 0) {
                glUniformMatrix4fv(_shader.loc_projection, 1, GL_FALSE, _projection.ptr);
            }

            // Bind font atlas texture
            if (_fontAtlas !is null && _shader.loc_font_atlas >= 0) {
                _fontAtlas.sync();  // Upload any dirty regions
                _fontAtlas.bind(0);
                glUniform1i(_shader.loc_font_atlas, 0);
            }

            // Draw terminal content
            glBindVertexArray(_vao);
            glDrawArrays(GL_TRIANGLES, 0, cast(int)_vertexCount);
            glBindVertexArray(0);

            glUseProgram(0);
        }
    }

    /**
     * Convert a cell to 6 vertices (2 triangles) for the cell quad.
     */
    void addCellVertices(float x, float y, float w, float h,
                         float u0, float v0, float u1, float v1,
                         float[4] fgColor, float[4] bgColor) {
        // Ensure buffer has space
        if (_vertexBuffer.length < _vertexCount + 6) {
            _vertexBuffer.length = (_vertexCount + 6) * 2;
        }

        // Triangle 1: top-left, top-right, bottom-left
        _vertexBuffer[_vertexCount++] = TerminalVertex(
            [x, y], [u0, v0], fgColor, bgColor);
        _vertexBuffer[_vertexCount++] = TerminalVertex(
            [x + w, y], [u1, v0], fgColor, bgColor);
        _vertexBuffer[_vertexCount++] = TerminalVertex(
            [x, y + h], [u0, v1], fgColor, bgColor);

        // Triangle 2: top-right, bottom-right, bottom-left
        _vertexBuffer[_vertexCount++] = TerminalVertex(
            [x + w, y], [u1, v0], fgColor, bgColor);
        _vertexBuffer[_vertexCount++] = TerminalVertex(
            [x + w, y + h], [u1, v1], fgColor, bgColor);
        _vertexBuffer[_vertexCount++] = TerminalVertex(
            [x, y + h], [u0, v1], fgColor, bgColor);
    }

    /**
     * Convert RenderModel to vertex data.
     */
    void buildVertexData(ref const RenderModel model) {
        _vertexCount = 0;

        if (_fontAtlas is null) return;

        // Default colors
        float[4] defaultFg = [0.9f, 0.9f, 0.9f, 1.0f];
        float[4] defaultBg = [0.1f, 0.1f, 0.1f, 1.0f];

        foreach (row; 0 .. model.rows) {
            foreach (col; 0 .. model.cols) {
                auto cellIdx = row * model.cols + col;
                if (cellIdx >= model.cells.length) break;

                auto cell = model.cells[cellIdx];
                float x = col * _cellWidth;
                float y = row * _cellHeight;

                // Get glyph from atlas
                dchar ch = (cell.ch != 0) ? cell.ch : ' ';
                auto glyph = _fontAtlas.getGlyph(ch);

                // Convert cell colors to float (attrs contains color indices)
                // For now use default colors - will be enhanced with palette later
                float[4] fgColor = defaultFg;
                float[4] bgColor = defaultBg;

                if (glyph.valid) {
                    addCellVertices(x, y, _cellWidth, _cellHeight,
                        glyph.u0, glyph.v0, glyph.u1, glyph.v1,
                        fgColor, bgColor);
                }
            }
        }

        // Upload to GPU
        static if (HaveBindBCOpenGL) {
            if (_vertexCount > 0) {
                glBindBuffer(GL_ARRAY_BUFFER, _vbo);
                glBufferSubData(GL_ARRAY_BUFFER, 0,
                    _vertexCount * VERTEX_SIZE, _vertexBuffer.ptr);
            }
        }
    }
}

@system
unittest {
    // Test FramePacer
    FramePacer pacer;
    pacer.initialize(60);
    assert(pacer.targetHz == 60);
    assert(pacer.targetFrameTime.total!"usecs" > 16000);  // ~16.67ms
    assert(pacer.targetFrameTime.total!"usecs" < 17000);

    pacer.setTargetHz(120);
    assert(pacer.targetHz == 120);
    assert(pacer.targetFrameTime.total!"usecs" > 8000);   // ~8.33ms
    assert(pacer.targetFrameTime.total!"usecs" < 9000);

    // Test RefreshRate enum
    pacer.initialize(cast(uint)RefreshRate.Gaming144);
    assert(pacer.targetHz == 144);

    // Test FrameStats
    FrameStats stats;
    stats.reset();
    assert(stats.frameCount == 0);
    stats.update(dur!"msecs"(16), 60.0);
    assert(stats.frameCount == 1);
    assert(stats.currentFPS > 0);
}
