/**
 * AT-SPI Module - Accessibility Service Provider Interface
 *
 * Public API for AT-SPI accessibility framework.
 */
module pured.accessibility.atspi;

version (PURE_D_BACKEND):

public import pured.accessibility.atspi.types;
public import pured.accessibility.atspi.interfaces;
public import pured.accessibility.atspi.provider;
public import pured.accessibility.atspi.events;
public import pured.accessibility.atspi.testing;
