/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.backend.vte3;

import std.experimental.logger;

import gtk.Widget;

import gx.tilix.backend.render;

/**
 * VTE3 render backend.
 *
 * This backend wraps VTE's native Cairo-based rendering.
 * It provides a consistent interface but delegates all actual rendering to VTE.
 *
 * Limitations:
 * - 40 FPS cap due to VTE's frame clock implementation
 * - No GPU acceleration (Cairo is CPU-based)
 * - Cannot access cell buffer directly for custom effects
 *
 * This backend is the default fallback when OpenGL is unavailable.
 */
class VTE3RenderBackend : IRenderBackend {
private:
    Widget _container;
    bool _initialized;
    uint _cols;
    uint _rows;

    enum MAX_FPS = 40;  // VTE3 hardcoded limit

public:
    /**
     * Initialize the VTE3 backend.
     * For VTE3, the container is expected to already contain a VTE Terminal widget.
     * This backend doesn't create its own widgets; it just marks itself ready.
     */
    override void initialize(Widget container) {
        _container = container;
        _initialized = true;
        trace("VTE3RenderBackend initialized");
    }

    /**
     * Prepare frame for rendering.
     * VTE manages its own rendering, so this is essentially a no-op.
     * The model is accepted for API consistency with other backends.
     */
    override void prepareFrame(ref const RenderModel model) {
        // VTE handles its own buffer management
        // This method exists for API consistency with OpenGL backend
    }

    /**
     * Present the frame.
     * For VTE3, this triggers a widget redraw via GTK's standard mechanism.
     */
    override void present() {
        if (_container !is null) {
            _container.queueDraw();
        }
    }

    /**
     * Handle terminal resize.
     * VTE handles resize internally; we just track dimensions for the model.
     */
    override void resize(uint cols, uint rows) {
        _cols = cols;
        _rows = rows;
    }

    /**
     * Get VTE3 backend capabilities.
     */
    override @property RenderCapabilities capabilities() const {
        return RenderCapabilities(
            false,      // supportsGPU
            false,      // supportsHighRefresh
            MAX_FPS,    // maxFPS
            "VTE3"      // name
        );
    }

    /**
     * Check if backend is ready.
     */
    override @property bool isReady() const {
        return _initialized;
    }

    /**
     * Clean up resources.
     * VTE3 backend doesn't own any resources that need explicit cleanup.
     */
    override void dispose() {
        _container = null;
        _initialized = false;
        trace("VTE3RenderBackend disposed");
    }
}

@system
unittest {
    auto backend = new VTE3RenderBackend();

    // Test initial state
    assert(!backend.isReady);
    assert(backend.capabilities.name == "VTE3");
    assert(backend.capabilities.maxFPS == 40);
    assert(!backend.capabilities.supportsGPU);
    assert(!backend.capabilities.supportsHighRefresh);

    // Test dispose
    backend.dispose();
    assert(!backend.isReady);
}
