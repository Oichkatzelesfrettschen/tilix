/**
 * Accessibility Announcer
 *
 * Provides screen reader announcement functionality.
 * Queues announcements for screen reader consumption.
 *
 * Future: Hook into AT-SPI for live region announcements.
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.accessibility.announcer;

version (PURE_D_BACKEND):

import std.datetime : Duration, seconds;
import core.time : MonoTime;

/**
 * Announcement priority levels.
 */
enum AnnouncePriority {
    low,      // Informational, can be interrupted
    medium,   // Normal announcements
    high,     // Important, should not be interrupted
    urgent    // Critical, interrupt current speech
}

/**
 * Announcement types for categorization.
 */
enum AnnounceType {
    text,        // Regular text content
    output,      // New terminal output
    cursor,      // Cursor movement
    selection,   // Selection change
    alert,       // Alert or bell
    title,       // Window/tab title change
    status       // Status information
}

/**
 * Announcement entry.
 */
struct Announcement {
    string message;
    AnnounceType type;
    AnnouncePriority priority;
    MonoTime timestamp;
    bool spoken;
}

/**
 * Announcement callback signature.
 */
alias AnnounceCallback = void delegate(string message, AnnounceType type, AnnouncePriority priority);

/**
 * Screen reader announcer.
 *
 * Manages announcement queue and delivery for screen readers.
 * Provides debouncing and priority handling.
 */
class AccessibilityAnnouncer {
private:
    Announcement[] _queue;
    AnnounceCallback _callback;
    bool _enabled = true;
    Duration _debounceTime = seconds(0);
    MonoTime _lastAnnounce;
    size_t _maxQueue = 100;

public:
    /**
     * Enable or disable announcements.
     */
    @property void enabled(bool value) { _enabled = value; }
    @property bool enabled() const { return _enabled; }

    /**
     * Set debounce time between announcements.
     */
    @property void debounceTime(Duration value) { _debounceTime = value; }

    /**
     * Set announcement callback.
     *
     * The callback is invoked when an announcement should be spoken.
     * In the future, this will be replaced with AT-SPI integration.
     */
    void setCallback(AnnounceCallback callback) {
        _callback = callback;
    }

    /**
     * Queue an announcement.
     */
    void announce(string message, AnnounceType type = AnnounceType.text,
                  AnnouncePriority priority = AnnouncePriority.medium) {
        if (!_enabled || message.length == 0) {
            return;
        }

        // Check debounce
        auto now = MonoTime.currTime;
        if (_debounceTime > Duration.zero) {
            if (now - _lastAnnounce < _debounceTime && priority != AnnouncePriority.urgent) {
                return;
            }
        }

        Announcement entry;
        entry.message = message;
        entry.type = type;
        entry.priority = priority;
        entry.timestamp = now;
        entry.spoken = false;

        // Handle priority
        if (priority == AnnouncePriority.urgent) {
            // Clear queue for urgent announcements
            _queue = [entry];
        } else if (priority == AnnouncePriority.high) {
            // Insert at front
            _queue = entry ~ _queue;
        } else {
            // Append to queue
            if (_queue.length >= _maxQueue) {
                _queue = _queue[1 .. $];  // Drop oldest
            }
            _queue ~= entry;
        }
    }

    /**
     * Announce cursor movement.
     */
    void announceCursor(int row, int col) {
        import std.format : format;
        announce(format("Row %d, column %d", row + 1, col + 1),
                 AnnounceType.cursor, AnnouncePriority.low);
    }

    /**
     * Announce new output.
     */
    void announceOutput(string text) {
        if (text.length > 200) {
            text = text[0 .. 200] ~ "...";
        }
        announce(text, AnnounceType.output, AnnouncePriority.medium);
    }

    /**
     * Announce selection change.
     */
    void announceSelection(string selectedText) {
        if (selectedText.length == 0) {
            announce("Selection cleared", AnnounceType.selection, AnnouncePriority.low);
        } else if (selectedText.length > 100) {
            import std.format : format;
            announce(format("Selected %d characters", selectedText.length),
                     AnnounceType.selection, AnnouncePriority.low);
        } else {
            announce("Selected: " ~ selectedText, AnnounceType.selection, AnnouncePriority.low);
        }
    }

    /**
     * Announce alert/bell.
     */
    void announceAlert() {
        announce("Alert", AnnounceType.alert, AnnouncePriority.high);
    }

    /**
     * Announce title change.
     */
    void announceTitle(string title) {
        announce("Title: " ~ title, AnnounceType.title, AnnouncePriority.low);
    }

    /**
     * Process pending announcements.
     *
     * Call this periodically (e.g., in main loop) to deliver queued
     * announcements to the callback.
     */
    void pump() {
        if (!_enabled || _callback is null || _queue.length == 0) {
            return;
        }

        auto now = MonoTime.currTime;

        // Find next unspoken announcement
        foreach (ref entry; _queue) {
            if (!entry.spoken) {
                // Check debounce
                if (_debounceTime > Duration.zero &&
                    now - _lastAnnounce < _debounceTime &&
                    entry.priority != AnnouncePriority.urgent) {
                    continue;
                }

                _callback(entry.message, entry.type, entry.priority);
                entry.spoken = true;
                _lastAnnounce = now;
                break;  // One at a time
            }
        }

        // Clean up old spoken entries
        cleanQueue();
    }

    /**
     * Clear all pending announcements.
     */
    void clear() {
        _queue = [];
    }

    /**
     * Get pending announcement count.
     */
    @property size_t pendingCount() const {
        size_t count = 0;
        foreach (ref entry; _queue) {
            if (!entry.spoken) count++;
        }
        return count;
    }

private:
    void cleanQueue() {
        // Remove old spoken entries
        Announcement[] newQueue;
        auto now = MonoTime.currTime;
        foreach (ref entry; _queue) {
            if (!entry.spoken || now - entry.timestamp < seconds(10)) {
                newQueue ~= entry;
            }
        }
        _queue = newQueue;
    }
}

// Unit tests
unittest {
    auto announcer = new AccessibilityAnnouncer();
    assert(announcer.pendingCount == 0);

    announcer.announce("Test");
    assert(announcer.pendingCount == 1);

    announcer.clear();
    assert(announcer.pendingCount == 0);
}

unittest {
    auto announcer = new AccessibilityAnnouncer();
    string received;

    announcer.setCallback((msg, type, priority) {
        received = msg;
    });

    announcer.announce("Hello", AnnounceType.text, AnnouncePriority.medium);
    announcer.pump();

    assert(received == "Hello");
}
