/**
 * Wayland Data Device Package
 *
 * System clipboard support via wl_data_device protocol.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.platform.wayland.data_device;

version (PURE_D_BACKEND):

public import pured.platform.wayland.data_device.bridge;
