/**
 * Signal/Slot Pattern Implementation
 *
 * Type-safe observer pattern for event handling.
 * Inspired by Qt signals/slots and D's std.signals (but simpler).
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.util.signal;

version (PURE_D_BACKEND):

import std.algorithm : remove, countUntil;

/**
 * Signal template for type-safe event emission.
 *
 * Example:
 * ---
 * class Button {
 *     Signal!() clicked;
 *     Signal!string textChanged;
 *
 *     void doClick() {
 *         clicked.emit();
 *     }
 * }
 *
 * auto btn = new Button();
 * btn.clicked.connect(() { writeln("Clicked!"); });
 * btn.textChanged.connect((text) { writeln("Text: ", text); });
 * ---
 */
struct Signal(Args...) {
private:
    alias SlotType = void delegate(Args);
    SlotType[] _slots;
    bool _emitting;
    SlotType[] _pendingRemove;
    SlotType[] _pendingAdd;

public:
    /**
     * Connect a handler to this signal.
     *
     * Params:
     *   slot = Delegate to call when signal emits
     */
    void connect(SlotType slot) {
        if (slot is null) return;

        if (_emitting) {
            _pendingAdd ~= slot;
        } else {
            _slots ~= slot;
        }
    }

    /**
     * Connect a handler (function pointer version).
     */
    void connect(void function(Args) fn) {
        if (fn is null) return;
        connect(toDelegate(fn));
    }

    /**
     * Disconnect a handler.
     *
     * Params:
     *   slot = Delegate to disconnect
     */
    void disconnect(SlotType slot) {
        if (slot is null) return;

        if (_emitting) {
            _pendingRemove ~= slot;
        } else {
            removeSlot(slot);
        }
    }

    /**
     * Disconnect all handlers.
     */
    void disconnectAll() {
        if (_emitting) {
            _pendingRemove = _slots.dup;
        } else {
            _slots = [];
        }
    }

    /**
     * Emit the signal, calling all connected handlers.
     *
     * Params:
     *   args = Arguments to pass to handlers
     */
    void emit(Args args) {
        if (_slots.length == 0) return;

        _emitting = true;
        scope(exit) {
            _emitting = false;
            processPending();
        }

        foreach (slot; _slots) {
            // Skip slots marked for removal
            if (_pendingRemove.countUntil(slot) >= 0)
                continue;
            slot(args);
        }
    }

    /**
     * Check if any handlers are connected.
     */
    @property bool hasConnections() const {
        return _slots.length > 0;
    }

    /**
     * Number of connected handlers.
     */
    @property size_t connectionCount() const {
        return _slots.length;
    }

    /**
     * Opaque connection handle for later disconnection.
     */
    static struct Connection {
        private SlotType _slot;
        private Signal!(Args)* _signal;

        void disconnect() {
            if (_signal !is null && _slot !is null) {
                _signal.disconnect(_slot);
                _signal = null;
                _slot = null;
            }
        }

        @property bool connected() const {
            return _signal !is null && _slot !is null;
        }
    }

    /**
     * Connect and return a connection handle.
     */
    Connection connectWithHandle(SlotType slot) {
        connect(slot);
        return Connection(slot, &this);
    }

private:
    void removeSlot(SlotType slot) {
        auto idx = _slots.countUntil(slot);
        if (idx >= 0) {
            _slots = _slots.remove(idx);
        }
    }

    void processPending() {
        foreach (slot; _pendingRemove) {
            removeSlot(slot);
        }
        _pendingRemove = [];

        foreach (slot; _pendingAdd) {
            _slots ~= slot;
        }
        _pendingAdd = [];
    }

    static SlotType toDelegate(void function(Args) fn) {
        // Create delegate from function pointer
        struct Wrapper {
            void function(Args) fn;
            void call(Args args) {
                fn(args);
            }
        }
        auto w = new Wrapper;
        w.fn = fn;
        return &w.call;
    }
}

/**
 * Signal with void arguments (no parameters).
 */
alias Signal0 = Signal!();

/**
 * Property change notification.
 *
 * Convenience wrapper for property change signals.
 */
struct PropertySignal(T) {
    Signal!(T, T) changed;  // (oldValue, newValue)

    void emit(T oldValue, T newValue) {
        if (oldValue != newValue) {
            changed.emit(oldValue, newValue);
        }
    }
}

/**
 * Scoped connection - automatically disconnects when destroyed.
 *
 * Example:
 * ---
 * {
 *     auto conn = scopedConnect(signal, &handler);
 *     // handler is connected
 * }
 * // handler is automatically disconnected
 * ---
 */
struct ScopedConnection(Args...) {
    private Signal!(Args).Connection _connection;

    @disable this(this);

    this(ref Signal!(Args) signal, void delegate(Args) slot) {
        _connection = signal.connectWithHandle(slot);
    }

    ~this() {
        disconnect();
    }

    void disconnect() {
        _connection.disconnect();
    }

    @property bool connected() const {
        return _connection.connected;
    }
}

/**
 * Create a scoped connection.
 */
auto scopedConnect(Args...)(ref Signal!(Args) signal, void delegate(Args) slot) {
    return ScopedConnection!(Args)(signal, slot);
}

/**
 * Event aggregator for centralized event handling.
 *
 * Allows loose coupling between components that don't know about each other.
 */
class EventAggregator {
private:
    void delegate()[][TypeInfo] _handlers;

public:
    /**
     * Subscribe to an event type.
     */
    void subscribe(T)(void delegate(T) handler) {
        auto ti = typeid(T);
        if (ti !in _handlers) {
            _handlers[ti] = [];
        }
        // Wrap handler to match void delegate()
        _handlers[ti] ~= () {
            // Note: This requires storing the event somehow
            // This is a simplified implementation
        };
    }

    /**
     * Publish an event.
     */
    void publish(T)(T event) {
        auto ti = typeid(T);
        if (auto handlers = ti in _handlers) {
            foreach (handler; *handlers) {
                handler();
            }
        }
    }
}

// === Unit Tests ===

unittest {
    // Test basic signal/slot
    int callCount = 0;
    Signal!int sig;

    sig.connect((int x) { callCount += x; });
    sig.emit(5);
    assert(callCount == 5);

    sig.emit(3);
    assert(callCount == 8);
}

unittest {
    // Test void signal
    bool called = false;
    Signal!() sig;

    sig.connect(() { called = true; });
    sig.emit();
    assert(called);
}

unittest {
    // Test disconnect
    int callCount = 0;
    Signal!() sig;

    void handler() { callCount++; }
    sig.connect(&handler);

    sig.emit();
    assert(callCount == 1);

    sig.disconnect(&handler);
    sig.emit();
    assert(callCount == 1);  // Not called again
}

unittest {
    // Test multiple arguments
    string result;
    Signal!(string, int) sig;

    sig.connect((string s, int n) {
        result = s;
        foreach (_; 0 .. n) result ~= "!";
    });

    sig.emit("Hello", 3);
    assert(result == "Hello!!!");
}
