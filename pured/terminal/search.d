module pured.terminal.search;

version (PURE_D_BACKEND):

import arsd.terminalemulator : TerminalEmulator;
import pured.terminal.frame : TerminalFrame;
import pured.terminal.scrollback_buffer : ScrollbackBuffer;
import core.bitop : bsf;


version (X86_64) {
    import inteli.emmintrin : __m128i, _mm_cmpeq_epi8, _mm_loadu_si128,
        _mm_movemask_epi8, _mm_set1_epi8;
}
version (X86) {
    import inteli.emmintrin : __m128i, _mm_cmpeq_epi8, _mm_loadu_si128,
        _mm_movemask_epi8, _mm_set1_epi8;
}

struct SearchHit {
    size_t line;
    size_t column;
}

struct SearchRange {
    int row;
    int startCol;
    int endCol;
}

/// Search scrollback lines for a UTF-8 needle. Caller should hold scrollback lock.
SearchHit[] findInScrollback(ScrollbackBuffer buffer, string needle,
        size_t maxResults = 256) {
    SearchHit[] hits;
    if (buffer is null || needle.length == 0) {
        return hits;
    }
    auto needleBytes = cast(const(ubyte)[]) needle;
    ubyte[] lineBytes;
    size_t[] cellOffsets;
    size_t lineCount = buffer.lineCount;
    foreach (lineIndex; 0 .. lineCount) {
        auto line = buffer.lineView(lineIndex);
        if (line is null) {
            continue;
        }
        lineToUtf8(line, lineBytes, cellOffsets);
        if (lineBytes.length < needleBytes.length) {
            continue;
        }
        size_t searchFrom = 0;
        while (true) {
            auto pos = findSubsequence(lineBytes, needleBytes, searchFrom);
            if (pos == size_t.max) {
                break;
            }
            auto col = byteOffsetToCell(cellOffsets, pos);
            hits ~= SearchHit(lineIndex, col);
            if (hits.length >= maxResults) {
                return hits;
            }
            size_t step = needleBytes.length == 0 ? 1 : needleBytes.length;
            searchFrom = pos + step;
        }
    }
    return hits;
}

/// Search visible frame lines. baseLine should be scrollback line count.
SearchHit[] findInFrame(ref TerminalFrame frame, string needle, size_t baseLine,
        size_t maxResults = 256, size_t existingCount = 0) {
    SearchHit[] hits;
    if (needle.length == 0 || frame.cols <= 0 || frame.rows <= 0) {
        return hits;
    }
    auto needleBytes = cast(const(ubyte)[]) needle;
    ubyte[] lineBytes;
    size_t[] cellOffsets;
    size_t remaining = maxResults > existingCount ? maxResults - existingCount : 0;
    if (remaining == 0) {
        return hits;
    }
    foreach (row; 0 .. frame.rows) {
        auto line = frame.cells[(row * frame.cols) .. ((row + 1) * frame.cols)];
        lineToUtf8(line, lineBytes, cellOffsets);
        if (lineBytes.length < needleBytes.length) {
            continue;
        }
        size_t searchFrom = 0;
        while (true) {
            auto pos = findSubsequence(lineBytes, needleBytes, searchFrom);
            if (pos == size_t.max) {
                break;
            }
            auto col = byteOffsetToCell(cellOffsets, pos);
            hits ~= SearchHit(baseLine + row, col);
            if (hits.length >= remaining) {
                return hits;
            }
            size_t step = needleBytes.length == 0 ? 1 : needleBytes.length;
            searchFrom = pos + step;
        }
    }
    return hits;
}
private void lineToUtf8(const(TerminalEmulator.TerminalCell)[] line,
        ref ubyte[] outBytes, ref size_t[] cellOffsets) {
    size_t cols = line.length;
    if (cellOffsets.length != cols + 1) {
        cellOffsets.length = cols + 1;
    }
    outBytes.length = cols * 4;
    size_t offset = 0;
    foreach (i, cell; line) {
        cellOffsets[i] = offset;
        auto mutableCell = cast(TerminalEmulator.TerminalCell)cell;
        dchar ch = mutableCell.hasNonCharacterData ? ' ' : mutableCell.ch;
        if (ch == 0) {
            ch = ' ';
        }
        ubyte[4] buf;
        size_t written = encodeUtf8(ch, buf);
        foreach (j; 0 .. written) {
            outBytes[offset + j] = buf[j];
        }
        offset += written;
    }
    cellOffsets[cols] = offset;
    outBytes.length = offset;
}
private size_t encodeUtf8(dchar codepoint, ref ubyte[4] buffer) {
    if (codepoint < 0x80) {
        buffer[0] = cast(ubyte)codepoint;
        return 1;
    } else if (codepoint < 0x800) {
        buffer[0] = cast(ubyte)(0xC0 | (codepoint >> 6));
        buffer[1] = cast(ubyte)(0x80 | (codepoint & 0x3F));
        return 2;
    } else if (codepoint < 0x10000) {
        buffer[0] = cast(ubyte)(0xE0 | (codepoint >> 12));
        buffer[1] = cast(ubyte)(0x80 | ((codepoint >> 6) & 0x3F));
        buffer[2] = cast(ubyte)(0x80 | (codepoint & 0x3F));
        return 3;
    }
    buffer[0] = cast(ubyte)(0xF0 | (codepoint >> 18));
    buffer[1] = cast(ubyte)(0x80 | ((codepoint >> 12) & 0x3F));
    buffer[2] = cast(ubyte)(0x80 | ((codepoint >> 6) & 0x3F));
    buffer[3] = cast(ubyte)(0x80 | (codepoint & 0x3F));
    return 4;
}

private size_t byteOffsetToCell(const size_t[] offsets, size_t byteOffset) {
    if (offsets.length == 0) {
        return 0;
    }
    size_t lo = 0;
    size_t hi = offsets.length - 1;
    while (lo + 1 < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (offsets[mid] <= byteOffset) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    return lo;
}
private size_t findSubsequence(const(ubyte)[] haystack,
        const(ubyte)[] needle, size_t start) {
    if (needle.length == 0 || haystack.length < needle.length) {
        return size_t.max;
    }
    size_t i = start;
    while (i + needle.length <= haystack.length) {
        i = findByte(haystack, needle[0], i);
        if (i == size_t.max || i + needle.length > haystack.length) {
            return size_t.max;
        }
        bool match = true;
        foreach (j; 1 .. needle.length) {
            if (haystack[i + j] != needle[j]) {
                match = false;
                break;
            }
        }
        if (match) {
            return i;
        }
        i++;
    }
    return size_t.max;
}
private size_t findByte(const(ubyte)[] data, ubyte value, size_t start) nothrow @nogc {
    if (start >= data.length) {
        return size_t.max;
    }

    version (X86_64) {
        enum block = 16;
        size_t i = start;
        __m128i needle = _mm_set1_epi8(cast(byte)value);

        for (; i + block <= data.length; i += block) {
            __m128i chunk = _mm_loadu_si128(cast(const(__m128i)*)&data[i]);
            __m128i eq = _mm_cmpeq_epi8(chunk, needle);
            uint mask = cast(uint)_mm_movemask_epi8(eq);
            if (mask != 0) {
                return i + bsf(mask);
            }
        }

        for (; i < data.length; i++) {
            if (data[i] == value) {
                return i;
            }
        }
        return size_t.max;
    } else version (X86) {
        enum block = 16;
        size_t i = start;
        __m128i needle = _mm_set1_epi8(cast(byte)value);

        for (; i + block <= data.length; i += block) {
            __m128i chunk = _mm_loadu_si128(cast(const(__m128i)*)&data[i]);
            __m128i eq = _mm_cmpeq_epi8(chunk, needle);
            uint mask = cast(uint)_mm_movemask_epi8(eq);
            if (mask != 0) {
                return i + bsf(mask);
            }
        }

        for (; i < data.length; i++) {
            if (data[i] == value) {
                return i;
            }
        }
        return size_t.max;
    } else {
        foreach (i, v; data[start .. $]) {
            if (v == value) {
                return start + i;
            }
        }
        return size_t.max;
    }
}

unittest {
    TerminalFrame frame;
    frame.ensureSize(22, 2);
    auto line0 = "0123456789abcdefHELLO";
    foreach (col; 0 .. frame.cols) {
        TerminalEmulator.TerminalCell cell = TerminalEmulator.TerminalCell.init;
        if (col < line0.length) {
            cell.ch = line0[col];
        } else {
            cell.ch = ' ';
        }
        frame.cells[col] = cell;
        frame.cells[frame.cols + col] = cell;
    }

    auto hits = findInFrame(frame, "defH", 0, 4);
    assert(hits.length == 1);
    assert(hits[0].line == 0);
    assert(hits[0].column == 13);
}
