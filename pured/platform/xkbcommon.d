module pured.platform.xkbcommon;

version (PURE_D_BACKEND):

import std.process : environment;
import std.string : toStringz;
import xkbcommon.xkbcommon;

class XkbTranslator {
private:
    enum int keycodeOffset = 8;

    xkb_context* _context;
    xkb_keymap* _keymap;
    xkb_state* _state;
    xkb_rule_names _names;
    string _rules;
    string _model;
    string _layout;
    string _variant;
    string _options;
    bool _available;

public:
    this() {
        init();
    }

    ~this() {
        shutdown();
    }

    @property bool available() const {
        return _available;
    }

    void updateKey(int scancode, bool pressed) {
        if (!_available || scancode < 0) {
            return;
        }
        auto keycode = cast(xkb_keycode_t)(scancode + keycodeOffset);
        if (!xkb_keycode_is_legal_x11(keycode)) {
            return;
        }
        xkb_state_update_key(_state, keycode,
            pressed ? XKB_KEY_DOWN : XKB_KEY_UP);
    }

    dchar lookupUtf32(int scancode) {
        if (!_available || scancode < 0) {
            return 0;
        }
        auto keycode = cast(xkb_keycode_t)(scancode + keycodeOffset);
        if (!xkb_keycode_is_legal_x11(keycode)) {
            return 0;
        }
        return cast(dchar)xkb_state_key_get_utf32(_state, keycode);
    }

private:
    void init() {
        _context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
        if (_context is null) {
            return;
        }

        _rules = environment.get("XKB_DEFAULT_RULES", "");
        _model = environment.get("XKB_DEFAULT_MODEL", "");
        _layout = environment.get("XKB_DEFAULT_LAYOUT", "");
        _variant = environment.get("XKB_DEFAULT_VARIANT", "");
        _options = environment.get("XKB_DEFAULT_OPTIONS", "");

        _names = xkb_rule_names.init;
        _names.rules = _rules.length ? _rules.toStringz : null;
        _names.model = _model.length ? _model.toStringz : null;
        _names.layout = _layout.length ? _layout.toStringz : null;
        _names.variant = _variant.length ? _variant.toStringz : null;
        _names.options = _options.length ? _options.toStringz : null;

        _keymap = xkb_keymap_new_from_names(
            _context, &_names, XKB_KEYMAP_COMPILE_NO_FLAGS);
        if (_keymap is null) {
            shutdown();
            return;
        }
        _state = xkb_state_new(_keymap);
        if (_state is null) {
            shutdown();
            return;
        }
        _available = true;
    }

    void shutdown() {
        _available = false;
        if (_state !is null) {
            xkb_state_unref(_state);
            _state = null;
        }
        if (_keymap !is null) {
            xkb_keymap_unref(_keymap);
            _keymap = null;
        }
        if (_context !is null) {
            xkb_context_unref(_context);
            _context = null;
        }
    }
}
