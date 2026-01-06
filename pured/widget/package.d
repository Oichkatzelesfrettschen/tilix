/**
 * Widget System Package
 *
 * UI widget hierarchy for Pure D terminal.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget;

version (PURE_D_BACKEND):

public import pured.widget.base;
public import pured.widget.container;
public import pured.widget.events;
public import pured.widget.layout;
public import pured.widget.scrollbar;
public import pured.widget.terminal;
