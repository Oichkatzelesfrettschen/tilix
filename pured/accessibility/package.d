/**
 * Accessibility Package
 *
 * Provides accessibility features for terminal emulator:
 * - Text extraction for screen readers
 * - Announcement notifications
 * - Role information
 *
 * Future: AT-SPI/D-Bus integration for full accessibility support.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.accessibility;

version (PURE_D_BACKEND):

public import pured.accessibility.text;
public import pured.accessibility.announcer;
