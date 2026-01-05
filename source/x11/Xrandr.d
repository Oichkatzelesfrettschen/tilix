/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 *
 * D bindings for XRandR extension (libXrandr).
 * Used for detecting native monitor refresh rates.
 */
module x11.Xrandr;

import core.stdc.config;
import x11.X;
import x11.Xlib;

extern (C) nothrow:

// RandR types
alias c_ulong RROutput;
alias c_ulong RRCrtc;
alias c_ulong RRMode;

// Connection status
enum RRConnected = 0;
enum RRDisconnected = 1;
enum RRUnknownConnection = 2;

// Rotation/reflection flags
enum RR_Rotate_0 = 1;
enum RR_Rotate_90 = 2;
enum RR_Rotate_180 = 4;
enum RR_Rotate_270 = 8;
enum RR_Reflect_X = 16;
enum RR_Reflect_Y = 32;

/**
 * Mode information structure.
 * Contains timing data to calculate refresh rate:
 *   refreshRate = dotClock / (hTotal * vTotal)
 */
struct XRRModeInfo {
    RRMode id;
    uint width;
    uint height;
    c_ulong dotClock;       // Pixel clock in Hz
    uint hSyncStart;
    uint hSyncEnd;
    uint hTotal;
    uint hSkew;
    uint vSyncStart;
    uint vSyncEnd;
    uint vTotal;
    char* name;
    uint nameLength;
    c_ulong modeFlags;
}

/**
 * Screen resources structure.
 * Contains arrays of CRTCs, outputs, and modes.
 */
struct XRRScreenResources {
    Time timestamp;
    Time configTimestamp;
    int ncrtc;
    RRCrtc* crtcs;
    int noutput;
    RROutput* outputs;
    int nmode;
    XRRModeInfo* modes;
}

/**
 * CRTC information structure.
 * Represents an active display output configuration.
 */
struct XRRCrtcInfo {
    Time timestamp;
    int x;
    int y;
    uint width;
    uint height;
    RRMode mode;            // Currently active mode ID
    ushort rotation;
    int noutput;
    RROutput* outputs;
    ushort rotations;
    int npossible;
    RROutput* possible;
}

/**
 * Output information structure.
 * Represents a physical display connector.
 */
struct XRROutputInfo {
    Time timestamp;
    RRCrtc crtc;            // Currently connected CRTC
    char* name;
    int nameLen;
    c_ulong mm_width;
    c_ulong mm_height;
    ushort connection;      // RRConnected, RRDisconnected, RRUnknownConnection
    ushort subpixel_order;
    int ncrtc;
    RRCrtc* crtcs;
    int nclone;
    RROutput* clones;
    int nmode;
    int npreferred;
    RRMode* modes;
}

// Function declarations

/// Query XRandR extension presence and base event/error codes
Bool XRRQueryExtension(Display* dpy, int* event_base_return, int* error_base_return);

/// Query XRandR version
Status XRRQueryVersion(Display* dpy, int* major_version_return, int* minor_version_return);

/// Get screen resources (modes, CRTCs, outputs)
XRRScreenResources* XRRGetScreenResources(Display* dpy, Window window);

/// Get screen resources (cached version, faster)
XRRScreenResources* XRRGetScreenResourcesCurrent(Display* dpy, Window window);

/// Free screen resources
void XRRFreeScreenResources(XRRScreenResources* resources);

/// Get CRTC information
XRRCrtcInfo* XRRGetCrtcInfo(Display* dpy, XRRScreenResources* resources, RRCrtc crtc);

/// Free CRTC info
void XRRFreeCrtcInfo(XRRCrtcInfo* crtcInfo);

/// Get output information
XRROutputInfo* XRRGetOutputInfo(Display* dpy, XRRScreenResources* resources, RROutput output);

/// Free output info
void XRRFreeOutputInfo(XRROutputInfo* outputInfo);

/**
 * Calculate refresh rate in Hz from XRRModeInfo.
 * Formula: refreshRate = dotClock / (hTotal * vTotal)
 * Returns 0 if timing data is invalid.
 */
double calculateRefreshRate(const XRRModeInfo* mode) {
    if (mode is null || mode.hTotal == 0 || mode.vTotal == 0) {
        return 0.0;
    }
    return cast(double)mode.dotClock / (cast(double)mode.hTotal * cast(double)mode.vTotal);
}

@system unittest {
    // Test refresh rate calculation
    XRRModeInfo mode;
    mode.dotClock = 148_500_000;  // 148.5 MHz (typical for 1080p60)
    mode.hTotal = 2200;
    mode.vTotal = 1125;
    auto hz = calculateRefreshRate(&mode);
    assert(hz > 59.9 && hz < 60.1);  // Should be ~60 Hz
}
