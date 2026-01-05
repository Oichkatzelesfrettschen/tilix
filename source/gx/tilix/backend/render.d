/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.backend.render;

import std.experimental.logger;
import std.process : environment;

import gdk.RGBA;
import gtk.Widget;

/**
 * Cell attributes for terminal rendering.
 */
struct CellAttrs {
    RGBA fg;
    RGBA bg;
    bool bold;
    bool italic;
    bool underline;
    bool strikethrough;
    bool inverse;
    bool blink;
}

/**
 * Cursor style for rendering.
 */
enum CursorStyle {
    Block,
    Beam,
    Underline
}

/**
 * Cursor state for rendering.
 */
struct CursorState {
    uint col;
    uint row;
    CursorStyle style;
    bool visible;
    bool blinkOn;
}

/**
 * Terminal cell data for GPU rendering.
 * Contains the character and its attributes.
 */
struct Cell {
    dchar ch;          // Unicode codepoint (0 = empty/space)
    CellAttrs attrs;   // Foreground, background, bold, etc.
}

/**
 * Render model representing terminal state to be drawn.
 * For VTE3Backend, this is mostly informational since VTE handles rendering.
 * For OpenGLRenderBackend, this provides the full cell grid for GPU rendering.
 */
struct RenderModel {
    uint cols;
    uint rows;
    CursorState cursor;
    RGBA[16] palette;
    RGBA defaultFg;
    RGBA defaultBg;
    Cell[] cells;  // Cell grid data for GPU rendering (cols * rows)
}

/**
 * Render backend capabilities.
 */
struct RenderCapabilities {
    bool supportsGPU;
    bool supportsHighRefresh;
    uint maxFPS;
    string name;
}

/**
 * Backend type enumeration.
 */
enum RenderBackendType {
    VTE3,
    OpenGL,
    Auto
}

/**
 * Interface for render backends.
 * Abstracts terminal rendering to support multiple implementations:
 * - VTE3RenderBackend: Uses VTE's native Cairo rendering (40 FPS cap)
 * - OpenGLRenderBackend: Custom GPU rendering via GtkGLArea (high refresh)
 */
interface IRenderBackend {
    /**
     * Initialize the backend with a container widget.
     * The backend may add child widgets or set up rendering contexts.
     */
    void initialize(Widget container);

    /**
     * Prepare a frame for rendering.
     * For VTE3, this is a no-op since VTE manages its own rendering.
     * For OpenGL, this uploads cell data to GPU buffers.
     */
    void prepareFrame(ref const RenderModel model);

    /**
     * Present the frame to the display.
     * For VTE3, this calls queue_draw on the VTE widget.
     * For OpenGL, this swaps buffers and handles VSync.
     */
    void present();

    /**
     * Handle terminal resize.
     */
    void resize(uint cols, uint rows);

    /**
     * Get backend capabilities.
     */
    @property RenderCapabilities capabilities() const;

    /**
     * Check if backend is ready for rendering.
     */
    @property bool isReady() const;

    /**
     * Clean up resources.
     */
    void dispose();
}

/**
 * Get the configured render backend type.
 * Checks TILIX_RENDERER environment variable first, then falls back to Auto.
 */
RenderBackendType getConfiguredBackendType() {
    string envRenderer = environment.get("TILIX_RENDERER", "auto");

    switch (envRenderer) {
        case "vte3":
        case "vte":
            return RenderBackendType.VTE3;
        case "opengl":
        case "gl":
            return RenderBackendType.OpenGL;
        default:
            return RenderBackendType.Auto;
    }
}

/**
 * Create a render backend based on configuration and capabilities.
 */
IRenderBackend createRenderBackend(RenderBackendType type = RenderBackendType.Auto) {
    import gx.tilix.backend.vte3 : VTE3RenderBackend;
    import gx.tilix.backend.opengl : OpenGLRenderBackend;

    final switch (type) {
        case RenderBackendType.VTE3:
            return new VTE3RenderBackend();

        case RenderBackendType.OpenGL:
            try {
                auto gl = new OpenGLRenderBackend();
                trace("Created OpenGL render backend");
                return gl;
            } catch (Exception e) {
                tracef("OpenGL backend failed: %s, falling back to VTE3", e.msg);
                return new VTE3RenderBackend();
            }

        case RenderBackendType.Auto:
            // Auto-detect: try OpenGL first, fall back to VTE3
            try {
                auto gl = new OpenGLRenderBackend();
                trace("Auto-selected OpenGL render backend");
                return gl;
            } catch (Exception e) {
                tracef("Auto-detect: OpenGL unavailable (%s), using VTE3", e.msg);
                return new VTE3RenderBackend();
            }
    }
}
