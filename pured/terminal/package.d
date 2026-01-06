/**
 * Terminal emulation components.
 *
 * Provides text selection, scrollback management, and related functionality.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.terminal;

version (PURE_D_BACKEND):

public import pured.terminal.selection;
public import pured.terminal.scrollback;
