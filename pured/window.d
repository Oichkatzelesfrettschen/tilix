/**
 * GLFW Window Management
 *
 * Provides a D wrapper around GLFW for window creation, input handling,
 * and event processing. Replaces GTK window management for the Pure D backend.
 *
 * Key features:
 * - Window creation with OpenGL 4.5 context
 * - Keyboard input mapping to terminal escape sequences
 * - Mouse event handling (click, scroll, motion)
 * - High refresh rate support (320Hz+)
 * - VSync bypass for minimal input latency
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.window;

version (PURE_D_BACKEND):

import bindbc.glfw;
import bindbc.opengl;
import std.string : toStringz, fromStringz;
import std.stdio : stderr, writefln;

/**
 * GLFW window wrapper for terminal rendering.
 *
 * Manages window lifecycle, input events, and OpenGL context.
 */
class GLFWWindow {
private:
    GLFWwindow* _handle;
    int _width;
    int _height;
    bool _shouldClose;

    // Callbacks
    void delegate(int, int) _resizeCallback;
    void delegate(int, int, int, int) _keyCallback;
    void delegate(uint) _charCallback;
    void delegate(int, int, int) _mouseButtonCallback;
    void delegate(double, double) _scrollCallback;
    void delegate(double, double) _cursorPosCallback;

public:
    /**
     * Initialize GLFW and create window with OpenGL 4.5 context.
     *
     * Params:
     *   width = Initial window width in pixels
     *   height = Initial window height in pixels
     *   title = Window title string
     *
     * Returns: true if initialization succeeded, false otherwise
     */
    bool initialize(int width, int height, string title) {
        _width = width;
        _height = height;

        // Initialize GLFW (statically linked, no dynamic loading needed)
        if (!glfwInit()) {
            stderr.writefln("Error: Failed to initialize GLFW");
            return false;
        }

        // Request OpenGL 4.5 Core Profile
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 5);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
        glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, true);

        // Window hints for terminal rendering
        glfwWindowHint(GLFW_RESIZABLE, true);
        glfwWindowHint(GLFW_DOUBLEBUFFER, true);

        // Create window
        _handle = glfwCreateWindow(width, height, title.toStringz, null, null);
        if (_handle is null) {
            stderr.writefln("Error: Failed to create GLFW window");
            glfwTerminate();
            return false;
        }

        // Make context current
        glfwMakeContextCurrent(_handle);

        // Load OpenGL functions
        auto glRet = loadOpenGL();
        if (glRet == GLSupport.noLibrary) {
            stderr.writefln("Error: Failed to load OpenGL library");
            return false;
        }
        if (glRet == GLSupport.badLibrary) {
            stderr.writefln("Warning: OpenGL library has missing symbols");
        }

        // Disable VSync for maximum framerate (320Hz+ target)
        glfwSwapInterval(0);

        // Set up callbacks
        glfwSetWindowUserPointer(_handle, cast(void*)this);
        glfwSetFramebufferSizeCallback(_handle, &framebufferSizeCallbackStatic);
        glfwSetKeyCallback(_handle, &keyCallbackStatic);
        glfwSetCharCallback(_handle, &charCallbackStatic);
        glfwSetMouseButtonCallback(_handle, &mouseButtonCallbackStatic);
        glfwSetScrollCallback(_handle, &scrollCallbackStatic);
        glfwSetCursorPosCallback(_handle, &cursorPosCallbackStatic);

        return true;
    }

    /**
     * Cleanup and destroy window.
     */
    void terminate() {
        if (_handle !is null) {
            glfwDestroyWindow(_handle);
            _handle = null;
        }
        glfwTerminate();
    }

    /**
     * Check if window should close.
     */
    @property bool shouldClose() const {
        return _shouldClose || glfwWindowShouldClose(cast(GLFWwindow*)_handle);
    }

    /**
     * Request window close.
     */
    void close() {
        _shouldClose = true;
    }

    /**
     * Poll for events (non-blocking).
     */
    void pollEvents() {
        glfwPollEvents();
    }

    /**
     * Swap front and back buffers.
     */
    void swapBuffers() {
        glfwSwapBuffers(_handle);
    }

    /**
     * Make this window's OpenGL context current.
     */
    void makeContextCurrent() {
        glfwMakeContextCurrent(_handle);
    }

    /**
     * Get current window size.
     */
    void getSize(out int width, out int height) {
        glfwGetWindowSize(_handle, &width, &height);
    }

    /**
     * Get framebuffer size (may differ from window size on HiDPI).
     */
    void getFramebufferSize(out int width, out int height) {
        glfwGetFramebufferSize(_handle, &width, &height);
    }

    /**
     * Set window title.
     */
    void setTitle(string title) {
        glfwSetWindowTitle(_handle, title.toStringz);
    }

    /**
     * Get high-precision timer value.
     */
    static double getTime() {
        return glfwGetTime();
    }

    // Callback setters
    void onResize(void delegate(int, int) callback) {
        _resizeCallback = callback;
    }

    void onKey(void delegate(int, int, int, int) callback) {
        _keyCallback = callback;
    }

    void onChar(void delegate(uint) callback) {
        _charCallback = callback;
    }

    void onMouseButton(void delegate(int, int, int) callback) {
        _mouseButtonCallback = callback;
    }

    void onScroll(void delegate(double, double) callback) {
        _scrollCallback = callback;
    }

    void onCursorPos(void delegate(double, double) callback) {
        _cursorPosCallback = callback;
    }

private:
    // Static callbacks that forward to instance methods
    extern(C) static void framebufferSizeCallbackStatic(GLFWwindow* window, int width, int height) nothrow {
        try {
            auto self = cast(GLFWWindow)glfwGetWindowUserPointer(window);
            if (self !is null && self._resizeCallback !is null) {
                self._resizeCallback(width, height);
            }
        } catch (Exception) {}
    }

    extern(C) static void keyCallbackStatic(GLFWwindow* window, int key, int scancode, int action, int mods) nothrow {
        try {
            auto self = cast(GLFWWindow)glfwGetWindowUserPointer(window);
            if (self !is null && self._keyCallback !is null) {
                self._keyCallback(key, scancode, action, mods);
            }
        } catch (Exception) {}
    }

    extern(C) static void charCallbackStatic(GLFWwindow* window, uint codepoint) nothrow {
        try {
            auto self = cast(GLFWWindow)glfwGetWindowUserPointer(window);
            if (self !is null && self._charCallback !is null) {
                self._charCallback(codepoint);
            }
        } catch (Exception) {}
    }

    extern(C) static void mouseButtonCallbackStatic(GLFWwindow* window, int button, int action, int mods) nothrow {
        try {
            auto self = cast(GLFWWindow)glfwGetWindowUserPointer(window);
            if (self !is null && self._mouseButtonCallback !is null) {
                self._mouseButtonCallback(button, action, mods);
            }
        } catch (Exception) {}
    }

    extern(C) static void scrollCallbackStatic(GLFWwindow* window, double xoffset, double yoffset) nothrow {
        try {
            auto self = cast(GLFWWindow)glfwGetWindowUserPointer(window);
            if (self !is null && self._scrollCallback !is null) {
                self._scrollCallback(xoffset, yoffset);
            }
        } catch (Exception) {}
    }

    extern(C) static void cursorPosCallbackStatic(GLFWwindow* window, double xpos, double ypos) nothrow {
        try {
            auto self = cast(GLFWWindow)glfwGetWindowUserPointer(window);
            if (self !is null && self._cursorPosCallback !is null) {
                self._cursorPosCallback(xpos, ypos);
            }
        } catch (Exception) {}
    }
}

/**
 * GLFW key code to terminal escape sequence mapping.
 *
 * Maps GLFW key events to VT100/ANSI escape sequences for terminal input.
 */
string keyToEscapeSequence(int key, int mods) {
    // Modifier flags
    immutable bool ctrl = (mods & GLFW_MOD_CONTROL) != 0;
    immutable bool shift = (mods & GLFW_MOD_SHIFT) != 0;
    immutable bool alt = (mods & GLFW_MOD_ALT) != 0;

    // Arrow keys
    switch (key) {
        case GLFW_KEY_UP:    return "\x1b[A";
        case GLFW_KEY_DOWN:  return "\x1b[B";
        case GLFW_KEY_RIGHT: return "\x1b[C";
        case GLFW_KEY_LEFT:  return "\x1b[D";
        case GLFW_KEY_HOME:  return "\x1b[H";
        case GLFW_KEY_END:   return "\x1b[F";
        case GLFW_KEY_INSERT: return "\x1b[2~";
        case GLFW_KEY_DELETE: return "\x1b[3~";
        case GLFW_KEY_PAGE_UP: return "\x1b[5~";
        case GLFW_KEY_PAGE_DOWN: return "\x1b[6~";

        // Function keys
        case GLFW_KEY_F1:  return "\x1bOP";
        case GLFW_KEY_F2:  return "\x1bOQ";
        case GLFW_KEY_F3:  return "\x1bOR";
        case GLFW_KEY_F4:  return "\x1bOS";
        case GLFW_KEY_F5:  return "\x1b[15~";
        case GLFW_KEY_F6:  return "\x1b[17~";
        case GLFW_KEY_F7:  return "\x1b[18~";
        case GLFW_KEY_F8:  return "\x1b[19~";
        case GLFW_KEY_F9:  return "\x1b[20~";
        case GLFW_KEY_F10: return "\x1b[21~";
        case GLFW_KEY_F11: return "\x1b[23~";
        case GLFW_KEY_F12: return "\x1b[24~";

        // Control characters
        case GLFW_KEY_ENTER:     return ctrl ? "\x1b[13;5u" : "\r";
        case GLFW_KEY_TAB:       return shift ? "\x1b[Z" : "\t";
        case GLFW_KEY_BACKSPACE: return ctrl ? "\x7f" : "\x08";
        case GLFW_KEY_ESCAPE:    return "\x1b";

        default:
            return null;
    }
}
