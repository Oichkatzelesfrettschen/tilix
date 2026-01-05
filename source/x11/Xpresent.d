/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 *
 * D bindings for X Present extension (libXpresent).
 * Provides hardware VSync and MSC-based frame timing for tear-free rendering.
 */
module x11.Xpresent;

import core.stdc.config;
import x11.X;
import x11.Xlib;

extern (C) nothrow:

// Present extension types
alias c_ulong XSyncFence;
alias c_ulong XserverRegion;

// Present capability flags
enum PresentCapabilityNone = 0;
enum PresentCapabilityAsync = 1;
enum PresentCapabilityFence = 2;
enum PresentCapabilityUST = 4;

// Present option flags (for XPresentPixmap)
enum PresentOptionNone = 0;
enum PresentOptionAsync = 1;
enum PresentOptionCopy = 2;
enum PresentOptionUST = 4;

// Present event mask
enum PresentConfigureNotifyMask = 1;
enum PresentCompleteNotifyMask = 2;
enum PresentIdleNotifyMask = 4;
enum PresentAllEvents = (PresentConfigureNotifyMask |
                         PresentCompleteNotifyMask |
                         PresentIdleNotifyMask);

// Present complete kind
enum PresentCompleteKindPixmap = 0;
enum PresentCompleteKindNotifyMsc = 1;

// Present complete mode
enum PresentCompleteModeFlip = 0;
enum PresentCompleteModeCopy = 1;
enum PresentCompleteModeSkip = 2;
enum PresentCompleteModeSuboptimalCopy = 3;

/**
 * Present complete notify event structure.
 * Delivered when a presented pixmap is displayed or presentation is complete.
 */
struct XPresentCompleteNotifyEvent {
    int type;                   // GenericEvent
    c_ulong serial;
    Bool send_event;
    Display* display;
    int extension;
    int evtype;
    uint eid;                   // Event ID
    Window window;
    uint serial_number;         // Serial number from XPresentPixmap
    ulong ust;                  // Presentation timestamp (microseconds)
    ulong msc;                  // Media stream counter at presentation
    ubyte kind;                 // PresentCompleteKind*
    ubyte mode;                 // PresentCompleteMode*
}

/**
 * Present idle notify event structure.
 * Delivered when a pixmap is no longer in use and can be reused.
 */
struct XPresentIdleNotifyEvent {
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    int extension;
    int evtype;
    uint eid;
    Window window;
    uint serial_number;
    Pixmap pixmap;
    XSyncFence idle_fence;
}

/**
 * Present configure notify event structure.
 * Delivered when the window configuration changes.
 */
struct XPresentConfigureNotifyEvent {
    int type;
    c_ulong serial;
    Bool send_event;
    Display* display;
    int extension;
    int evtype;
    uint eid;
    Window window;
    int x;
    int y;
    uint width;
    uint height;
    int off_x;
    int off_y;
    uint pixmap_width;
    uint pixmap_height;
    c_ulong pixmap_flags;
}

// Function declarations

/// Query Present extension presence and opcodes
Bool XPresentQueryExtension(Display* dpy, int* major_opcode_return,
                            int* event_base_return, int* error_base_return);

/// Query Present extension version
Status XPresentQueryVersion(Display* dpy, int* major_version_return,
                            int* minor_version_return);

/// Query capabilities for a CRTC
int XPresentQueryCapabilities(Display* dpy, XID target);

/**
 * Present a pixmap to the screen.
 *
 * Params:
 *   dpy = Display connection
 *   window = Target window
 *   pixmap = Source pixmap to present
 *   serial = Client-assigned serial number for tracking
 *   valid = Region of pixmap that is valid (None = all)
 *   update = Region to update (None = all)
 *   x_off = X offset for pixmap within window
 *   y_off = Y offset for pixmap within window
 *   target_crtc = CRTC for timing (None = any)
 *   wait_fence = Fence to wait on before presentation (None = immediate)
 *   idle_fence = Fence to signal when pixmap is idle (None = no fence)
 *   options = PresentOption* flags
 *   target_msc = Target media stream counter (0 = next vsync)
 *   divisor = MSC divisor for timing
 *   remainder = MSC remainder for timing
 *   notifies = Array of notify structures (null = none)
 *   nnotifies = Number of notify structures
 */
void XPresentPixmap(Display* dpy, Window window, Pixmap pixmap,
                    uint serial, XserverRegion valid, XserverRegion update,
                    int x_off, int y_off, c_ulong target_crtc,
                    XSyncFence wait_fence, XSyncFence idle_fence,
                    uint options, ulong target_msc,
                    ulong divisor, ulong remainder,
                    void* notifies, int nnotifies);

/**
 * Notify at a specific MSC.
 * Sends a PresentCompleteNotify with kind=PresentCompleteKindNotifyMsc.
 */
void XPresentNotifyMSC(Display* dpy, Window window, uint serial,
                       ulong target_msc, ulong divisor, ulong remainder);

/// Select which Present events to receive
void XPresentSelectInput(Display* dpy, Window window, uint event_mask);

/**
 * Free a Present event ID.
 * Event IDs are allocated by XPresentSelectInput.
 */
void XPresentFreeInput(Display* dpy, Window window, uint event_id);

/**
 * Simple wrapper for presenting with vsync.
 * Equivalent to XPresentPixmap with target_msc=0, divisor=1, remainder=0.
 */
void presentPixmapVSync(Display* dpy, Window window, Pixmap pixmap, uint serial) {
    XPresentPixmap(dpy, window, pixmap, serial,
                   cast(XserverRegion)0, cast(XserverRegion)0,  // valid, update = all
                   0, 0,                    // no offset
                   0,                       // any CRTC
                   cast(XSyncFence)0,       // no wait fence
                   cast(XSyncFence)0,       // no idle fence
                   PresentOptionNone,       // default options
                   0,                       // target_msc = next vsync
                   1, 0,                    // divisor=1, remainder=0 = every vsync
                   null, 0);                // no notifies
}

@system unittest {
    // Test capability flag composition
    auto caps = PresentCapabilityAsync | PresentCapabilityFence;
    assert(caps & PresentCapabilityAsync);
    assert(caps & PresentCapabilityFence);
    assert(!(caps & PresentCapabilityUST));

    // Test event mask composition
    auto mask = PresentCompleteNotifyMask | PresentIdleNotifyMask;
    assert(mask & PresentCompleteNotifyMask);
    assert(mask & PresentIdleNotifyMask);
}
