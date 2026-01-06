/**
 * Widget Event System
 *
 * Event hierarchy for UI interactions.
 * Events flow through the widget tree: capture (root->leaf) then bubble (leaf->root).
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.widget.events;

version (PURE_D_BACKEND):

import pured.widget.base : Point, Widget;

/**
 * Event routing strategy.
 */
enum RoutingStrategy {
    direct,   /// Event goes only to target
    bubble,   /// Event bubbles from target to root
    tunnel,   /// Event tunnels from root to target
}

/**
 * Base class for all events.
 */
class Event {
protected:
    Widget _source;
    Widget _originalSource;
    bool _handled;
    RoutingStrategy _routingStrategy;
    long _timestamp;

public:
    this(Widget source, RoutingStrategy strategy = RoutingStrategy.bubble) {
        _source = source;
        _originalSource = source;
        _routingStrategy = strategy;
        _timestamp = currentTimeMillis();
    }

    /// Source widget (changes during routing)
    @property Widget source() { return _source; }
    @property void source(Widget value) { _source = value; }

    /// Original source widget (doesn't change)
    @property Widget originalSource() { return _originalSource; }

    /// Whether event has been handled
    @property bool handled() const { return _handled; }
    @property void handled(bool value) { _handled = value; }

    /// Routing strategy
    @property RoutingStrategy routingStrategy() const { return _routingStrategy; }

    /// Event timestamp (milliseconds)
    @property long timestamp() const { return _timestamp; }

    /// Mark as handled (convenience)
    void markHandled() { _handled = true; }

private:
    static long currentTimeMillis() {
        import core.time : MonoTime;
        return MonoTime.currTime.ticks / 10_000;  // Convert to ~ms
    }
}

// ============================================================================
// Input Events
// ============================================================================

/**
 * Base class for input events.
 */
class InputEvent : Event {
protected:
    ModifierKeys _modifiers;

public:
    this(Widget source, ModifierKeys mods, RoutingStrategy strategy = RoutingStrategy.bubble) {
        super(source, strategy);
        _modifiers = mods;
    }

    @property ModifierKeys modifiers() const { return _modifiers; }

    @property bool shift() const { return (_modifiers & ModifierKeys.shift) != 0; }
    @property bool ctrl() const { return (_modifiers & ModifierKeys.ctrl) != 0; }
    @property bool alt() const { return (_modifiers & ModifierKeys.alt) != 0; }
    @property bool super_() const { return (_modifiers & ModifierKeys.super_) != 0; }
}

/**
 * Modifier key flags.
 */
enum ModifierKeys : uint {
    none    = 0,
    shift   = 1 << 0,
    ctrl    = 1 << 1,
    alt     = 1 << 2,
    super_  = 1 << 3,
    capsLock = 1 << 4,
    numLock  = 1 << 5,
}

// ============================================================================
// Mouse Events
// ============================================================================

/**
 * Mouse button identifiers.
 */
enum MouseButton {
    none,
    left,
    middle,
    right,
    x1,
    x2,
}

/**
 * Mouse event types.
 */
enum MouseEventType {
    move,
    buttonDown,
    buttonUp,
    wheel,
    enter,
    leave,
}

/**
 * Mouse event.
 */
class MouseEvent : InputEvent {
private:
    MouseEventType _eventType;
    Point _position;
    Point _screenPosition;
    MouseButton _button;
    int _clickCount;
    float _wheelDeltaX;
    float _wheelDeltaY;

public:
    this(Widget source, MouseEventType eventType, Point pos, ModifierKeys mods,
         MouseButton button = MouseButton.none) {
        super(source, mods);
        _eventType = eventType;
        _position = pos;
        _screenPosition = pos;  // Will be set by routing
        _button = button;
        _clickCount = 1;
    }

    /// Event type
    @property MouseEventType eventType() const { return _eventType; }

    /// Position in widget-local coordinates
    @property Point position() const { return _position; }
    @property void position(Point value) { _position = value; }

    /// Position in screen coordinates
    @property Point screenPosition() const { return _screenPosition; }
    @property void screenPosition(Point value) { _screenPosition = value; }

    /// X coordinate (convenience)
    @property int x() const { return _position.x; }

    /// Y coordinate (convenience)
    @property int y() const { return _position.y; }

    /// Button that triggered the event
    @property MouseButton button() const { return _button; }

    /// Click count (1=single, 2=double, 3=triple)
    @property int clickCount() const { return _clickCount; }
    @property void clickCount(int value) { _clickCount = value; }

    /// Horizontal wheel delta
    @property float wheelDeltaX() const { return _wheelDeltaX; }
    @property void wheelDeltaX(float value) { _wheelDeltaX = value; }

    /// Vertical wheel delta
    @property float wheelDeltaY() const { return _wheelDeltaY; }
    @property void wheelDeltaY(float value) { _wheelDeltaY = value; }

    /// Check if left button is involved
    @property bool isLeftButton() const { return _button == MouseButton.left; }

    /// Check if right button is involved
    @property bool isRightButton() const { return _button == MouseButton.right; }

    /// Check if middle button is involved
    @property bool isMiddleButton() const { return _button == MouseButton.middle; }
}

/**
 * Create mouse move event.
 */
MouseEvent mouseMove(Widget source, Point pos, ModifierKeys mods) {
    return new MouseEvent(source, MouseEventType.move, pos, mods);
}

/**
 * Create mouse button down event.
 */
MouseEvent mouseDown(Widget source, Point pos, MouseButton button, ModifierKeys mods, int clicks = 1) {
    auto event = new MouseEvent(source, MouseEventType.buttonDown, pos, mods, button);
    event.clickCount = clicks;
    return event;
}

/**
 * Create mouse button up event.
 */
MouseEvent mouseUp(Widget source, Point pos, MouseButton button, ModifierKeys mods) {
    return new MouseEvent(source, MouseEventType.buttonUp, pos, mods, button);
}

/**
 * Create mouse wheel event.
 */
MouseEvent mouseWheel(Widget source, Point pos, float deltaX, float deltaY, ModifierKeys mods) {
    auto event = new MouseEvent(source, MouseEventType.wheel, pos, mods);
    event.wheelDeltaX = deltaX;
    event.wheelDeltaY = deltaY;
    return event;
}

// ============================================================================
// Keyboard Events
// ============================================================================

/**
 * Key action types.
 */
enum KeyAction {
    press,
    release,
    repeat,
}

/**
 * Virtual key codes.
 *
 * Based on GLFW key codes for easy mapping.
 */
enum KeyCode {
    unknown = -1,

    // Printable keys
    space = 32,
    apostrophe = 39,
    comma = 44,
    minus = 45,
    period = 46,
    slash = 47,
    digit0 = 48,
    digit1 = 49,
    digit2 = 50,
    digit3 = 51,
    digit4 = 52,
    digit5 = 53,
    digit6 = 54,
    digit7 = 55,
    digit8 = 56,
    digit9 = 57,
    semicolon = 59,
    equal = 61,
    a = 65, b = 66, c = 67, d = 68, e = 69, f = 70, g = 71, h = 72,
    i = 73, j = 74, k = 75, l = 76, m = 77, n = 78, o = 79, p = 80,
    q = 81, r = 82, s = 83, t = 84, u = 85, v = 86, w = 87, x = 88,
    y = 89, z = 90,
    leftBracket = 91,
    backslash = 92,
    rightBracket = 93,
    graveAccent = 96,

    // Function keys
    escape = 256,
    enter = 257,
    tab = 258,
    backspace = 259,
    insert = 260,
    delete_ = 261,
    right = 262,
    left = 263,
    down = 264,
    up = 265,
    pageUp = 266,
    pageDown = 267,
    home = 268,
    end = 269,
    capsLock = 280,
    scrollLock = 281,
    numLock = 282,
    printScreen = 283,
    pause = 284,
    f1 = 290, f2 = 291, f3 = 292, f4 = 293, f5 = 294, f6 = 295,
    f7 = 296, f8 = 297, f9 = 298, f10 = 299, f11 = 300, f12 = 301,
    f13 = 302, f14 = 303, f15 = 304, f16 = 305, f17 = 306, f18 = 307,
    f19 = 308, f20 = 309, f21 = 310, f22 = 311, f23 = 312, f24 = 313,
    f25 = 314,

    // Keypad
    kp0 = 320, kp1 = 321, kp2 = 322, kp3 = 323, kp4 = 324,
    kp5 = 325, kp6 = 326, kp7 = 327, kp8 = 328, kp9 = 329,
    kpDecimal = 330,
    kpDivide = 331,
    kpMultiply = 332,
    kpSubtract = 333,
    kpAdd = 334,
    kpEnter = 335,
    kpEqual = 336,

    // Modifiers
    leftShift = 340,
    leftControl = 341,
    leftAlt = 342,
    leftSuper = 343,
    rightShift = 344,
    rightControl = 345,
    rightAlt = 346,
    rightSuper = 347,
    menu = 348,
}

/**
 * Keyboard event.
 */
class KeyEvent : InputEvent {
private:
    KeyCode _keyCode;
    KeyAction _action;
    int _scanCode;

public:
    this(Widget source, KeyCode key, KeyAction action, ModifierKeys mods, int scanCode = 0) {
        super(source, mods);
        _keyCode = key;
        _action = action;
        _scanCode = scanCode;
    }

    /// Virtual key code
    @property KeyCode keyCode() const { return _keyCode; }

    /// Key action (press/release/repeat)
    @property KeyAction action() const { return _action; }

    /// Platform-specific scan code
    @property int scanCode() const { return _scanCode; }

    /// Check if key was pressed
    @property bool isPressed() const { return _action == KeyAction.press; }

    /// Check if key was released
    @property bool isReleased() const { return _action == KeyAction.release; }

    /// Check if key is repeating
    @property bool isRepeat() const { return _action == KeyAction.repeat; }

    /// Check if this is a modifier key
    @property bool isModifierKey() const {
        return _keyCode >= KeyCode.leftShift && _keyCode <= KeyCode.rightSuper;
    }
}

/**
 * Character input event (for text input).
 */
class CharEvent : InputEvent {
private:
    dchar _codepoint;

public:
    this(Widget source, dchar codepoint, ModifierKeys mods) {
        super(source, mods);
        _codepoint = codepoint;
    }

    /// Unicode codepoint
    @property dchar codepoint() const { return _codepoint; }

    /// Character as string
    @property string character() const {
        char[4] buf;
        size_t len = encode(buf, _codepoint);
        return buf[0 .. len].idup;
    }

private:
    static size_t encode(ref char[4] buf, dchar c) {
        if (c < 0x80) {
            buf[0] = cast(char)c;
            return 1;
        } else if (c < 0x800) {
            buf[0] = cast(char)(0xC0 | (c >> 6));
            buf[1] = cast(char)(0x80 | (c & 0x3F));
            return 2;
        } else if (c < 0x10000) {
            buf[0] = cast(char)(0xE0 | (c >> 12));
            buf[1] = cast(char)(0x80 | ((c >> 6) & 0x3F));
            buf[2] = cast(char)(0x80 | (c & 0x3F));
            return 3;
        } else {
            buf[0] = cast(char)(0xF0 | (c >> 18));
            buf[1] = cast(char)(0x80 | ((c >> 12) & 0x3F));
            buf[2] = cast(char)(0x80 | ((c >> 6) & 0x3F));
            buf[3] = cast(char)(0x80 | (c & 0x3F));
            return 4;
        }
    }
}

// ============================================================================
// Focus Events
// ============================================================================

/**
 * Focus change reason.
 */
enum FocusReason {
    mouse,      /// Focus changed by mouse click
    tab,        /// Focus changed by Tab key
    backtab,    /// Focus changed by Shift+Tab
    programmatic, /// Focus changed by code
    other,
}

/**
 * Focus event.
 */
class FocusEvent : Event {
private:
    bool _isFocusIn;
    Widget _otherWidget;
    FocusReason _reason;

public:
    this(Widget source, bool focusIn, Widget other, FocusReason reason) {
        super(source, RoutingStrategy.direct);
        _isFocusIn = focusIn;
        _otherWidget = other;
        _reason = reason;
    }

    /// Whether gaining focus (true) or losing (false)
    @property bool isFocusIn() const { return _isFocusIn; }

    /// Widget losing focus (if gaining) or gaining focus (if losing)
    @property Widget otherWidget() { return _otherWidget; }

    /// Reason for focus change
    @property FocusReason reason() const { return _reason; }
}

/**
 * Create focus gained event.
 */
FocusEvent focusIn(Widget source, Widget previous, FocusReason reason) {
    return new FocusEvent(source, true, previous, reason);
}

/**
 * Create focus lost event.
 */
FocusEvent focusOut(Widget source, Widget next, FocusReason reason) {
    return new FocusEvent(source, false, next, reason);
}

// ============================================================================
// Window Events
// ============================================================================

/**
 * Window resize event.
 */
class ResizeEvent : Event {
private:
    int _width;
    int _height;
    int _oldWidth;
    int _oldHeight;

public:
    this(Widget source, int newWidth, int newHeight, int oldWidth, int oldHeight) {
        super(source, RoutingStrategy.direct);
        _width = newWidth;
        _height = newHeight;
        _oldWidth = oldWidth;
        _oldHeight = oldHeight;
    }

    @property int width() const { return _width; }
    @property int height() const { return _height; }
    @property int oldWidth() const { return _oldWidth; }
    @property int oldHeight() const { return _oldHeight; }
}

// ============================================================================
// Event Handlers (Mixin Templates)
// ============================================================================

/**
 * Mixin for adding standard event handlers to a widget.
 */
mixin template EventHandlers() {
    import pured.util.signal : Signal;

    // Mouse signals
    Signal!MouseEvent onMouseDown;
    Signal!MouseEvent onMouseUp;
    Signal!MouseEvent onMouseMove;
    Signal!MouseEvent onMouseWheel;
    Signal!MouseEvent onMouseEnter;
    Signal!MouseEvent onMouseLeave;

    // Keyboard signals
    Signal!KeyEvent onKeyDown;
    Signal!KeyEvent onKeyUp;
    Signal!CharEvent onCharInput;

    // Focus signals
    Signal!FocusEvent onFocusIn;
    Signal!FocusEvent onFocusOut;

    // Dispatch mouse event
    protected void dispatchMouseEvent(MouseEvent event) {
        final switch (event.eventType) {
            case MouseEventType.buttonDown:
                onMouseDown.emit(event);
                break;
            case MouseEventType.buttonUp:
                onMouseUp.emit(event);
                break;
            case MouseEventType.move:
                onMouseMove.emit(event);
                break;
            case MouseEventType.wheel:
                onMouseWheel.emit(event);
                break;
            case MouseEventType.enter:
                onMouseEnter.emit(event);
                break;
            case MouseEventType.leave:
                onMouseLeave.emit(event);
                break;
        }
    }

    // Dispatch key event
    protected void dispatchKeyEvent(KeyEvent event) {
        if (event.isPressed || event.isRepeat) {
            onKeyDown.emit(event);
        } else {
            onKeyUp.emit(event);
        }
    }

    // Dispatch char event
    protected void dispatchCharEvent(CharEvent event) {
        onCharInput.emit(event);
    }

    // Dispatch focus event
    protected void dispatchFocusEvent(FocusEvent event) {
        if (event.isFocusIn) {
            onFocusIn.emit(event);
        } else {
            onFocusOut.emit(event);
        }
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

unittest {
    // Test mouse event creation
    auto me = mouseDown(null, Point(100, 200), MouseButton.left, ModifierKeys.ctrl, 2);
    assert(me.eventType == MouseEventType.buttonDown);
    assert(me.x == 100);
    assert(me.y == 200);
    assert(me.button == MouseButton.left);
    assert(me.clickCount == 2);
    assert(me.ctrl);
    assert(!me.shift);
}

unittest {
    // Test key event
    auto ke = new KeyEvent(null, KeyCode.enter, KeyAction.press, ModifierKeys.shift);
    assert(ke.keyCode == KeyCode.enter);
    assert(ke.isPressed);
    assert(ke.shift);
}

unittest {
    // Test char event UTF-8 encoding
    auto ce = new CharEvent(null, '\u00E9', ModifierKeys.none);  // e with acute
    assert(ce.codepoint == '\u00E9');
    assert(ce.character == "\u00E9");
}

unittest {
    // Test focus event
    auto fe = focusIn(null, null, FocusReason.mouse);
    assert(fe.isFocusIn);
    assert(fe.reason == FocusReason.mouse);
}
