module pured.platform.input_types;

version (PURE_D_BACKEND):

import bindbc.glfw;

enum MouseMode {
    none = 0,
    x10 = 9,
    normal = 1000,
    highlight = 1001,
    buttonEvent = 1002,
    anyEvent = 1003,
}

enum MouseEncoding {
    x10 = 0,
    utf8 = 1005,
    sgr = 1006,
    urxvt = 1015,
}
