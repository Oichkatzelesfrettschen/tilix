module pured.platform.clipboard;

version (PURE_D_BACKEND):

import bindbc.glfw;
import core.sync.condition : Condition;
import core.sync.mutex : Mutex;
import std.string : fromStringz, toStringz;

static if (glfwSupport >= GLFWSupport.glfw33) {
    extern(C) @nogc nothrow {
        void glfwSetX11SelectionString(const(char)* string_);
        const(char)* glfwGetX11SelectionString();
    }
}

/**
 * Thread-safe clipboard bridge for GLFW and X11 PRIMARY selection.
 */
class ClipboardBridge {
private:
    GLFWwindow* _window;
    Mutex _mutex;
    Condition _cond;

    string _pendingClipboardText;
    string _pendingPrimaryText;
    bool _pendingClipboardSet;
    bool _pendingPrimarySet;

    bool _clipboardRequest;
    bool _primaryRequest;
    bool _clipboardReady;
    bool _primaryReady;
    string _clipboardText;
    string _primaryText;

public:
    this(GLFWwindow* window) {
        _window = window;
        _mutex = new Mutex();
        _cond = new Condition(_mutex);
    }

    void setClipboard(string text) {
        _mutex.lock();
        scope(exit) _mutex.unlock();
        _pendingClipboardText = text.idup;
        _pendingClipboardSet = true;
        _cond.notifyAll();
    }

    void setPrimary(string text) {
        _mutex.lock();
        scope(exit) _mutex.unlock();
        _pendingPrimaryText = text.idup;
        _pendingPrimarySet = true;
        _cond.notifyAll();
    }

    string requestClipboard() {
        return request(false);
    }

    string requestPrimary() {
        return request(true);
    }

    void pump() {
        string clipboardSet;
        string primarySet;
        bool clipboardReq;
        bool primaryReq;

        _mutex.lock();
        if (_pendingClipboardSet) {
            clipboardSet = _pendingClipboardText;
            _pendingClipboardSet = false;
        }
        if (_pendingPrimarySet) {
            primarySet = _pendingPrimaryText;
            _pendingPrimarySet = false;
        }

        clipboardReq = _clipboardRequest;
        primaryReq = _primaryRequest;
        _mutex.unlock();

        if (_window !is null) {
            if (clipboardSet.length) {
                glfwSetClipboardString(_window, clipboardSet.toStringz);
            }
        }

        static if (glfwSupport >= GLFWSupport.glfw33) {
            if (primarySet.length) {
                glfwSetX11SelectionString(primarySet.toStringz);
            }
        } else {
            if (primarySet.length && _window !is null) {
                glfwSetClipboardString(_window, primarySet.toStringz);
            }
        }

        string clipboardValue;
        string primaryValue;
        if (clipboardReq && _window !is null) {
            auto cstr = glfwGetClipboardString(_window);
            clipboardValue = cstr is null ? "" : fromStringz(cstr).idup;
        }
        static if (glfwSupport >= GLFWSupport.glfw33) {
            if (primaryReq) {
                auto pstr = glfwGetX11SelectionString();
                if (pstr is null && _window !is null) {
                    auto cstr = glfwGetClipboardString(_window);
                    primaryValue = cstr is null ? "" : fromStringz(cstr).idup;
                } else {
                    primaryValue = pstr is null ? "" : fromStringz(pstr).idup;
                }
            }
        } else {
            if (primaryReq) {
                if (_window !is null) {
                    auto cstr = glfwGetClipboardString(_window);
                    primaryValue = cstr is null ? "" : fromStringz(cstr).idup;
                } else {
                    primaryValue = "";
                }
            }
        }

        _mutex.lock();
        if (clipboardReq) {
            _clipboardText = clipboardValue;
            _clipboardReady = true;
            _clipboardRequest = false;
        }
        if (primaryReq) {
            _primaryText = primaryValue;
            _primaryReady = true;
            _primaryRequest = false;
        }
        if (clipboardReq || primaryReq) {
            _cond.notifyAll();
        }
        _mutex.unlock();
    }

private:
    string request(bool primary) {
        _mutex.lock();
        scope(exit) _mutex.unlock();

        if (primary) {
            _primaryRequest = true;
            _primaryReady = false;
        } else {
            _clipboardRequest = true;
            _clipboardReady = false;
        }
        _cond.notifyAll();

        while (primary ? !_primaryReady : !_clipboardReady) {
            _cond.wait();
        }

        return primary ? _primaryText : _clipboardText;
    }
}
