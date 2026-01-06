/**
 * Pure D Terminal Backend
 *
 * This module provides a high-performance terminal emulator backend using:
 * - bindbc-glfw for window management and input
 * - bindbc-opengl (GL 4.5) for hardware-accelerated rendering
 * - arsd.terminalemulator for VT sequence parsing
 * - mir-algorithm for SIMD-optimized data structures
 * - intel-intrinsics for AVX2 vectorization
 *
 * Target: 320Hz+ framerate, <1ms input latency, >200 MB/s UTF-8 throughput
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured;

// Core modules
public import pured.window;
public import pured.context;
public import pured.pty;
public import pured.emulator;
public import pured.fontatlas;
public import pured.renderer;

// Platform modules
public import pured.platform.input;

// Terminal modules
public import pured.terminal.selection;
public import pured.terminal.scrollback;

// Widget system
public import pured.widget;

// Utilities
public import pured.util;

version (PURE_D_BACKEND) {
    // Pure D backend enabled - use GLFW/OpenGL rendering
    enum bool isPureDBackend = true;
} else {
    // Default VTE3/GTK backend
    enum bool isPureDBackend = false;
}
