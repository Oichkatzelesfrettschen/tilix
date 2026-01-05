/*
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
 * If a copy of the MPL was not distributed with this file, You can obtain one at
 * http://mozilla.org/MPL/2.0/.
 */
module gx.tilix.terminal.vtparser;

import std.algorithm : min;
import std.conv : to;
import std.range : empty, front, popFront;
import std.experimental.logger;

/**
 * ANSI/DEC VT Parser State Machine
 *
 * Hybrid parser design for IO thread processing:
 * - Parses common CSI sequences (SGR colors, cursor movement, erase)
 * - Decodes UTF-8 byte sequences to codepoints
 * - Delegates complex/rare sequences to VTE for correctness
 *
 * Performance target: <500μs per 4KB of PTY data
 *
 * State Machine Architecture:
 * Based on Paul Williams' VT parser (vt100.net/emu/dec_ansi_parser)
 * Extended for modern terminal capabilities (OSC, DCS, APC)
 */

/**
 * Parser states for ANSI/DEC escape sequence processing.
 *
 * Flow:
 * Ground -> Escape -> CSI/OSC/DCS -> Ground
 */
enum VTState : ubyte {
    Ground = 0,         // Normal text input
    Escape,             // ESC received, awaiting sequence type
    EscapeIntermediate, // ESC [ or ESC ] intermediate bytes
    CSIEntry,           // Control Sequence Introducer (ESC [)
    CSIParam,           // Reading CSI parameters (digits, semicolons)
    CSIIntermediate,    // CSI intermediate bytes (space, !, etc.)
    CSIIgnore,          // Invalid CSI sequence, ignore until terminator
    DCSEntry,           // Device Control String (ESC P)
    DCSParam,           // DCS parameter bytes
    DCSIntermediate,    // DCS intermediate bytes
    DCSPassthrough,     // DCS string data
    DCSIgnore,          // Invalid DCS, ignore until ST
    OSCString,          // Operating System Command (ESC ])
    STIgnore            // Ignoring until String Terminator (ESC \)
}

/**
 * Parser actions triggered by state transitions.
 */
enum VTAction : ubyte {
    None,           // No action
    Print,          // Print character to buffer
    Execute,        // Execute C0/C1 control
    CSIDispatch,    // Dispatch CSI sequence
    ESCDispatch,    // Dispatch ESC sequence
    OSCStart,       // Start OSC string collection
    OSCPut,         // Add byte to OSC string
    OSCEnd,         // End OSC string, dispatch
    DCSStart,       // Start DCS string collection
    DCSPut,         // Add byte to DCS string
    DCSEnd,         // End DCS string, dispatch
    Param,          // Add byte to parameter buffer
    Collect,        // Collect intermediate byte
    Clear,          // Clear parser state
    Ignore          // Ignore byte
}

/**
 * Parsed CSI sequence with parameters.
 */
struct CSISequence {
    char finalByte;           // Final character (m, H, J, etc.)
    int[16] params;           // Parameters (max 16)
    ubyte paramCount;         // Actual parameter count
    char[4] intermediates;    // Intermediate bytes
    ubyte intermediateCount;  // Intermediate count

    void reset() {
        finalByte = 0;
        paramCount = 0;
        intermediateCount = 0;
        params[] = 0;
        intermediates[] = 0;
    }
}

/**
 * Parser output event for consumption by renderer.
 */
struct VTEvent {
    enum Type : ubyte {
        Text,           // Printable text (UTF-8 codepoint)
        SGR,            // Set Graphics Rendition (colors, bold, etc.)
        CursorMove,     // Cursor position change
        EraseDisplay,   // ED - Erase in Display
        EraseLine,      // EL - Erase in Line
        InsertChars,    // ICH - Insert blank characters
        DeleteChars,    // DCH - Delete characters
        ScrollUp,       // SU - Scroll up
        ScrollDown,     // SD - Scroll down
        SetMode,        // SM - Set Mode
        ResetMode,      // RM - Reset Mode
        DelegateToVTE,  // Complex sequence - delegate to VTE
        BEL,            // Bell (0x07)
        BS,             // Backspace
        HT,             // Horizontal Tab
        LF,             // Line Feed
        CR              // Carriage Return
    }

    Type type;
    union {
        dchar codepoint;        // For Text events
        CSISequence csi;        // For CSI events
        ubyte[64] rawData;      // For DelegateToVTE
    }
    ubyte rawDataLength;
}

/**
 * High-performance VT parser for IO thread.
 *
 * Design:
 * - Zero-allocation hot path for common sequences
 * - Hybrid approach: fast path for common, delegate rare
 * - UTF-8 decoding integrated into state machine
 */
class VTParser {
private:
    VTState _state;
    CSISequence _csi;
    ubyte[4] _utf8Buffer;    // UTF-8 multibyte accumulator
    ubyte _utf8BytesExpected;
    ubyte _utf8BytesRead;
    ubyte[128] _oscBuffer;   // OSC string accumulator
    ubyte _oscLength;
    ubyte[64] _delegateBuffer;  // Raw bytes for VTE delegation
    ubyte _delegateLength;

    int _currentParam;       // Current CSI parameter being parsed
    bool _hasParam;          // Track if we've seen any param digits

public:

    this() {
        reset();
    }

    void reset() {
        _state = VTState.Ground;
        _csi.reset();
        _utf8BytesExpected = 0;
        _utf8BytesRead = 0;
        _oscLength = 0;
        _delegateLength = 0;
        _currentParam = 0;
        _hasParam = false;
    }

    /**
     * Parse PTY data and yield VT events.
     *
     * Params:
     *   data = Raw PTY bytes
     *   events = Output array for parsed events
     *
     * Performance: Target <500μs for 4KB input
     */
    void parse(const(ubyte)[] data, ref VTEvent[] events) {
        foreach (b; data) {
            auto action = processInputByte(b);
            if (action != VTAction.None) {
                VTEvent event;
                if (executeAction(action, b, event)) {
                    events ~= event;
                }
            }
        }
    }

private:

    /**
     * State machine transition table.
     * Returns action to execute for current state + input byte.
     */
    VTAction processInputByte(ubyte b) {
        final switch (_state) {
            case VTState.Ground:
                return processGround(b);
            case VTState.Escape:
                return processEscape(b);
            case VTState.CSIEntry:
                return processCSIEntry(b);
            case VTState.CSIParam:
                return processCSIParam(b);
            case VTState.CSIIntermediate:
                return processCSIIntermediate(b);
            case VTState.CSIIgnore:
                return processCSIIgnore(b);
            case VTState.OSCString:
                return processOSCString(b);
            case VTState.DCSEntry:
            case VTState.DCSParam:
            case VTState.DCSIntermediate:
            case VTState.DCSPassthrough:
            case VTState.DCSIgnore:
            case VTState.STIgnore:
                // DCS sequences delegated to VTE
                return processDelegated(b);
            case VTState.EscapeIntermediate:
                return processEscapeIntermediate(b);
        }
    }

    VTAction processGround(ubyte b) {
        if (b < 0x20) {
            // C0 control characters
            if (b == 0x1B) {  // ESC
                _state = VTState.Escape;
                _delegateBuffer[0] = b;
                _delegateLength = 1;
                return VTAction.None;
            }
            return VTAction.Execute;  // BEL, BS, HT, LF, CR, etc.
        } else if (b < 0x7F) {
            // ASCII printable
            return VTAction.Print;
        } else if (b >= 0x80 && b < 0xC0) {
            // Invalid UTF-8 start byte
            return VTAction.Ignore;
        } else if (b >= 0xC0) {
            // UTF-8 multibyte sequence start
            _utf8Buffer[0] = b;
            _utf8BytesRead = 1;
            if (b < 0xE0) _utf8BytesExpected = 2;
            else if (b < 0xF0) _utf8BytesExpected = 3;
            else _utf8BytesExpected = 4;
            return VTAction.None;
        }
        return VTAction.Print;
    }

    VTAction processEscape(ubyte b) {
        _delegateBuffer[_delegateLength++] = b;

        if (b == '[') {
            _state = VTState.CSIEntry;
            _csi.reset();
            _currentParam = 0;
            _hasParam = false;
            return VTAction.Clear;
        } else if (b == ']') {
            _state = VTState.OSCString;
            _oscLength = 0;
            return VTAction.OSCStart;
        } else if (b == 'P') {
            _state = VTState.DCSEntry;
            return VTAction.DCSStart;
        } else if (b >= 0x20 && b < 0x30) {
            // Intermediate byte
            _state = VTState.EscapeIntermediate;
            return VTAction.Collect;
        } else if (b >= 0x30 && b < 0x7F) {
            // Final byte - dispatch ESC sequence
            _state = VTState.Ground;
            return VTAction.ESCDispatch;
        }
        return VTAction.Ignore;
    }

    VTAction processEscapeIntermediate(ubyte b) {
        _delegateBuffer[_delegateLength++] = b;

        if (b >= 0x20 && b < 0x30) {
            return VTAction.Collect;
        } else if (b >= 0x30 && b < 0x7F) {
            _state = VTState.Ground;
            return VTAction.ESCDispatch;
        }
        return VTAction.Ignore;
    }

    VTAction processCSIEntry(ubyte b) {
        _delegateBuffer[_delegateLength++] = b;

        if (b >= '0' && b <= '9') {
            _state = VTState.CSIParam;
            _currentParam = _currentParam * 10 + (b - '0');
            _hasParam = true;
            return VTAction.Param;
        } else if (b == ';') {
            _state = VTState.CSIParam;
            if (_hasParam) {
                _csi.params[_csi.paramCount++] = _currentParam;
            }
            _currentParam = 0;
            _hasParam = false;
            return VTAction.Param;
        } else if (b >= 0x20 && b < 0x30) {
            _state = VTState.CSIIntermediate;
            return VTAction.Collect;
        } else if (b >= 0x40 && b < 0x7F) {
            _csi.finalByte = cast(char)b;
            if (_hasParam) {
                _csi.params[_csi.paramCount++] = _currentParam;
            }
            _state = VTState.Ground;
            return VTAction.CSIDispatch;
        }
        return VTAction.Ignore;
    }

    VTAction processCSIParam(ubyte b) {
        _delegateBuffer[_delegateLength++] = b;

        if (b >= '0' && b <= '9') {
            _currentParam = _currentParam * 10 + (b - '0');
            _hasParam = true;
            return VTAction.Param;
        } else if (b == ';') {
            if (_hasParam) {
                _csi.params[_csi.paramCount++] = _currentParam;
            }
            _currentParam = 0;
            _hasParam = false;
            return VTAction.Param;
        } else if (b >= 0x20 && b < 0x30) {
            if (_hasParam) {
                _csi.params[_csi.paramCount++] = _currentParam;
            }
            _state = VTState.CSIIntermediate;
            return VTAction.Collect;
        } else if (b >= 0x40 && b < 0x7F) {
            if (_hasParam) {
                _csi.params[_csi.paramCount++] = _currentParam;
            }
            _csi.finalByte = cast(char)b;
            _state = VTState.Ground;
            return VTAction.CSIDispatch;
        } else if (b < 0x20) {
            _state = VTState.CSIIgnore;
            return VTAction.Ignore;
        }
        return VTAction.Ignore;
    }

    VTAction processCSIIntermediate(ubyte b) {
        _delegateBuffer[_delegateLength++] = b;

        if (b >= 0x20 && b < 0x30) {
            if (_csi.intermediateCount < 4) {
                _csi.intermediates[_csi.intermediateCount++] = cast(char)b;
            }
            return VTAction.Collect;
        } else if (b >= 0x40 && b < 0x7F) {
            _csi.finalByte = cast(char)b;
            _state = VTState.Ground;
            return VTAction.CSIDispatch;
        } else {
            _state = VTState.CSIIgnore;
            return VTAction.Ignore;
        }
    }

    VTAction processCSIIgnore(ubyte b) {
        if (b >= 0x40 && b < 0x7F) {
            _state = VTState.Ground;
        }
        return VTAction.Ignore;
    }

    VTAction processOSCString(ubyte b) {
        // OSC sequences: ESC ] Ps ; Pt ST
        // ST = ESC \ or 0x9C
        if (b == 0x07 || b == 0x9C) {  // BEL or ST
            _state = VTState.Ground;
            return VTAction.OSCEnd;
        } else if (b == 0x1B) {
            // Might be ESC \ (ST)
            _state = VTState.STIgnore;
            return VTAction.None;
        } else if (_oscLength < _oscBuffer.length) {
            _oscBuffer[_oscLength++] = b;
            return VTAction.OSCPut;
        }
        return VTAction.Ignore;
    }

    VTAction processDelegated(ubyte b) {
        // Accumulate bytes for VTE delegation
        if (_delegateLength < _delegateBuffer.length) {
            _delegateBuffer[_delegateLength++] = b;
        }

        // Check for terminator
        if (b == 0x9C || (_state == VTState.STIgnore && b == '\\')) {
            _state = VTState.Ground;
            return VTAction.DCSEnd;
        }
        return VTAction.None;
    }

    /**
     * Execute parser action and generate VTEvent if applicable.
     */
    bool executeAction(VTAction action, ubyte b, ref VTEvent event) {
        switch (action) {
            case VTAction.Print:
                if (_utf8BytesExpected > 0) {
                    // Continue UTF-8 sequence
                    _utf8Buffer[_utf8BytesRead++] = b;
                    if (_utf8BytesRead == _utf8BytesExpected) {
                        // Complete UTF-8 sequence
                        dchar codepoint = decodeUTF8(_utf8Buffer[0.._utf8BytesExpected]);
                        _utf8BytesExpected = 0;
                        _utf8BytesRead = 0;
                        event.type = VTEvent.Type.Text;
                        event.codepoint = codepoint;
                        return true;
                    }
                    return false;
                } else {
                    // ASCII character
                    event.type = VTEvent.Type.Text;
                    event.codepoint = cast(dchar)b;
                    return true;
                }

            case VTAction.Execute:
                return executeControlChar(b, event);

            case VTAction.CSIDispatch:
                return dispatchCSI(event);

            case VTAction.ESCDispatch:
            case VTAction.DCSEnd:
                // Delegate to VTE
                event.type = VTEvent.Type.DelegateToVTE;
                event.rawDataLength = cast(ubyte)min(_delegateLength, event.rawData.length);
                event.rawData[0..event.rawDataLength] = _delegateBuffer[0..event.rawDataLength];
                _delegateLength = 0;
                return true;

            case VTAction.OSCEnd:
                // For now, delegate OSC to VTE
                // Future: parse OSC 0/1/2 (window title) here
                event.type = VTEvent.Type.DelegateToVTE;
                event.rawDataLength = cast(ubyte)min(_oscLength + 4, event.rawData.length);
                // Reconstruct: ESC ] <osc> BEL
                event.rawData[0] = 0x1B;
                event.rawData[1] = ']';
                event.rawData[2.._oscLength+2] = _oscBuffer[0.._oscLength];
                event.rawData[_oscLength+2] = 0x07;
                _oscLength = 0;
                return true;

            default:
                return false;
        }
    }

    bool executeControlChar(ubyte b, ref VTEvent event) {
        switch (b) {
            case 0x07:  // BEL
                event.type = VTEvent.Type.BEL;
                return true;
            case 0x08:  // BS
                event.type = VTEvent.Type.BS;
                return true;
            case 0x09:  // HT
                event.type = VTEvent.Type.HT;
                return true;
            case 0x0A:  // LF
                event.type = VTEvent.Type.LF;
                return true;
            case 0x0D:  // CR
                event.type = VTEvent.Type.CR;
                return true;
            default:
                return false;
        }
    }

    bool dispatchCSI(ref VTEvent event) {
        // Fast path for common CSI sequences
        switch (_csi.finalByte) {
            case 'm':  // SGR - Set Graphics Rendition
                event.type = VTEvent.Type.SGR;
                event.csi = _csi;
                _delegateLength = 0;
                return true;

            case 'H':  // CUP - Cursor Position
            case 'f':  // HVP - Horizontal and Vertical Position
                event.type = VTEvent.Type.CursorMove;
                event.csi = _csi;
                _delegateLength = 0;
                return true;

            case 'J':  // ED - Erase in Display
                event.type = VTEvent.Type.EraseDisplay;
                event.csi = _csi;
                _delegateLength = 0;
                return true;

            case 'K':  // EL - Erase in Line
                event.type = VTEvent.Type.EraseLine;
                event.csi = _csi;
                _delegateLength = 0;
                return true;

            case '@':  // ICH - Insert Characters
                event.type = VTEvent.Type.InsertChars;
                event.csi = _csi;
                _delegateLength = 0;
                return true;

            case 'P':  // DCH - Delete Characters
                event.type = VTEvent.Type.DeleteChars;
                event.csi = _csi;
                _delegateLength = 0;
                return true;

            default:
                // Delegate to VTE for less common sequences
                event.type = VTEvent.Type.DelegateToVTE;
                event.rawDataLength = cast(ubyte)min(_delegateLength, event.rawData.length);
                event.rawData[0..event.rawDataLength] = _delegateBuffer[0..event.rawDataLength];
                _delegateLength = 0;
                return true;
        }
    }

    dchar decodeUTF8(const(ubyte)[] bytes) {
        // Simple UTF-8 decoder
        if (bytes.length == 1) {
            return cast(dchar)bytes[0];
        } else if (bytes.length == 2) {
            return cast(dchar)(
                ((bytes[0] & 0x1F) << 6) |
                (bytes[1] & 0x3F)
            );
        } else if (bytes.length == 3) {
            return cast(dchar)(
                ((bytes[0] & 0x0F) << 12) |
                ((bytes[1] & 0x3F) << 6) |
                (bytes[2] & 0x3F)
            );
        } else if (bytes.length == 4) {
            return cast(dchar)(
                ((bytes[0] & 0x07) << 18) |
                ((bytes[1] & 0x3F) << 12) |
                ((bytes[2] & 0x3F) << 6) |
                (bytes[3] & 0x3F)
            );
        }
        return 0xFFFD;  // Replacement character
    }
}
