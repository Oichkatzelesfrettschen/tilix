/**
 * Crash recovery snapshot support.
 *
 * Persists the visible terminal frame to a binary snapshot on disk and
 * restores it on the next launch (best-effort).
 */
module pured.recovery;

version (PURE_D_BACKEND):

import arsd.terminalemulator : TerminalEmulator;
import pured.terminal.frame : TerminalFrame;
import std.file : exists, remove;
import std.path : buildPath;
import std.process : environment;
import std.stdio : File;

alias TerminalCell = TerminalEmulator.TerminalCell;

enum uint SNAPSHOT_MAGIC = 0x54584C54; // "TLXT"
enum ushort SNAPSHOT_VERSION = 1;

struct SnapshotHeader {
    uint magic;
    ushort formatVersion;
    ushort reserved;
    int cols;
    int rows;
    int cursorCol;
    int cursorRow;
    int scrollOffset;
    ulong sequence;
    ulong cellCount;
}

string defaultSnapshotPath() {
    string runtimeDir = environment.get("XDG_RUNTIME_DIR", "");
    if (runtimeDir.length == 0) {
        runtimeDir = "/tmp";
    }
    return buildPath(runtimeDir, "tilix-pure.snapshot");
}

bool saveSnapshot(ref TerminalFrame frame, int scrollOffset,
        string path = null) {
    if (frame.cols <= 0 || frame.rows <= 0) {
        return false;
    }
    string target = (path is null || path.length == 0)
        ? defaultSnapshotPath()
        : path;
    if (frame.cells.length == 0) {
        return false;
    }

    SnapshotHeader header;
    header.magic = SNAPSHOT_MAGIC;
    header.formatVersion = SNAPSHOT_VERSION;
    header.cols = frame.cols;
    header.rows = frame.rows;
    header.cursorCol = frame.cursorCol;
    header.cursorRow = frame.cursorRow;
    header.scrollOffset = scrollOffset;
    header.sequence = frame.sequence;
    header.cellCount = frame.cells.length;

    auto file = File(target, "wb");
    auto headerBytes = (cast(const(ubyte)*) &header)[0 .. header.sizeof];
    file.rawWrite(headerBytes);
    file.rawWrite(cast(const(ubyte)[]) frame.cells);
    file.flush();
    return true;
}

bool loadSnapshot(ref TerminalFrame frame, out int scrollOffset,
        string path = null) {
    scrollOffset = 0;
    string target = (path is null || path.length == 0)
        ? defaultSnapshotPath()
        : path;
    if (!exists(target)) {
        return false;
    }

    auto file = File(target, "rb");
    SnapshotHeader header;
    auto headerSlice = (cast(ubyte*) &header)[0 .. header.sizeof];
    auto readHeader = file.rawRead(headerSlice);
    if (readHeader.length != headerSlice.length) {
        return false;
    }
    if (header.magic != SNAPSHOT_MAGIC || header.formatVersion != SNAPSHOT_VERSION) {
        return false;
    }
    if (header.cols <= 0 || header.rows <= 0) {
        return false;
    }
    if (header.cellCount != cast(ulong)(header.cols * header.rows)) {
        return false;
    }

    frame.ensureSize(header.cols, header.rows);
    auto cellBytes = cast(ubyte[]) frame.cells;
    auto readCells = file.rawRead(cellBytes);
    if (readCells.length != cellBytes.length) {
        return false;
    }
    frame.cursorCol = header.cursorCol;
    frame.cursorRow = header.cursorRow;
    frame.sequence = header.sequence;
    scrollOffset = header.scrollOffset;
    return true;
}

void clearSnapshot(string path = null) {
    string target = (path is null || path.length == 0)
        ? defaultSnapshotPath()
        : path;
    if (exists(target)) {
        remove(target);
    }
}
