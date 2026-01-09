/**
 * Fractional Scale Protocol Support
 *
 * Provides high-DPI scaling support via wp_fractional_scale_v1.
 */
module pured.platform.wayland.fractional_scale;

version (PURE_D_BACKEND):

public import pured.platform.wayland.fractional_scale.bridge;
