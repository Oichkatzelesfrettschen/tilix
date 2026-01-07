module headless_tests;

version (PURE_D_BACKEND):

import arsd.terminalemulator : TerminalEmulator;
import pured.terminal.scrollback_buffer : ScrollbackBuffer;
import pured.terminal.search : findInScrollback, findInFrame;
import pured.terminal.frame : TerminalFrame;
import pured.terminal.hyperlink : HyperlinkRange, scanLineForLinks;
import pured.terminal.selection : Selection, SelectionType;
import pured.scenegraph : SceneGraph, SplitOrientation, Viewport;
import pured.recovery : saveSnapshot, loadSnapshot, clearSnapshot;
import pured.config : SplitLayoutConfig, SplitLayoutNode, sanitizeSplitLayout;
import pured.platform.wayland.primary_selection.bridge : WaylandPrimarySelectionBridge;
import pured.platform.input : parseKeyChord, matchKeyChord;
import bindbc.glfw : GLFW_KEY_F, GLFW_MOD_CONTROL, GLFW_MOD_SHIFT;
import std.algorithm : min;
import std.path : buildPath;
import std.process : environment;
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

    string[] lines = ["hello world", "alpha beta"];
    dchar getChar(int col, int row) {
        if (row < 0 || row >= cast(int)lines.length) {
            return 0;
        }
        auto line = lines[row];
        if (col < 0 || col >= cast(int)line.length) {
            return 0;
        }
        return line[col];
    }
    auto sel = new Selection(&getChar);
    sel.start(1, 0, SelectionType.word);
    sel.finish();
    assert(sel.hasSelection);
    assert(sel.getSelectedText(&getChar, 16) == "hello");
    sel.start(7, 0, SelectionType.word);
    sel.finish();
    assert(sel.getSelectedText(&getChar, 16) == "world");
    sel.start(0, 1, SelectionType.line);
    sel.finish();
    assert(sel.getSelectedText(&getChar, 16) == "alpha beta");

    SceneGraph scene = new SceneGraph();
    auto rightPane = scene.splitLeaf(0, SplitOrientation.vertical, 0.5f);
    assert(rightPane >= 0);
    Viewport[] viewports;
    scene.computeViewports(0, 0, 100, 40, viewports);
    assert(viewports.length == 2);
    int leftWidth = viewports[0].paneId == 0 ? viewports[0].width : viewports[1].width;
    int rightWidth = viewports[0].paneId == 0 ? viewports[1].width : viewports[0].width;
    assert(leftWidth == 50);
    assert(rightWidth == 50);
    assert(scene.adjustSplitForPane(0, SplitOrientation.vertical, 0.2f));
    scene.computeViewports(0, 0, 100, 40, viewports);
    leftWidth = viewports[0].paneId == 0 ? viewports[0].width : viewports[1].width;
    rightWidth = viewports[0].paneId == 0 ? viewports[1].width : viewports[0].width;
    assert(leftWidth > rightWidth);
    assert(scene.setSplitRatioForPane(0, SplitOrientation.vertical, 0.7f));
    scene.computeViewports(0, 0, 100, 40, viewports);
    leftWidth = viewports[0].paneId == 0 ? viewports[0].width : viewports[1].width;
    assert(leftWidth >= 69 && leftWidth <= 71);

    SceneGraph tabScene = new SceneGraph(10);
    auto tabPane = tabScene.splitLeafWithIds(10, SplitOrientation.horizontal, 0.4f, 11, 12);
    assert(tabPane == 12);
    Viewport[] tabViewports;
    tabScene.computeViewports(0, 0, 100, 40, tabViewports);
    assert(tabViewports.length == 2);
    bool has10 = false;
    bool has12 = false;
    foreach (vp; tabViewports) {
        if (vp.paneId == 10) has10 = true;
        if (vp.paneId == 12) has12 = true;
    }
    assert(has10 && has12);

    SplitLayoutConfig layout;
    layout.rootPaneId = 1;
    layout.activePaneId = 1;
    SplitLayoutNode rootNode;
    rootNode.paneId = 1;
    rootNode.first = 0;
    rootNode.second = 2;
    rootNode.orientation = "vertical";
    rootNode.splitRatio = 0.5f;
    SplitLayoutNode leftNode;
    leftNode.paneId = 0;
    leftNode.first = -1;
    leftNode.second = -1;
    SplitLayoutNode rightNode;
    rightNode.paneId = 2;
    rightNode.first = -1;
    rightNode.second = -1;
    layout.nodes = [rootNode, leftNode, rightNode];
    auto sanitized = sanitizeSplitLayout(layout);
    assert(sanitized.activePaneId == 0 || sanitized.activePaneId == 2);

    TerminalFrame snapshot;
    snapshot.ensureSize(4, 2);
    foreach (i; 0 .. cast(size_t)snapshot.cells.length) {
        snapshot.cells[i] = TerminalCell.init;
    }
    snapshot.cells[0].ch = 'A';
    snapshot.cells[5].ch = 'B';
    snapshot.cursorCol = 1;
    snapshot.cursorRow = 1;
    snapshot.sequence = 42;
    int expectedOffset = 3;
    string runtimeDir = environment.get("XDG_RUNTIME_DIR", "");
    if (runtimeDir.length == 0) {
        runtimeDir = "/tmp";
    }
    auto snapshotPath = buildPath(runtimeDir, "tilix-pure.snapshot.test");
    clearSnapshot(snapshotPath);
    assert(saveSnapshot(snapshot, expectedOffset, snapshotPath));
    TerminalFrame restored;
    int restoredOffset = 0;
    assert(loadSnapshot(restored, restoredOffset, snapshotPath));
    assert(restoredOffset == expectedOffset);
    assert(restored.cursorCol == snapshot.cursorCol);
    assert(restored.cursorRow == snapshot.cursorRow);
    assert(restored.sequence == snapshot.sequence);
    assert(restored.cells.length == snapshot.cells.length);
    assert(restored.cells[0].ch == 'A');
    assert(restored.cells[5].ch == 'B');
    clearSnapshot(snapshotPath);

    bool hasWayland = environment.get("WAYLAND_DISPLAY", "").length != 0;
    auto bridge = new WaylandPrimarySelectionBridge();
    if (!hasWayland) {
        assert(!bridge.available);
        assert(bridge.requestPrimary().length == 0);
        bridge.setPrimary("test");
    }

    auto findChord = parseKeyChord("Ctrl+Shift+F");
    assert(findChord.valid);
    assert(matchKeyChord(findChord, GLFW_KEY_F, GLFW_MOD_CONTROL | GLFW_MOD_SHIFT));
    auto badChord = parseKeyChord("Ctrl+?");
    assert(!badChord.valid);

    sb.terminate();
    writeln("Pure D headless tests passed.");
}
