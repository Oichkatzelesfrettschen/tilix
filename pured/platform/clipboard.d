module pured.platform.clipboard;

version (PURE_D_BACKEND):

import bindbc.glfw;
import core.sync.condition : Condition;
import core.sync.mutex : Mutex;
import core.thread : Thread;
import core.stdc.stdlib : free;
import std.string : fromStringz, toStringz;
import xcb.xcb;

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
    Thread _ownerThread;

    xcb_connection_t* _xconn;
    xcb_window_t _xwindow;
    xcb_atom_t _atomPrimary;
    xcb_atom_t _atomTargets;
    xcb_atom_t _atomUtf8;
    xcb_atom_t _atomText;
    xcb_atom_t _atomXselData;
    string _xPrimaryText;
    bool _x11Available;

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
        _ownerThread = Thread.getThis();
        initX11();
    }

    ~this() {
        if (_xconn !is null) {
            xcb_disconnect(_xconn);
            _xconn = null;
        }
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
        pumpX11Events();
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

        string clipboardValue;
        string primaryValue;
        if (primarySet.length) {
            if (_x11Available) {
                setPrimaryX11(primarySet);
            } else static if (glfwSupport >= GLFWSupport.glfw33) {
                glfwSetX11SelectionString(primarySet.toStringz);
            } else if (_window !is null) {
                glfwSetClipboardString(_window, primarySet.toStringz);
            }
        }

        if (clipboardReq) {
            clipboardValue = directRequestClipboard();
        }
        if (primaryReq) {
            primaryValue = directRequestPrimary();
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
        if (onOwnerThread()) {
            return primary ? directRequestPrimary() : directRequestClipboard();
        }
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

    bool onOwnerThread() {
        auto current = Thread.getThis();
        return _ownerThread is null || current is _ownerThread;
    }

    string directRequestClipboard() {
        if (_window is null) {
            return "";
        }
        auto cstr = glfwGetClipboardString(_window);
        return cstr is null ? "" : fromStringz(cstr).idup;
    }

    string directRequestPrimary() {
        if (_x11Available) {
            return requestPrimaryX11();
        }
        static if (glfwSupport >= GLFWSupport.glfw33) {
            auto pstr = glfwGetX11SelectionString();
            if (pstr !is null) {
                return fromStringz(pstr).idup;
            }
        }
        return directRequestClipboard();
    }

    void initX11() {
        _x11Available = false;
        int screenIndex = 0;
        _xconn = xcb_connect(null, &screenIndex);
        if (_xconn is null || xcb_connection_has_error(_xconn) != 0) {
            if (_xconn !is null) {
                xcb_disconnect(_xconn);
                _xconn = null;
            }
            return;
        }
        auto setup = xcb_get_setup(_xconn);
        auto iter = xcb_setup_roots_iterator(setup);
        foreach (i; 0 .. screenIndex) {
            xcb_screen_next(&iter);
        }
        auto screen = iter.data;
        if (screen is null) {
            xcb_disconnect(_xconn);
            _xconn = null;
            return;
        }
        _xwindow = xcb_generate_id(_xconn);
        uint valueMask = XCB_CW_EVENT_MASK;
        uint valueList = XCB_EVENT_MASK_PROPERTY_CHANGE;
        xcb_create_window(_xconn, XCB_COPY_FROM_PARENT, _xwindow, screen.root,
            0, 0, 1, 1, 0, XCB_WINDOW_CLASS_INPUT_OUTPUT,
            screen.root_visual, valueMask, &valueList);
        xcb_map_window(_xconn, _xwindow);
        xcb_flush(_xconn);
        _atomPrimary = internAtom("PRIMARY");
        _atomTargets = internAtom("TARGETS");
        _atomUtf8 = internAtom("UTF8_STRING");
        _atomText = internAtom("TEXT");
        _atomXselData = internAtom("XSEL_DATA");
        _x11Available = _atomPrimary != XCB_ATOM_NONE &&
            _atomXselData != XCB_ATOM_NONE;
    }

    xcb_atom_t internAtom(string name) {
        if (_xconn is null || name.length == 0) {
            return XCB_ATOM_NONE;
        }
        auto cookie = xcb_intern_atom(_xconn, 0, cast(ushort)name.length, name.ptr);
        auto reply = xcb_intern_atom_reply(_xconn, cookie, null);
        if (reply is null) {
            return XCB_ATOM_NONE;
        }
        auto atom = reply.atom;
        free(reply);
        return atom;
    }

    void pumpX11Events() {
        if (!_x11Available || _xconn is null) {
            return;
        }
        xcb_generic_event_t* event;
        while ((event = xcb_poll_for_event(_xconn)) !is null) {
            auto type = event.response_type & 0x7f;
            if (type == XCB_SELECTION_REQUEST) {
                handleSelectionRequest(cast(xcb_selection_request_event_t*)event);
            } else if (type == XCB_SELECTION_CLEAR) {
                _xPrimaryText = "";
            }
            free(event);
        }
    }

    void handleSelectionRequest(xcb_selection_request_event_t* req) {
        if (req is null || _xconn is null) {
            return;
        }
        xcb_atom_t property = req.property == XCB_ATOM_NONE ? req.target : req.property;
        xcb_selection_notify_event_t notify;
        notify.response_type = XCB_SELECTION_NOTIFY;
        notify.sequence = 0;
        notify.time = req.time;
        notify.requestor = req.requestor;
        notify.selection = req.selection;
        notify.target = req.target;
        notify.property = XCB_ATOM_NONE;

        if (req.selection == _atomPrimary && _xPrimaryText.length != 0) {
            if (req.target == _atomTargets) {
                xcb_atom_t[4] targets = [
                    _atomTargets,
                    _atomUtf8 != XCB_ATOM_NONE ? _atomUtf8 : XCB_ATOM_STRING,
                    _atomText != XCB_ATOM_NONE ? _atomText : XCB_ATOM_STRING,
                    XCB_ATOM_STRING
                ];
                xcb_change_property(_xconn, XCB_PROP_MODE_REPLACE, req.requestor,
                    property, XCB_ATOM_ATOM, 32, cast(uint)targets.length, targets.ptr);
                notify.property = property;
            } else if (req.target == _atomUtf8 || req.target == _atomText ||
                req.target == XCB_ATOM_STRING) {
                auto bytes = cast(const(ubyte)[])_xPrimaryText;
                xcb_change_property(_xconn, XCB_PROP_MODE_REPLACE, req.requestor,
                    property, req.target, 8, cast(uint)bytes.length, bytes.ptr);
                notify.property = property;
            }
        }

        xcb_send_event(_xconn, 0, req.requestor, 0, cast(char*)&notify);
        xcb_flush(_xconn);
    }

    void setPrimaryX11(string text) {
        if (!_x11Available || _xconn is null) {
            return;
        }
        _xPrimaryText = text.idup;
        xcb_set_selection_owner(_xconn, _xwindow, _atomPrimary, XCB_TIME_CURRENT_TIME);
        xcb_flush(_xconn);
    }

    string requestPrimaryX11() {
        if (!_x11Available || _xconn is null) {
            return "";
        }
        xcb_atom_t target = _atomUtf8 != XCB_ATOM_NONE ? _atomUtf8 : XCB_ATOM_STRING;
        xcb_convert_selection(_xconn, _xwindow, _atomPrimary, target, _atomXselData,
            XCB_TIME_CURRENT_TIME);
        xcb_flush(_xconn);
        while (true) {
            auto event = xcb_wait_for_event(_xconn);
            if (event is null) {
                break;
            }
            auto type = event.response_type & 0x7f;
            if (type == XCB_SELECTION_NOTIFY) {
                auto notify = cast(xcb_selection_notify_event_t*)event;
                string text;
                if (notify.property != XCB_ATOM_NONE) {
                    text = readSelectionProperty(notify.property);
                } else if (target != XCB_ATOM_STRING) {
                    text = requestPrimaryX11StringFallback();
                }
                free(event);
                return text;
            }
            if (type == XCB_SELECTION_REQUEST) {
                handleSelectionRequest(cast(xcb_selection_request_event_t*)event);
            } else if (type == XCB_SELECTION_CLEAR) {
                _xPrimaryText = "";
            }
            free(event);
        }
        return "";
    }

    string requestPrimaryX11StringFallback() {
        if (!_x11Available || _xconn is null) {
            return "";
        }
        xcb_convert_selection(_xconn, _xwindow, _atomPrimary, XCB_ATOM_STRING,
            _atomXselData, XCB_TIME_CURRENT_TIME);
        xcb_flush(_xconn);
        while (true) {
            auto event = xcb_wait_for_event(_xconn);
            if (event is null) {
                break;
            }
            auto type = event.response_type & 0x7f;
            if (type == XCB_SELECTION_NOTIFY) {
                auto notify = cast(xcb_selection_notify_event_t*)event;
                string text = notify.property != XCB_ATOM_NONE
                    ? readSelectionProperty(notify.property) : "";
                free(event);
                return text;
            }
            if (type == XCB_SELECTION_REQUEST) {
                handleSelectionRequest(cast(xcb_selection_request_event_t*)event);
            } else if (type == XCB_SELECTION_CLEAR) {
                _xPrimaryText = "";
            }
            free(event);
        }
        return "";
    }

    string readSelectionProperty(xcb_atom_t property) {
        auto cookie = xcb_get_property(_xconn, 0, _xwindow, property,
            XCB_GET_PROPERTY_TYPE_ANY, 0, uint.max);
        auto reply = xcb_get_property_reply(_xconn, cookie, null);
        if (reply is null) {
            return "";
        }
        scope(exit) free(reply);
        int len = xcb_get_property_value_length(reply);
        if (len <= 0) {
            return "";
        }
        auto data = cast(const(char)*)xcb_get_property_value(reply);
        return cast(string)data[0 .. len].idup;
    }
}
