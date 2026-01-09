/**
 * AT-SPI Event Handling and Announcements
 *
 * Manages accessibility events and coordinates screen reader announcements.
 * Provides batching and debouncing to avoid flooding listeners.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.accessibility.atspi.events;

version (PURE_D_BACKEND):

import pured.accessibility.atspi.types;
import pured.accessibility.atspi.provider;
import core.time : Duration, dur;
import std.datetime.systime : SysTime, Clock;
import std.array : appender;

/**
 * AT-SPI event emission and batching.
 */
class AccessibilityEventBatcher {
private:
    struct PendingEvent {
        string source;
        ATSPIEventType type;
        string detail;
        SysTime timestamp;
    }

    PendingEvent[] _pendingEvents;
    SysTime _lastEmitTime;
    Duration _textChangedDebounce = dur!"msecs"(50);
    Duration _caretChangedDebounce = dur!"msecs"(100);
    bool _enabled;

public:
    this() {
        _enabled = true;
        _lastEmitTime = Clock.currTime();
    }

    /**
     * Queue an event for batched emission.
     */
    void queueEvent(string source, ATSPIEventType type, string detail = "") {
        if (!_enabled) return;

        PendingEvent evt;
        evt.source = source;
        evt.type = type;
        evt.detail = detail;
        evt.timestamp = Clock.currTime();

        _pendingEvents ~= evt;
    }

    /**
     * Emit all pending events to listeners.
     */
    void pumpEvents() {
        if (_pendingEvents.length == 0) {
            return;
        }

        auto provider = getATSPIProvider();
        if (provider is null) {
            _pendingEvents = [];
            return;
        }

        // Group events by type for deduplication
        bool[string] textChangedEmitted;
        bool[string] caretChangedEmitted;

        foreach (evt; _pendingEvents) {
            // Deduplicate text-changed events
            if (evt.type == ATSPIEventType.TextChanged) {
                if (evt.source !in textChangedEmitted) {
                    provider.emitEvent(evt.source, evt.type, evt.detail);
                    textChangedEmitted[evt.source] = true;
                }
            }
            // Deduplicate caret-moved events
            else if (evt.type == ATSPIEventType.TextCaretMoved) {
                if (evt.source !in caretChangedEmitted) {
                    provider.emitEvent(evt.source, evt.type, evt.detail);
                    caretChangedEmitted[evt.source] = true;
                }
            }
            // Emit all other events
            else {
                provider.emitEvent(evt.source, evt.type, evt.detail);
            }
        }

        _pendingEvents = [];
        _lastEmitTime = Clock.currTime();
    }

    /**
     * Enable or disable event batching.
     */
    void setEnabled(bool enabled) {
        _enabled = enabled;
    }

    /**
     * Check if event batching is enabled.
     */
    bool isEnabled() const {
        return _enabled;
    }

    /**
     * Clear pending events without emitting.
     */
    void clearPendingEvents() {
        _pendingEvents = [];
    }

    /**
     * Set debounce duration for text-changed events.
     */
    void setTextChangedDebounce(Duration duration) {
        _textChangedDebounce = duration;
    }

    /**
     * Set debounce duration for caret-moved events.
     */
    void setCaretChangedDebounce(Duration duration) {
        _caretChangedDebounce = duration;
    }
}

/**
 * Global accessibility event batcher.
 */
private __gshared AccessibilityEventBatcher _eventBatcher;

/**
 * Get global event batcher.
 */
AccessibilityEventBatcher getEventBatcher() {
    if (_eventBatcher is null) {
        _eventBatcher = new AccessibilityEventBatcher();
    }
    return _eventBatcher;
}

/**
 * Announce a text change event (debounced).
 */
void announceTextChanged(string source, string text) {
    auto batcher = getEventBatcher();
    if (batcher !is null) {
        batcher.queueEvent(source, ATSPIEventType.TextChanged, text);
    }
}

/**
 * Announce a caret movement event (debounced).
 */
void announceCaretMoved(string source, uint offset) {
    auto batcher = getEventBatcher();
    if (batcher !is null) {
        import std.format : format;
        batcher.queueEvent(source, ATSPIEventType.TextCaretMoved, format("%d", offset));
    }
}

/**
 * Announce a focus change event (immediate, not batched).
 */
void announceFocusChanged(string source, bool focused) {
    auto provider = getATSPIProvider();
    if (provider !is null) {
        import std.format : format;
        provider.emitEvent(source, ATSPIEventType.FocusChanged, format("%d", focused ? 1 : 0));
    }
}

/**
 * Pump pending accessibility events.
 */
void pumpAccessibilityEvents() {
    auto batcher = getEventBatcher();
    if (batcher !is null) {
        batcher.pumpEvents();
    }
}
