/**
 * Wayland Fractional Scale Support
 *
 * Implements wp_fractional_scale_v1 protocol for high-DPI displays.
 * Detects when display scale changes (1.5x, 2x, etc.) and notifies
 * the renderer to rescale the font atlas and UI elements.
 *
 * This bridges the gap where GLFW only exposes integer scale factors
 * via glfwGetWindowContentScale() but modern Wayland compositors
 * (GNOME 43+, KDE 5.27+, Sway 1.7+) need sub-pixel scaling.
 */
module pured.platform.wayland.fractional_scale.bridge;

version (PURE_D_BACKEND):

import core.stdc.errno : EAGAIN, errno;
import core.sys.posix.poll : poll, pollfd, POLLIN;
import core.sys.posix.unistd : close;
import std.algorithm : min;
import std.process : environment;
import std.string : fromStringz, toStringz;
import wayland.client.core;
import wayland.client.ifaces;
import wayland.client.opaque_types;
import wayland.client.protocol;
import wayland.client.util;
import pured.platform.wayland.fractional_scale.protocol;
import pured.platform.wayland.fractional_scale.ifaces;

version (Dynamic) {
    import wayland.client.dy_loader : loadWaylandClient;
}

/**
 * Scale change callback signature.
 *
 * Called when the display scale factor changes. The scale is fixed-point
 * with factor of 120 (e.g., 180 = 1.5x, 240 = 2.0x).
 *
 * Params:
 *   scale = Fixed-point scale (120 = 1.0x, 180 = 1.5x, 240 = 2.0x)
 */
alias ScaleChangeCallback = void delegate(uint scale);

/**
 * Wayland fractional scale protocol bridge.
 *
 * Manages wp_fractional_scale_v1 protocol to receive precise DPI scale
 * factors from the compositor. Uses the same lifecycle pattern as other
 * Wayland protocol bridges in the application.
 */
class WaylandFractionalScaleBridge {
private:
    wl_display* _display;
    wl_registry* _registry;
    wl_surface* _surface;
    wp_fractional_scale_manager_v1* _manager;
    wp_fractional_scale_v1* _fractionalScale;
    uint _currentScale; // Fixed-point scale: 120 = 1.0x, 180 = 1.5x, 240 = 2.0x
    bool _available;
    ScaleChangeCallback _scaleChangeCallback;
    bool _scaleChangePending;
    uint _pendingScale;

public:
    this() {
        init();
    }

    ~this() {
        shutdown();
    }

    /**
     * Check if fractional scale protocol is available.
     *
     * Returns true only after both the manager interface and scale object
     * have been successfully created. Returns false if the compositor
     * does not support wp_fractional_scale_v1.
     */
    @property bool available() const {
        return _available && _fractionalScale !is null;
    }

    /**
     * Get the current scale factor as a fixed-point value.
     *
     * Returns:
     *   Fixed-point scale (120 = 1.0x, 180 = 1.5x, 240 = 2.0x)
     *   Returns 120 if protocol not available.
     */
    @property uint currentScale() const {
        return _currentScale > 0 ? _currentScale : 120;
    }

    /**
     * Get the current scale as a floating-point multiplier.
     *
     * Converts the fixed-point scale factor to a float for use in
     * rendering calculations.
     *
     * Returns:
     *   Float scale (1.0 = normal, 1.5 = 150% scale, 2.0 = 200% scale)
     */
    @property float scaleFloat() const {
        return currentScale / 120.0f;
    }

    /**
     * Set the Wayland surface for scale tracking.
     *
     * Must be called with the wl_surface from GLFW after window creation.
     * This creates the fractional scale object for that surface.
     *
     * Params:
     *   surface = The wl_surface* from glfwGetWaylandWindow()
     *
     * Returns: true if scale object was created successfully
     */
    bool setSurface(wl_surface* surface) {
        if (surface is null) {
            return false;
        }

        _surface = surface;

        // Create fractional scale object for this surface
        if (_manager !is null && _surface !is null) {
            _fractionalScale = wp_fractional_scale_manager_v1_get_fractional_scale(_manager, _surface);
            if (_fractionalScale !is null) {
                wp_fractional_scale_v1_add_listener(_fractionalScale, &scaleListener, cast(void*)this);
                wl_display_flush(_display);
                return true;
            }
        }

        return false;
    }

    /**
     * Set callback for scale change events.
     *
     * Called whenever the compositor changes the scale factor. The callback
     * should trigger renderer rescaling of fonts and UI elements.
     *
     * Params:
     *   callback = Function to call on scale changes
     */
    void onScaleChanged(ScaleChangeCallback callback) {
        _scaleChangeCallback = callback;
        // If we already have a scale and haven't called back yet, do it now
        if (_currentScale > 0 && callback !is null) {
            callback(_currentScale);
        }
    }

    /**
     * Process pending Wayland events.
     *
     * Must be called regularly from the main event loop to receive
     * scale change notifications from the compositor. Uses non-blocking
     * poll to avoid stalling the render loop.
     */
    void pump() {
        if (!_available || _display is null) {
            return;
        }

        // Dispatch pending events
        wl_display_dispatch_pending(_display);
        wl_display_flush(_display);

        // Non-blocking poll for new events
        if (wl_display_prepare_read(_display) != 0) {
            if (errno == EAGAIN) {
                wl_display_dispatch_pending(_display);
            }
            return;
        }

        pollfd pfd;
        pfd.fd = wl_display_get_fd(_display);
        pfd.events = POLLIN;
        int ready = poll(&pfd, 1, 0);
        if (ready > 0 && (pfd.revents & POLLIN) != 0) {
            wl_display_read_events(_display);
            wl_display_dispatch_pending(_display);
        } else {
            wl_display_cancel_read(_display);
        }

        // If scale changed during events, call callback now
        if (_scaleChangePending && _scaleChangeCallback !is null) {
            _scaleChangeCallback(_pendingScale);
            _scaleChangePending = false;
        }
    }

private:
    void init() {
        _currentScale = 120; // Default to 1.0x
        _available = false;
        _scaleChangePending = false;

        // Connect to Wayland display
        _display = wl_display_connect(null);
        if (_display is null) {
            return;
        }

        // Get registry
        _registry = wl_display_get_registry(_display);
        if (_registry is null) {
            wl_display_disconnect(_display);
            _display = null;
            return;
        }

        // Listen for global interfaces
        wl_registry_add_listener(_registry, &registryListener, cast(void*)this);

        // Round-trip to receive global announcements
        wl_display_roundtrip(_display);

        // Protocol is available if we found the manager
        _available = (_manager !is null);
    }

    void shutdown() {
        if (_fractionalScale !is null) {
            wp_fractional_scale_v1_destroy(_fractionalScale);
            _fractionalScale = null;
        }

        if (_manager !is null) {
            wp_fractional_scale_manager_v1_destroy(_manager);
            _manager = null;
        }

        if (_registry !is null) {
            wl_registry_destroy(_registry);
            _registry = null;
        }

        if (_display !is null) {
            wl_display_disconnect(_display);
            _display = null;
        }
    }

    void handleRegistryGlobal(wl_registry* registry, uint name, const(char)[] iface, uint ifaceVersion) {
        if (iface == "wp_fractional_scale_manager_v1" && _manager is null) {
            auto managerVersion = min(ifaceVersion, 1u);
            _manager = cast(wp_fractional_scale_manager_v1*)wl_registry_bind(
                registry, name, wp_fractional_scale_manager_v1_interface(), managerVersion);
        }
    }

    void handleScaleChanged(uint scale) {
        if (scale != _currentScale) {
            _currentScale = scale;
            _pendingScale = scale;
            _scaleChangePending = true;
        }
    }

    // ========================================================================
    // Wayland Listeners
    // ========================================================================

    static __gshared wl_registry_listener registryListener = {
        &registryGlobalCallback,
        &registryRemoveCallback
    };

    extern (C) static void registryGlobalCallback(
        void* data, wl_registry* registry, uint name, const(char)* iface, uint version_)
    {
        auto self = cast(WaylandFractionalScaleBridge)data;
        if (self is null)
            return;

        auto ifaceName = fromStringz(iface);
        self.handleRegistryGlobal(registry, name, ifaceName, version_);
    }

    extern (C) static void registryRemoveCallback(void* data, wl_registry* registry, uint name) {
        // We don't need to handle global removals for our use case
    }

    static __gshared wp_fractional_scale_v1_listener scaleListener = {
        &scalePreferredScaleCallback
    };

    extern (C) static void scalePreferredScaleCallback(void* data, wp_fractional_scale_v1* scale, uint preferred_scale) {
        auto self = cast(WaylandFractionalScaleBridge)data;
        if (self is null)
            return;

        self.handleScaleChanged(preferred_scale);
    }
}
