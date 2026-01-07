module bench_scrollback_search;

version (PURE_D_BACKEND):

import arsd.terminalemulator : TerminalEmulator;
import pured.terminal.scrollback_buffer : ScrollbackBuffer;
import pured.terminal.search : findInScrollback;
import std.algorithm : min;
import std.conv : to;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.getopt : getopt;
import std.stdio : writeln;

alias TerminalCell = TerminalEmulator.TerminalCell;

TerminalCell[] makeLine(dchar fillChar, size_t cols) {
    TerminalCell[] line;
    line.length = cols;
    foreach (i; 0 .. cols) {
        line[i] = TerminalCell.init;
        line[i].ch = fillChar;
    }
    return line;
}

void main(string[] args) {
    size_t cols = 120;
    size_t lines = 20000;
    string needle = "ERROR";
    size_t matchEvery = 50;

    getopt(args,
        "cols", &cols,
        "lines", &lines,
        "needle", &needle,
        "matchEvery", &matchEvery);

    auto sb = new ScrollbackBuffer();
    if (!sb.initialize(cols, lines)) {
        writeln("scrollback init failed");
        return;
    }

    auto baseLine = makeLine('A', cols);
    auto matchLine = baseLine.dup;
    size_t insertAt = cols > needle.length ? (cols - needle.length) / 2 : 0;
    size_t copyLen = min(needle.length, cols - insertAt);
    foreach (i; 0 .. copyLen) {
        matchLine[insertAt + i].ch = needle[i];
    }

    foreach (i; 0 .. lines) {
        if (matchEvery != 0 && i % matchEvery == 0) {
            sb.pushLine(matchLine);
        } else {
            sb.pushLine(baseLine);
        }
    }

    auto sw = StopWatch(AutoStart.yes);
    auto hits = findInScrollback(sb, needle, lines);
    sw.stop();

    size_t expectedHits = 0;
    if (matchEvery != 0) {
        expectedHits = (lines + matchEvery - 1) / matchEvery;
    }
    assert(hits.length == expectedHits);

    double elapsedSec = sw.peek.total!"usecs"() / 1_000_000.0;
    double bytesScanned = cast(double)(lines * cols);
    double mb = bytesScanned / (1024.0 * 1024.0);
    double mbps = elapsedSec > 0.0 ? mb / elapsedSec : 0.0;

    writeln("Scrollback search benchmark");
    writeln("  lines: ", lines, " cols: ", cols,
        " needle: '", needle, "' matchEvery: ", matchEvery);
    writeln("  hits: ", hits.length, " elapsed: ", elapsedSec, "s");
    writeln("  approx MB scanned: ", mb, " throughput: ", mbps, " MB/s");

    sb.terminate();
}
