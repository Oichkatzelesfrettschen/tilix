module pured.terminal.hyperlink;

version (PURE_D_BACKEND):

import arsd.terminalemulator : TerminalEmulator;

struct HyperlinkRange {
    int row;
    int startCol;
    int endCol;
    string url;
}

void scanLineForLinks(const TerminalEmulator.TerminalCell[] line, int row,
        ref HyperlinkRange[] ranges, ref size_t count, ref char[] scratch) {
    if (line.length == 0) {
        return;
    }
    if (scratch.length < line.length) {
        version (PURE_D_STRICT_NOGC) {
            return;
        } else {
            scratch.length = line.length;
        }
    }

    foreach (i, cell; line) {
        auto mutableCell = cast(TerminalEmulator.TerminalCell)cell;
        dchar ch = mutableCell.hasNonCharacterData ? ' ' : mutableCell.ch;
        if (ch < 0x20 || ch > 0x7E) {
            scratch[i] = ' ';
        } else {
            scratch[i] = cast(char)ch;
        }
    }

    size_t i = 0;
    while (i < line.length) {
        size_t start = size_t.max;
        if (scratch[i] == 'h') {
            if (matchesAt(scratch, i, "http://") ||
                matchesAt(scratch, i, "https://")) {
                start = i;
            }
        } else if (scratch[i] == 'w') {
            if (matchesAt(scratch, i, "www.")) {
                start = i;
            }
        } else if (scratch[i] == 'm') {
            if (matchesAt(scratch, i, "mailto:")) {
                start = i;
            }
        } else if (scratch[i] == 'f') {
            if (matchesAt(scratch, i, "file://") ||
                matchesAt(scratch, i, "ftp://")) {
                start = i;
            }
        } else if (scratch[i] == 's') {
            if (matchesAt(scratch, i, "ssh://")) {
                start = i;
            }
        }

        if (start == size_t.max) {
            i++;
            continue;
        }

        size_t end = start;
        while (end < line.length && isUrlChar(scratch[end])) {
            end++;
        }
        end = trimTrailing(scratch, start, end);
        if (end > start) {
            if (count >= ranges.length) {
                version (PURE_D_STRICT_NOGC) {
                    return;
                } else {
                    ranges.length = ranges.length * 2 + 8;
                }
            }
            auto url = scratch[start .. end].idup;
            ranges[count++] = HyperlinkRange(row, cast(int)start,
                cast(int)(end - 1), url);
        }
        i = end > start ? end : start + 1;
    }
}

private bool matchesAt(const(char)[] text, size_t start, string token) {
    if (start + token.length > text.length) {
        return false;
    }
    foreach (i; 0 .. token.length) {
        if (text[start + i] != token[i]) {
            return false;
        }
    }
    return true;
}

private bool isUrlChar(char ch) {
    if (ch >= 'a' && ch <= 'z') return true;
    if (ch >= 'A' && ch <= 'Z') return true;
    if (ch >= '0' && ch <= '9') return true;
    switch (ch) {
        case '-', '.', '_', '~', ':', '/', '?', '#', '[', ']', '@':
        case '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '=':
        case '%':
            return true;
        default:
            return false;
    }
}

private size_t trimTrailing(const(char)[] text, size_t start, size_t end) {
    size_t trimmed = end;
    while (trimmed > start) {
        char ch = text[trimmed - 1];
        if (ch == ')' || ch == ']' || ch == '}' ||
            ch == '.' || ch == ',' || ch == ';') {
            trimmed--;
            continue;
        }
        break;
    }
    return trimmed;
}
