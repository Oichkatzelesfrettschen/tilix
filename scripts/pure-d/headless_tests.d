module headless_tests;

version (PURE_D_BACKEND):

import arsd.terminalemulator : TerminalEmulator;
import pured.terminal.scrollback_buffer : ScrollbackBuffer;
import pured.terminal.search : findInScrollback, findInFrame;
import pured.terminal.frame : TerminalFrame;
import pured.terminal.hyperlink : HyperlinkRange, scanLineForLinks;
import std.algorithm : min;
import std.stdio : writeln;

alias TerminalCell = TerminalEmulator.TerminalCell;

TerminalCell[] makeLine(string text, size_t cols) {
    TerminalCell[] line;
    line.length = cols;
    foreach (i; 0 .. cols) {
        line[i] = TerminalCell.init;
    }
    size_t limit = min(text.length, cols);
    foreach (i; 0 .. limit) {
        line[i].ch = text[i];
    }
    return line;
}

void main() {
    auto sb = new ScrollbackBuffer();
    assert(sb.initialize(8, 4));
    sb.pushLine(makeLine("hello", 8));
    sb.pushLine(makeLine("world", 8));
    sb.pushLine(makeLine("hello", 8));

    auto hits = findInScrollback(sb, "lo");
    assert(hits.length >= 2);
    assert(hits[0].line == 0);
    assert(hits[0].column == 3);

    TerminalFrame frame;
    frame.ensureSize(8, 2);
    foreach (i; 0 .. cast(size_t)frame.cells.length) {
        frame.cells[i] = TerminalCell.init;
    }
    foreach (i; 0 .. 3) {
        frame.cells[i].ch = "abc"[i];
    }
    foreach (i; 0 .. 3) {
        frame.cells[8 + 2 + i].ch = "abc"[i];
    }
    auto frameHits = findInFrame(frame, "abc", 10);
    assert(frameHits.length == 2);
    assert(frameHits[0].line == 10);
    assert(frameHits[0].column == 0);
    assert(frameHits[1].line == 11);
    assert(frameHits[1].column == 2);

    HyperlinkRange[] ranges;
    size_t count = 0;
    char[] scratch;
    auto linkLine = makeLine("https://example.com", 32);
    scanLineForLinks(linkLine, 0, ranges, count, scratch);
    assert(count == 1);
    assert(ranges[0].startCol == 0);
    assert(ranges[0].url == "https://example.com");

    sb.terminate();
    writeln("Pure D headless tests passed.");
}
