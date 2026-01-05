/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 */

/**
 * Unit tests for VTParser ANSI/DEC VT sequence parser.
 *
 * Test coverage:
 * - Basic text parsing and control characters
 * - UTF-8 multibyte sequence decoding
 * - ANSI escape sequences (CSI, OSC)
 * - SGR (Select Graphic Rendition) color attributes
 * - Cursor movement and positioning
 * - Display and line erasure
 * - State machine transitions
 * - Edge cases and invalid sequences
 */

module gx.tilix.terminal.vtparser_test;

import std.algorithm : equal;
import std.array;
import std.conv;

// Import the parser
import gx.tilix.terminal.vtparser;

// ============ Utility Functions ============

/**
 * Helper to create a parser, feed data, and verify events.
 */
void parseAndExpect(const(ubyte)[] data, scope void delegate(ref VTEvent[]) expectFunc) {
    auto parser = new VTParser();
    VTEvent[] events;
    parser.parse(data, events);
    expectFunc(events);
}

/**
 * Assert that event type matches expected.
 */
void assertEventType(const ref VTEvent event, VTEvent.Type expected, string msg = "") {
    assert(event.type == expected,
        "Expected event type " ~ to!string(expected) ~
        " but got " ~ to!string(event.type) ~
        (msg.length > 0 ? " (" ~ msg ~ ")" : ""));
}

/**
 * Assert CSI final byte.
 */
void assertCSIFinal(const ref VTEvent event, char expected, string msg = "") {
    assert(event.type == VTEvent.Type.SGR ||
           event.type == VTEvent.Type.CursorMove ||
           event.type == VTEvent.Type.EraseDisplay ||
           event.type == VTEvent.Type.EraseLine,
           "Event is not a CSI sequence");
    assert(event.csi.finalByte == expected,
           "Expected CSI final byte '" ~ expected ~ "' but got '" ~ event.csi.finalByte ~
           (msg.length > 0 ? "' (" ~ msg ~ ")" : "'"));
}

/**
 * Assert CSI parameter count.
 */
void assertParamCount(const ref VTEvent event, ubyte expected, string msg = "") {
    assert(event.csi.paramCount == expected,
           "Expected " ~ to!string(expected) ~ " parameters but got " ~ to!string(event.csi.paramCount) ~
           (msg.length > 0 ? " (" ~ msg ~ ")" : ""));
}

/**
 * Assert CSI parameter value.
 */
void assertCSIParam(const ref VTEvent event, ubyte index, int expected, string msg = "") {
    assert(index < event.csi.paramCount,
           "Parameter index " ~ to!string(index) ~ " out of range (max " ~ to!string(event.csi.paramCount) ~ ")");
    assert(event.csi.params[index] == expected,
           "Parameter[" ~ to!string(index) ~ "] expected " ~ to!string(expected) ~
           " but got " ~ to!string(event.csi.params[index]) ~
           (msg.length > 0 ? " (" ~ msg ~ ")" : ""));
}

// ============ Test Cases ============

unittest {
    // Test 1: Plain ASCII text
    parseAndExpect(cast(ubyte[])"Hello", (ref events) {
        assert(events.length == 5, "Expected 5 text events");
        foreach (i, c; "Hello") {
            assertEventType(events[i], VTEvent.Type.Text);
            assert(events[i].codepoint == c, "Expected codepoint '" ~ c ~ "'");
        }
    });
}

unittest {
    // Test 2: Carriage Return
    parseAndExpect([0x0D], (ref events) {
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.CR);
    });
}

unittest {
    // Test 3: Line Feed
    parseAndExpect([0x0A], (ref events) {
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.LF);
    });
}

unittest {
    // Test 4: Backspace
    parseAndExpect([0x08], (ref events) {
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.BS);
    });
}

unittest {
    // Test 5: Horizontal Tab
    parseAndExpect([0x09], (ref events) {
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.HT);
    });
}

unittest {
    // Test 6: Bell (BEL) control character
    parseAndExpect([0x07], (ref events) {
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.BEL);
    });
}

unittest {
    // Test 7: UTF-8 two-byte sequence (é = 0xC3 0xA9)
    parseAndExpect([0xC3, 0xA9], (ref events) {
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.Text);
        assert(events[0].codepoint == 'é', "Expected UTF-8 encoded é");
    });
}

unittest {
    // Test 8: UTF-8 three-byte sequence (€ = 0xE2 0x82 0xAC)
    parseAndExpect([0xE2, 0x82, 0xAC], (ref events) {
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.Text);
    });
}

unittest {
    // Test 9: Mixed ASCII and UTF-8
    ubyte[] data = cast(ubyte[])("Hi " ~ "é" ~ "!");
    parseAndExpect(data, (ref events) {
        assert(events.length == 5, "Expected 5 events (Hi + space + é + !)");
    });
}

unittest {
    // Test 10: CSI SGR - Bold (m is final byte)
    parseAndExpect([0x1B, 0x5B, 0x31, 0x6D], (ref events) {
        // ESC [ 1 m
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.SGR);
        assertCSIFinal(events[0], 'm');
        assertParamCount(events[0], 1);
        assertCSIParam(events[0], 0, 1);
    });
}

unittest {
    // Test 11: CSI SGR - Reset (0)
    parseAndExpect([0x1B, 0x5B, 0x30, 0x6D], (ref events) {
        // ESC [ 0 m
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.SGR);
        assertParamCount(events[0], 1);
        assertCSIParam(events[0], 0, 0);
    });
}

unittest {
    // Test 12: CSI SGR - Multiple parameters (31;1 for red+bold)
    parseAndExpect([0x1B, 0x5B, 0x33, 0x31, 0x3B, 0x31, 0x6D], (ref events) {
        // ESC [ 31 ; 1 m
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.SGR);
        assertParamCount(events[0], 2);
        assertCSIParam(events[0], 0, 31, "foreground red");
        assertCSIParam(events[0], 1, 1, "bold");
    });
}

unittest {
    // Test 13: CSI Cursor Movement - CUP (H)
    parseAndExpect([0x1B, 0x5B, 0x35, 0x3B, 0x31, 0x30, 0x48], (ref events) {
        // ESC [ 5 ; 10 H (move to row 5, col 10)
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.CursorMove);
        assertCSIFinal(events[0], 'H');
        assertParamCount(events[0], 2);
        assertCSIParam(events[0], 0, 5);
        assertCSIParam(events[0], 1, 10);
    });
}

unittest {
    // Test 14: CSI Erase Display - ED (J)
    parseAndExpect([0x1B, 0x5B, 0x32, 0x4A], (ref events) {
        // ESC [ 2 J (erase entire display)
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.EraseDisplay);
        assertCSIFinal(events[0], 'J');
        assertParamCount(events[0], 1);
        assertCSIParam(events[0], 0, 2);
    });
}

unittest {
    // Test 15: CSI Erase Line - EL (K)
    parseAndExpect([0x1B, 0x5B, 0x4B], (ref events) {
        // ESC [ K (erase to end of line)
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.EraseLine);
    });
}

unittest {
    // Test 16: CSI without parameters
    parseAndExpect([0x1B, 0x5B, 0x48], (ref events) {
        // ESC [ H (cursor home)
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.CursorMove);
        assertCSIFinal(events[0], 'H');
    });
}

unittest {
    // Test 17: Parser reset clears state
    auto parser = new VTParser();
    VTEvent[] events;

    // Feed partial sequence
    parser.parse([0x1B, 0x5B], events);
    parser.reset();

    // Feed new complete sequence
    events = [];
    parser.parse([0x1B, 0x5B, 0x31, 0x6D], events);
    assert(events.length == 1, "Reset should allow new sequence parsing");
}

unittest {
    // Test 18: Text followed by control sequence
    ubyte[] data = [
        'H', 'i', // "Hi"
        0x1B, 0x5B, 0x31, 0x6D, // ESC [ 1 m (bold)
        'B', 'y', 'e' // "Bye"
    ];
    parseAndExpect(data, (ref events) {
        assert(events.length == 6, "Expected 2 + 1 + 3 events");
        // Hi
        assertEventType(events[0], VTEvent.Type.Text);
        assertEventType(events[1], VTEvent.Type.Text);
        // SGR
        assertEventType(events[2], VTEvent.Type.SGR);
        // Bye
        assertEventType(events[3], VTEvent.Type.Text);
        assertEventType(events[4], VTEvent.Type.Text);
        assertEventType(events[5], VTEvent.Type.Text);
    });
}

unittest {
    // Test 19: Multiple SGR parameters with missing ones (31;;1 should treat middle as 0)
    parseAndExpect([0x1B, 0x5B, 0x33, 0x31, 0x3B, 0x3B, 0x31, 0x6D], (ref events) {
        // ESC [ 31 ; ; 1 m
        assert(events.length == 1);
        assertEventType(events[0], VTEvent.Type.SGR);
        // Parser should handle missing parameters gracefully
        assertCSIParam(events[0], 0, 31);
    });
}

unittest {
    // Test 20: Incomplete UTF-8 sequence (should not crash)
    auto parser = new VTParser();
    VTEvent[] events;

    // Feed incomplete 2-byte sequence
    parser.parse([0xC3], events); // Missing second byte
    // Should not generate event for incomplete sequence

    // Complete it in next parse
    events = [];
    parser.parse([0xA9], events); // é second byte
    // Should now have complete sequence
}
