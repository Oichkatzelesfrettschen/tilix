/**
 * Pure D Terminal Entry Point
 *
 * Main application entry for the Pure D terminal backend using GLFW/OpenGL.
 * Integrates PTY management and terminal emulation for Super Phase 6.1.
 *
 * Build: dub build --config=pure-d
 * Run: ./build/pure/tilix-pure
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.main;

version (PURE_D_BACKEND):

import pured.window;
import pured.context;
import pured.emulator;
import pured.session : TerminalSession;
import pured.renderer;
import pured.config : PureDConfig, ThemeConfig, resolveTheme, loadConfig,
    defaultConfigPath, saveSplitLayout;
import pured.theme_importer;
import pured.platform.input;
import pured.platform.clipboard;
import pured.terminal.frame : TerminalFrame;
import pured.terminal.selection;
import pured.terminal.scrollback;
import pured.terminal.search : SearchHit, SearchRange, findInScrollback, findInFrame;
import pured.terminal.hyperlink : HyperlinkRange, scanLineForLinks;
import pured.ipc.server : IpcServer, IpcCommand, IpcCommandType;
import pured.recovery : defaultSnapshotPath, saveSnapshot, loadSnapshot;
import pured.scenegraph : SceneGraph, Viewport, SplitOrientation;
import arsd.terminalemulator : TerminalEmulator;
import std.stdio : stderr, writefln, writeln;
import std.string : strip, toLower;
import std.utf : byDchar, toUTF8;
import std.math : pow;
import std.algorithm : clamp;
import std.process : spawnProcess;
import std.path : buildPath;
import std.process : environment;
import std.conv : to;
import std.format : format;
import core.atomic : atomicLoad, atomicStore, MemoryOrder;
import core.thread : Thread;
import core.time : MonoTime, dur;
import core.sync.mutex : Mutex;
import std.datetime : SysTime;
import std.file : exists, timeLastModified, thisExePath;
import bindbc.glfw;

private class PaneState {
public:
    TerminalSession session;
    ScrollbackViewport scrollback;
    Selection selection;
    ClickDetector clickDetector;
    size_t lastScrollbackCount;
    int lastScrollbackOffset = int.min;
    int cols;
    int rows;
    string shellTitle;
}

private struct SplitDragState {
    bool active;
    SplitOrientation orientation;
    int paneId;
    double origin;
    double span;
}

private struct TabState {
    SceneGraph scene;
    Viewport[] viewports;
    int activePaneId = -1;
    string title;
}

private struct KeybindingSet {
    KeyChord closeWindow;
    KeyChord newWindow;
    KeyChord newTab;
    KeyChord closeTab;
    KeyChord splitVertical;
    KeyChord splitHorizontal;
    KeyChord resizeLeft;
    KeyChord resizeRight;
    KeyChord resizeUp;
    KeyChord resizeDown;
    KeyChord focusNextPane;
    KeyChord focusPrevPane;
    KeyChord nextTab;
    KeyChord prevTab;
    KeyChord find;
    KeyChord findNext;
    KeyChord findPrev;
    KeyChord copy;
    KeyChord paste;
    KeyChord pasteSelection;
    KeyChord zoomIn;
    KeyChord zoomOut;
    KeyChord zoomReset;
    KeyChord fullscreen;
    KeyChord scrollPageUp;
    KeyChord scrollPageDown;
    KeyChord scrollTop;
    KeyChord scrollBottom;
}

private class SessionCallbacks : ITerminalCallbacks {
private:
    PureDTerminal _owner;
    int _paneId;

public:
    this(PureDTerminal owner, int paneId) {
        _owner = owner;
        _paneId = paneId;
    }

    override void onTitleChanged(string title) {
        _owner.onPaneTitleChanged(_paneId, title);
    }

    override void onSendToApplication(scope const(void)[] data) {
        _owner.onPaneSendToApplication(_paneId, data);
    }

    override void onBell() {
        _owner.onPaneBell(_paneId);
    }

    override void onRequestExit() {
        _owner.onPaneRequestExit(_paneId);
    }

    override void onCursorStyleChanged(TerminalEmulator.CursorStyle style) {
        _owner.onPaneCursorStyleChanged(_paneId, style);
    }

    override void onCopyToClipboard(string text) {
        _owner.onCopyToClipboard(text);
    }

    override void onCopyToPrimary(string text) {
        _owner.onCopyToPrimary(text);
    }

    override string onPasteFromClipboard() {
        return _owner.onPasteFromClipboard();
    }

    override string onPasteFromPrimary() {
        return _owner.onPasteFromPrimary();
    }
}

/**
 * Pure D Terminal Application
 *
 * Main class coordinating window, rendering, PTY, and terminal emulation.
 */
class PureDTerminal : ITerminalCallbacks {
private:
    GLFWWindow _window;
    GLContext _glContext;
    CellRenderer _renderer;
    PaneState[int] _panes;

    // Input handling
    InputHandler _inputHandler;
    ClipboardBridge _clipboard;
    KeybindingSet _keybindings;
    size_t _scrollbackMaxLines = 200_000;

    // Mouse state
    double _mouseX = 0;
    double _mouseY = 0;
    int _mouseButtons = 0;
    int _lastKeyMods = 0;
    SplitDragState _splitDrag;

    // Frame timing
    MonoTime _lastFrameTime;
    long _frameCount;
    long _totalFrameCount;
    double _fps;
    double _frameTimeAccum;
    ulong _lastFrameSequence;
    double _latencyMs;
    double _latencyAvgMs;
    size_t _lastPtyBytes;
    double _ptyMbps;

    // Terminal state
    int _cols = 80;
    int _rows = 24;
    int _cellWidth = 10;
    int _cellHeight = 20;

    // Title synchronization
    Mutex _titleMutex;

    // Window title from shell
    shared bool _exitRequested;
    float _contentScale = 1.0f;
    PureDConfig _config;
    Thread _configWatcher;
    Mutex _configMutex;
    PureDConfig _pendingConfig;
    shared bool _configPending;
    string _configPath;
    int _baseFontSize;
    float _bellIntensity;
    float _bellDecayRate = 4.0f;
    shared bool _bellTriggered;
    CursorRenderStyle _cursorStyle = CursorRenderStyle.block;
    TerminalEmulator.CursorStyle _rawCursorStyle = TerminalEmulator.CursorStyle.block;
    bool _cursorStyleOverride;
    float _cursorThickness;
    float[4] _selectionBg = [0.2f, 0.6f, 0.8f, 1.0f];
    float[4] _selectionFg = [1.0f, 1.0f, 1.0f, 1.0f];
    float[4] _searchBg = [0.85f, 0.7f, 0.2f, 1.0f];
    float[4] _searchFg = [0.0f, 0.0f, 0.0f, 1.0f];
    float[4] _linkFg = [0.2f, 0.6f, 1.0f, 1.0f];
    bool _quakeMode;
    float _quakeHeight;
    string _snapshotPath;
    MonoTime _lastSnapshotTime;

    TabState[] _tabs;
    int _activeTabIndex = -1;
    int _nextPaneId = 1;
    SceneGraph _scene;
    Viewport[] _viewports;
    int _activePaneId;

    IpcServer _ipcServer;

    // Search state (scrollback + screen)
    string _searchQuery;
    SearchHit[] _searchHits;
    SearchRange[] _searchRanges;
    int _searchIndex;
    size_t _searchMatchLen;
    size_t _searchGeneration;
    size_t _searchRangesGeneration;
    size_t _searchRangesScrollbackCount;
    int _searchRangesOffset = int.min;
    bool _searchPromptActive;
    string _searchPromptBuffer;
    dchar[] _searchPromptGlyphs;
    string[] _searchHistory;
    int _searchHistoryIndex = -1;
    string _searchPromptDraft;

    HyperlinkRange[] _hyperlinks;
    char[] _hyperlinkScratch;
    ulong _lastHyperlinkSequence;
    int _lastHyperlinkOffset = int.min;
    HyperlinkRange _hoverLink;
    bool _hoverLinkActive;

public:
    /**
     * Initialize the terminal application.
     *
     * Returns: true if initialization succeeded
     */
    bool initialize() {
        _config = loadConfig();
        _configMutex = new Mutex();
        _configPath = defaultConfigPath();
        _baseFontSize = _config.fontSize;
        _selectionBg = resolveSelectionBg(_config);
        _selectionFg = resolveSelectionFg(_config, _selectionBg);
        _searchBg = resolveSearchBg(_config);
        _searchFg = resolveSearchFg(_config, _searchBg);
        _linkFg = resolveLinkFg(_config);
        refreshKeybindings();
        _quakeMode = _config.quakeMode;
        _quakeHeight = _config.quakeHeight;
        int windowWidth = _config.windowWidth;
        int windowHeight = _config.windowHeight;

        // Create window
        _window = new GLFWWindow();
        if (!_window.initialize(windowWidth, windowHeight,
                "Tilix Pure D - Super Phase 6.1",
                _config.swapInterval)) {
            stderr.writefln("Error: Failed to initialize window");
            return false;
        }
        _clipboard = new ClipboardBridge(_window.handle);

        // Initialize OpenGL context
        _glContext = new GLContext();
        if (!_glContext.initialize()) {
            stderr.writefln("Error: Failed to initialize GL context");
            _window.terminate();
            return false;
        }

        // Initialize cell renderer (includes font atlas)
        _renderer = new CellRenderer();
        if (!_renderer.initialize()) {
            stderr.writefln("Error: Failed to initialize cell renderer");
            _glContext.terminate();
            _window.terminate();
            return false;
        }

        auto themeConfig = _config.theme;
        if (_config.themePath.length > 0) {
            ThemeConfig importedTheme;
            if (loadThemeFromFile(_config.themePath, _config.themeFormat, importedTheme)) {
                themeConfig = importedTheme;
            } else {
                stderr.writefln("Warning: Failed to load theme file %s", _config.themePath);
            }
        }
        _renderer.setTheme(resolveTheme(themeConfig));
        if (_config.fontPath.length > 0 || _config.fontSize != 16) {
            if (!_renderer.reloadFont(_config.fontPath, _config.fontSize)) {
                stderr.writefln("Warning: Failed to apply Pure D config font settings");
            }
        }

        // Get cell dimensions from font atlas
        _cellWidth = _renderer.cellWidth;
        _cellHeight = _renderer.cellHeight;

        applyQuakeMode();

        // Set initial viewport and calculate terminal size
        int width, height;
        _window.getFramebufferSize(width, height);
        ensureTabs();
        _activePaneId = -1;
        auto tab = activeTab();
        if (tab !is null) {
            _scene = tab.scene;
        }
        if (_scene is null) {
            _scene = new SceneGraph(0);
        }
        if (_config.splitLayout.nodes.length > 0) {
            if (_scene.applyLayoutConfig(_config.splitLayout)) {
                _activePaneId = _config.splitLayout.activePaneId;
            }
        }
        syncNextPaneIdFromScene();
        updateViewports(false);
        _glContext.setViewport(width, height);
        _renderer.setViewport(width, height);

        // Create terminal session
        _inputHandler = new InputHandler();
        _scrollbackMaxLines = _config.scrollbackMaxLines;
        _snapshotPath = defaultSnapshotPath();

        auto active = activePane();
        if (active is null) {
            _window.terminate();
            return false;
        }
        _cols = active.cols;
        _rows = active.rows;
        _rawCursorStyle = active.session.emulator.cursorStyle;
        refreshCursorSettings();
        initializeFrames(active.session, _cols, _rows);

        // Attempt crash recovery snapshot restore before PTY starts streaming.
        int recoveredOffset = 0;
        TerminalFrame snapshot;
        if (active !is null && loadSnapshot(snapshot, recoveredOffset, _snapshotPath)) {
            if (snapshot.cols == active.cols && snapshot.rows == active.rows) {
                active.session.frames.writeBuffer = snapshot;
                active.session.frames.publish();
                active.session.frames.consume();
                active.scrollback.scrollTo(recoveredOffset);
            }
        }

        _titleMutex = new Mutex();
        startAllPanes();
        updateWindowTitle();

        // Set up callbacks
        _window.onResize(&onResize);
        _window.onKey(&onKey);
        _window.onChar(&onChar);
        _window.onMouseButton(&onMouseButton);
        _window.onScroll(&onScroll);
        _window.onCursorPos(&onCursorPos);
        _window.onFocus(&onFocusChanged);
        _window.onContentScale(&onContentScale);

        float scaleX;
        float scaleY;
        _window.getContentScale(scaleX, scaleY);
        applyContentScale(scaleX > scaleY ? scaleX : scaleY);

        // Initialize timing
        _lastFrameTime = MonoTime.currTime;
        _frameCount = 0;
        _totalFrameCount = 0;
        _fps = 0.0;
        _frameTimeAccum = 0.0;
        writeln("Tilix Pure D Backend initialized successfully");
        writefln("  Target: 320Hz+ framerate, <1ms input latency");
        writefln("  Window: %dx%d", width, height);
        writefln("  Terminal: %dx%d cells", _cols, _rows);
        auto infoPane = activePane();
        if (infoPane !is null && infoPane.session !is null) {
            writefln("  PTY: master fd=%d", infoPane.session.pty.masterFd);
        }

        startConfigWatcher();
        startIpcServer();

        return true;
    }

    /**
     * Run the main loop.
     */
    void run() {
        while (!_window.shouldClose) {
            // Calculate frame timing
            auto now = MonoTime.currTime;
            auto deltaTime = (now - _lastFrameTime).total!"usecs" / 1_000_000.0;
            _lastFrameTime = now;

            // Update FPS counter
            updateFPS(deltaTime);
            updateBell(deltaTime);

            // Poll input events
            _window.pollEvents();
            if (_clipboard !is null) {
                _clipboard.pump();
            }

            applyPendingConfig();
            applyIpcCommands();

            // Check PTY child exit
            checkPtyExit();

            if (atomicLoad!(MemoryOrder.raw)(_exitRequested)) {
                _window.close();
            }

            // Render frame
            render();

            // Swap buffers
            _window.swapBuffers();

            _frameCount++;
            _totalFrameCount++;
        }
    }

    void startConfigWatcher() {
        if (_configWatcher !is null) {
            return;
        }
        _configWatcher = new Thread({
            bool hadFile = exists(_configPath);
            SysTime lastMod = hadFile ? timeLastModified(_configPath) : SysTime.init;
            while (!atomicLoad!(MemoryOrder.raw)(_exitRequested)) {
                bool fileExists = exists(_configPath);
                if (fileExists) {
                    auto mod = timeLastModified(_configPath);
                    if (!hadFile || mod > lastMod) {
                        hadFile = true;
                        lastMod = mod;
                        queueConfig(loadConfig(_configPath));
                    }
                } else if (hadFile) {
                    hadFile = false;
                    queueConfig(loadConfig(_configPath));
                }
                Thread.sleep(dur!"msecs"(250));
            }
        });
        _configWatcher.isDaemon = true;
        _configWatcher.start();
    }

    void startIpcServer() {
        if (_ipcServer !is null) {
            return;
        }
        string runtimeDir = environment.get("XDG_RUNTIME_DIR", "");
        if (runtimeDir.length == 0) {
            runtimeDir = "/tmp";
        }
        auto socketPath = buildPath(runtimeDir, "tilix-pure.sock");
        _ipcServer = new IpcServer(socketPath);
        _ipcServer.start();
        writefln("IPC: listening on %s", socketPath);
    }

    void applyQuakeMode() {
        if (_window is null) {
            return;
        }

        if (!_quakeMode) {
            _window.setDecorated(true);
            _window.setFloating(false);
            _window.setSize(_config.windowWidth, _config.windowHeight);
            return;
        }

        int xpos;
        int ypos;
        int width;
        int height;
        if (!_window.getWorkArea(xpos, ypos, width, height)) {
            _window.getSize(width, height);
            xpos = 0;
            ypos = 0;
        }

        int targetHeight = cast(int)(height * _quakeHeight);
        if (targetHeight < _cellHeight) {
            targetHeight = _cellHeight;
        }

        _window.setDecorated(false);
        _window.setFloating(true);
        _window.setSize(width, targetHeight);
        _window.setPosition(xpos, ypos);
    }

    void updateViewports(bool startNewSessions = true) {
        ensureTabs();
        auto tab = activeTab();
        if (tab is null) {
            return;
        }
        if (tab.scene is null) {
            tab.scene = new SceneGraph(allocatePaneId());
            tab.activePaneId = tab.scene.root.paneId;
        }
        _scene = tab.scene;
        _viewports = tab.viewports;
        _activePaneId = tab.activePaneId;
        int fbWidth;
        int fbHeight;
        _window.getFramebufferSize(fbWidth, fbHeight);
        _scene.computeViewports(0, 0, fbWidth, fbHeight, _viewports);
        if (_viewports.length != 0 && _activePaneId < 0) {
            _activePaneId = _viewports[0].paneId;
        }
        syncPanesForViewports(startNewSessions);
        syncActiveTabState();
    }

    PaneState paneForId(int paneId) {
        auto found = paneId in _panes;
        return found is null ? null : *found;
    }

    PaneState activePane() {
        return paneForId(_activePaneId);
    }

    TabState* activeTab() {
        if (_activeTabIndex < 0 || _activeTabIndex >= cast(int)_tabs.length) {
            return null;
        }
        return &_tabs[_activeTabIndex];
    }

    void ensureTabs() {
        if (_tabs.length != 0) {
            return;
        }
        TabState tab;
        tab.scene = new SceneGraph(0);
        tab.activePaneId = -1;
        tab.title = "Tab 1";
        _tabs ~= tab;
        _activeTabIndex = 0;
        _scene = tab.scene;
        _viewports = tab.viewports;
        _activePaneId = tab.activePaneId;
    }

    void syncActiveTabState() {
        auto tab = activeTab();
        if (tab is null) {
            return;
        }
        tab.viewports = _viewports;
        tab.activePaneId = _activePaneId;
        tab.scene = _scene;
    }

    int allocatePaneId() {
        int id = _nextPaneId;
        _nextPaneId += 1;
        return id;
    }

    void syncNextPaneIdFromScene() {
        if (_scene is null) {
            return;
        }
        if (_scene.nextPaneId > _nextPaneId) {
            _nextPaneId = _scene.nextPaneId;
        }
    }

    bool paneInAnyTab(int paneId) {
        foreach (tab; _tabs) {
            if (tab.scene !is null && tab.scene.hasPane(paneId)) {
                return true;
            }
        }
        return false;
    }

    int tabIndexForPane(int paneId) {
        foreach (i, tab; _tabs) {
            if (tab.scene !is null && tab.scene.hasPane(paneId)) {
                return cast(int)i;
            }
        }
        return -1;
    }

    void setActivePane(int paneId, bool force = false) {
        if (!force && paneId == _activePaneId) {
            return;
        }
        _activePaneId = paneId;
        auto tab = activeTab();
        if (tab !is null) {
            tab.activePaneId = paneId;
        }
        auto pane = activePane();
        if (pane !is null) {
            _cols = pane.cols;
            _rows = pane.rows;
            if (pane.session !is null && pane.session.parserWorker !is null) {
                _lastPtyBytes = pane.session.parserWorker.totalBytesProcessed();
            } else {
                _lastPtyBytes = 0;
            }
            if (pane.session !is null && pane.session.emulator !is null) {
                _rawCursorStyle = pane.session.emulator.cursorStyle;
                if (!_cursorStyleOverride) {
                    _cursorStyle = mapCursorStyle(_rawCursorStyle);
                }
            }
        }
        resetSearchAndLinks();
    }

    void focusAdjacentPane(int direction) {
        if (_viewports.length == 0) {
            return;
        }
        int count = cast(int)_viewports.length;
        int currentIndex = -1;
        foreach (i, vp; _viewports) {
            if (vp.paneId == _activePaneId) {
                currentIndex = cast(int)i;
                break;
            }
        }
        int delta = direction >= 0 ? 1 : -1;
        int targetIndex = currentIndex < 0
            ? 0
            : (currentIndex + delta + count) % count;
        setActivePane(_viewports[targetIndex].paneId);
    }

    void createTab() {
        TabState tab;
        int rootPaneId = allocatePaneId();
        tab.scene = new SceneGraph(rootPaneId);
        tab.activePaneId = rootPaneId;
        tab.title = "Tab " ~ to!string(_tabs.length + 1);
        _tabs ~= tab;
        switchTab(cast(int)_tabs.length - 1);
    }

    void loadTab(int index) {
        _activeTabIndex = index;
        auto tab = activeTab();
        if (tab is null) {
            return;
        }
        _scene = tab.scene;
        _viewports = tab.viewports;
        _activePaneId = tab.activePaneId;
        updateViewports();
        resetSearchAndLinks();
        updateWindowTitle();
    }

    void switchTab(int index) {
        if (index < 0 || index >= cast(int)_tabs.length) {
            return;
        }
        syncActiveTabState();
        loadTab(index);
    }

    void closeTab(int index) {
        if (index < 0 || index >= cast(int)_tabs.length) {
            return;
        }
        if (_tabs.length == 1) {
            _window.close();
            return;
        }
        syncActiveTabState();
        auto closing = _tabs[index];
        int[] paneIds;
        if (closing.scene !is null) {
            closing.scene.collectLeafPaneIds(paneIds);
        }
        foreach (paneId; paneIds) {
            auto pane = paneForId(paneId);
            if (pane !is null && pane.session !is null) {
                pane.session.stop();
            }
            _panes.remove(paneId);
        }
        _tabs = _tabs[0 .. index] ~ _tabs[index + 1 .. $];
        if (_activeTabIndex > index) {
            _activeTabIndex -= 1;
        } else if (_activeTabIndex == index) {
            if (_activeTabIndex >= cast(int)_tabs.length) {
                _activeTabIndex = cast(int)_tabs.length - 1;
            }
        }
        loadTab(_activeTabIndex);
    }

    void updateWindowTitle() {
        if (_window is null) {
            return;
        }
        string title = "Tilix Pure D";
        auto tab = activeTab();
        if (tab !is null) {
            int total = cast(int)_tabs.length;
            int index = _activeTabIndex + 1;
            string tabTitle = tab.title.length != 0
                ? tab.title
                : ("Tab " ~ to!string(index));
            if (_searchPromptActive) {
                string prompt = _searchPromptBuffer.length != 0
                    ? _searchPromptBuffer
                    : "<type to search>";
                title = format("Tilix Pure D [%d/%d] Search: %s",
                    index, total, prompt);
            } else {
                title = format("Tilix Pure D [%d/%d] %s", index, total, tabTitle);
            }
        }
        _window.setTitle(title);
    }

    void refreshSearchPromptDisplay() {
        updateWindowTitle();
        if (!_searchPromptActive) {
            _searchPromptGlyphs.length = 0;
            return;
        }
        string text = "Search: " ~ _searchPromptBuffer;
        _searchPromptGlyphs.length = 0;
        foreach (dchar ch; text.byDchar) {
            _searchPromptGlyphs ~= ch;
        }
    }

    void nextTab(int delta) {
        if (_tabs.length == 0) {
            return;
        }
        int count = cast(int)_tabs.length;
        int next = (_activeTabIndex + delta) % count;
        if (next < 0) {
            next += count;
        }
        switchTab(next);
    }

    int clampScrollbackMaxLines() const {
        if (_scrollbackMaxLines > cast(size_t)int.max) {
            return int.max;
        }
        return cast(int)_scrollbackMaxLines;
    }

    PaneState ensurePane(int paneId, int cols, int rows, bool startNow = true) {
        auto found = paneId in _panes;
        if (found !is null) {
            auto pane = *found;
            resizePane(pane, cols, rows);
            return pane;
        }

        auto pane = new PaneState();
        pane.cols = cols;
        pane.rows = rows;
        pane.scrollback = new ScrollbackViewport(rows, clampScrollbackMaxLines());
        pane.selection = new Selection((col, row) => getCharAt(paneId, col, row));
        pane.clickDetector = ClickDetector.init;
        pane.lastScrollbackCount = 0;
        pane.lastScrollbackOffset = int.min;

        pane.session = new TerminalSession();
        auto callbacks = new SessionCallbacks(this, paneId);
        if (!pane.session.initialize(cols, rows, callbacks, _scrollbackMaxLines)) {
            stderr.writefln("Error: Failed to initialize session for pane %d", paneId);
            return null;
        }
        initializeFrames(pane.session, cols, rows);
        if (startNow) {
            pane.session.start();
        }
        _panes[paneId] = pane;
        return pane;
    }

    void resizePane(PaneState pane, int cols, int rows) {
        if (pane is null) {
            return;
        }
        if (pane.cols == cols && pane.rows == rows) {
            return;
        }
        pane.cols = cols;
        pane.rows = rows;
        resizeFrameBuffers(pane.session, cols, rows);
        if (pane.scrollback !is null) {
            pane.scrollback.resize(rows);
        }
        if (pane.session !is null) {
            pane.session.resize(cols, rows);
        }
        if (pane.session is null ||
            pane.session.parserWorker is null ||
            !pane.session.parserWorker.isRunning) {
            updateFrameFromEmulator(pane.session);
            pane.session.frames.publish();
            pane.session.frames.consume();
        }
    }

    void syncPanesForViewports(bool startNewSessions) {
        bool[int] activePanes;
        int maxCols = 0;
        int maxRows = 0;
        int previousActive = _activePaneId;

        foreach (vp; _viewports) {
            int cols = vp.width / _cellWidth;
            int rows = vp.height / _cellHeight;
            if (cols < 1) {
                cols = 1;
            }
            if (rows < 1) {
                rows = 1;
            }
            if (cols > maxCols) {
                maxCols = cols;
            }
            if (rows > maxRows) {
                maxRows = rows;
            }
            auto pane = ensurePane(vp.paneId, cols, rows, startNewSessions);
            if (pane !is null) {
                pane.cols = cols;
                pane.rows = rows;
                activePanes[vp.paneId] = true;
            }
        }

        int[] stale;
        foreach (paneId, pane; _panes) {
            if (!(paneId in activePanes) && !paneInAnyTab(paneId)) {
                stale ~= paneId;
            }
        }
        foreach (paneId; stale) {
            auto pane = _panes[paneId];
            if (pane !is null && pane.session !is null) {
                pane.session.stop();
            }
            _panes.remove(paneId);
        }

        if (_activePaneId >= 0 && paneForId(_activePaneId) is null && _viewports.length > 0) {
            _activePaneId = _viewports[0].paneId;
        }

        if (maxCols > 0 && maxRows > 0) {
            reserveSearchBuffers(maxCols, maxRows);
        }
        if (_renderer !is null && maxCols > 0 && maxRows > 0) {
            _renderer.prepareBuffers(maxCols, maxRows);
        }

        if (_activePaneId != previousActive) {
            setActivePane(_activePaneId, true);
        } else {
            auto active = activePane();
            if (active !is null) {
                _cols = active.cols;
                _rows = active.rows;
            }
        }
    }

    void startAllPanes() {
        foreach (paneId, pane; _panes) {
            if (pane !is null && pane.session !is null) {
                pane.session.start();
            }
        }
    }

    void reserveSearchBuffers(int cols, int rows) {
        if (cols <= 0 || rows <= 0) {
            return;
        }
        size_t maxRanges = cast(size_t)cols * cast(size_t)rows;
        reserveCapacity(_searchRanges, maxRanges);
        reserveCapacity(_hyperlinks, maxRanges);
        if (_hyperlinkScratch.length < cols) {
            _hyperlinkScratch.length = cols;
        }
    }

    private void reserveCapacity(T)(ref T[] arr, size_t capacity) {
        if (arr.length >= capacity) {
            return;
        }
        auto previous = arr.length;
        arr.length = capacity;
        arr.length = previous;
    }

    void splitActive(SplitOrientation orientation) {
        if (_scene is null) {
            _scene = new SceneGraph(allocatePaneId());
        }
        int internalId = allocatePaneId();
        int newPaneId = allocatePaneId();
        int newPane = _scene.splitLeafWithIds(_activePaneId, orientation, 0.5f,
            internalId, newPaneId);
        if (newPane < 0) {
            stderr.writefln("Split: failed to split pane %d", _activePaneId);
            return;
        }
        updateViewports();
        setActivePane(newPane);
        persistSplitLayout();
    }

    void resizeActiveSplit(SplitOrientation orientation, float delta) {
        if (_scene is null) {
            return;
        }
        if (_scene.adjustSplitForPane(_activePaneId, orientation, delta)) {
            updateViewports();
            persistSplitLayout();
        }
    }

    bool beginSplitDrag(double x, double y) {
        if (_viewports.length < 2) {
            return false;
        }
        const double threshold = 4.0;

        foreach (i; 0 .. _viewports.length) {
            auto a = _viewports[i];
            foreach (j; i + 1 .. _viewports.length) {
                auto b = _viewports[j];

                // Vertical split boundary (side-by-side)
                if (a.y == b.y && a.height == b.height) {
                    int boundaryX = -1;
                    if (a.x + a.width == b.x) {
                        boundaryX = b.x;
                    } else if (b.x + b.width == a.x) {
                        boundaryX = a.x;
                    }
                    if (boundaryX >= 0 &&
                        y >= a.y &&
                        y <= a.y + a.height &&
                        (x >= boundaryX - threshold) &&
                        (x <= boundaryX + threshold)) {
                        auto left = a.x < b.x ? a : b;
                        auto right = a.x < b.x ? b : a;
                        _splitDrag.active = true;
                        _splitDrag.orientation = SplitOrientation.vertical;
                        _splitDrag.paneId = left.paneId;
                        _splitDrag.origin = left.x;
                        _splitDrag.span = left.width + right.width;
                        return true;
                    }
                }

                // Horizontal split boundary (stacked)
                if (a.x == b.x && a.width == b.width) {
                    int boundaryY = -1;
                    if (a.y + a.height == b.y) {
                        boundaryY = b.y;
                    } else if (b.y + b.height == a.y) {
                        boundaryY = a.y;
                    }
                    if (boundaryY >= 0 &&
                        x >= a.x &&
                        x <= a.x + a.width &&
                        (y >= boundaryY - threshold) &&
                        (y <= boundaryY + threshold)) {
                        auto top = a.y < b.y ? a : b;
                        auto bottom = a.y < b.y ? b : a;
                        _splitDrag.active = true;
                        _splitDrag.orientation = SplitOrientation.horizontal;
                        _splitDrag.paneId = top.paneId;
                        _splitDrag.origin = top.y;
                        _splitDrag.span = top.height + bottom.height;
                        return true;
                    }
                }
            }
        }
        return false;
    }

    void updateSplitDrag(double x, double y) {
        if (!_splitDrag.active || _scene is null) {
            return;
        }
        double pos = _splitDrag.orientation == SplitOrientation.vertical ? x : y;
        if (_splitDrag.span <= 1.0) {
            return;
        }
        double ratio = (pos - _splitDrag.origin) / _splitDrag.span;
        if (ratio < 0.1) {
            ratio = 0.1;
        } else if (ratio > 0.9) {
            ratio = 0.9;
        }
        if (_scene.setSplitRatioForPane(_splitDrag.paneId,
                _splitDrag.orientation, cast(float)ratio)) {
            updateViewports();
        }
    }

    void endSplitDrag() {
        _splitDrag.active = false;
        persistSplitLayout();
    }

    void persistSplitLayout() {
        if (_configPath.length == 0 || _scene is null) {
            return;
        }
        auto layout = _scene.toLayoutConfig();
        layout.activePaneId = resolveActivePaneId(layout.rootPaneId);
        if (!saveSplitLayout(layout, _configPath)) {
            stderr.writefln("Warning: Failed to persist split layout to %s", _configPath);
        }
    }

    int resolveActivePaneId(int fallbackId) const {
        int candidate = _activePaneId;
        foreach (vp; _viewports) {
            if (vp.paneId == candidate) {
                return candidate;
            }
        }
        if (_viewports.length > 0) {
            return _viewports[0].paneId;
        }
        return fallbackId;
    }

    bool viewportAt(double x, double y, out Viewport viewport) {
        foreach (vp; _viewports) {
            if (x >= vp.x && x < vp.x + vp.width &&
                y >= vp.y && y < vp.y + vp.height) {
                viewport = vp;
                return true;
            }
        }
        return false;
    }

    void spawnNewInstance(string[] extraArgs = null) {
        string exePath;
        try {
            exePath = thisExePath();
        } catch (Exception ex) {
            stderr.writefln("IPC: failed to resolve executable path: %s", ex.msg);
            return;
        }
        if (exePath.length == 0) {
            stderr.writefln("IPC: executable path unavailable");
            return;
        }

        string[] cmd = [exePath];
        if (extraArgs !is null && extraArgs.length != 0) {
            cmd ~= extraArgs;
        }

        try {
            spawnProcess(cmd);
        } catch (Exception ex) {
            stderr.writefln("IPC: spawn failed: %s", ex.msg);
        }
    }

    void applyIpcCommands() {
        if (_ipcServer is null) {
            return;
        }
        IpcCommand cmd;
        while (_ipcServer.pollCommand(cmd)) {
            final switch (cmd.type) {
                case IpcCommandType.newTab:
                    createTab();
                    break;
                case IpcCommandType.pasteText:
                    pasteText(cmd.payload);
                    break;
                case IpcCommandType.setTitle:
                    onTitleChanged(cmd.payload);
                    break;
                case IpcCommandType.spawnProfile:
                    auto profile = strip(cmd.payload);
                    if (profile.length != 0) {
                        spawnNewInstance(["--profile", profile]);
                    } else {
                        spawnNewInstance();
                    }
                    break;
            }
        }
    }

    void queueConfig(PureDConfig cfg) {
        _configMutex.lock();
        scope(exit) _configMutex.unlock();
        _pendingConfig = cfg;
        atomicStore!(MemoryOrder.raw)(_configPending, true);
    }

    void applyPendingConfig() {
        if (!atomicLoad!(MemoryOrder.raw)(_configPending)) {
            return;
        }
        _configMutex.lock();
        auto cfg = _pendingConfig;
        atomicStore!(MemoryOrder.raw)(_configPending, false);
        _configMutex.unlock();
        applyConfig(cfg);
    }

    void applyConfig(PureDConfig cfg) {
        auto previous = _config;
        _config = cfg;
        _baseFontSize = _config.fontSize;
        refreshCursorSettings();
        _selectionBg = resolveSelectionBg(_config);
        _selectionFg = resolveSelectionFg(_config, _selectionBg);
        _searchBg = resolveSearchBg(_config);
        _searchFg = resolveSearchFg(_config, _searchBg);
        _linkFg = resolveLinkFg(_config);
        refreshKeybindings();
        _quakeMode = _config.quakeMode;
        _quakeHeight = _config.quakeHeight;
        applyQuakeMode();

        if (_renderer !is null) {
            auto themeConfig = _config.theme;
            if (_config.themePath.length > 0) {
                ThemeConfig importedTheme;
                if (loadThemeFromFile(_config.themePath, _config.themeFormat, importedTheme)) {
                    themeConfig = importedTheme;
                } else {
                    stderr.writefln("Warning: Failed to load theme file %s", _config.themePath);
                }
            }
            _renderer.setTheme(resolveTheme(themeConfig));
        }

        if (_window !is null && _config.swapInterval != previous.swapInterval) {
            _window.setSwapInterval(_config.swapInterval);
        }

        if (_window !is null &&
            (_config.windowWidth != previous.windowWidth ||
             _config.windowHeight != previous.windowHeight)) {
            _window.setSize(_config.windowWidth, _config.windowHeight);
        }

        if (_config.scrollbackMaxLines != previous.scrollbackMaxLines) {
            _scrollbackMaxLines = _config.scrollbackMaxLines;
            foreach (paneId, pane; _panes) {
                if (pane !is null &&
                    pane.session !is null &&
                    pane.session.parserWorker !is null) {
                    pane.session.parserWorker.setScrollbackMaxLines(_scrollbackMaxLines);
                }
            }
        }

        if (_config.splitLayout.nodes.length > 0 && _scene !is null) {
            if (_scene.applyLayoutConfig(_config.splitLayout)) {
                _activePaneId = _config.splitLayout.activePaneId;
                syncNextPaneIdFromScene();
                updateViewports();
            }
        }

        bool fontChanged = _config.fontPath != previous.fontPath ||
            _config.fontSize != previous.fontSize;
        if (fontChanged && _renderer !is null) {
            if (!_renderer.reloadFont(_config.fontPath, _config.fontSize)) {
                stderr.writefln("Warning: Failed to apply Pure D config font settings");
            }
            _cellWidth = _renderer.cellWidth;
            _cellHeight = _renderer.cellHeight;
            int width, height;
            _window.getFramebufferSize(width, height);
            onResize(width, height);
        }
    }

    void adjustFontSize(int delta) {
        applyFontSize(_config.fontSize + delta);
    }

    void resetFontSize() {
        applyFontSize(_baseFontSize);
    }

    void applyFontSize(int targetSize) {
        int clamped = clamp(targetSize, 6, 72);
        if (clamped == _config.fontSize || _renderer is null || _window is null) {
            return;
        }
        _config.fontSize = clamped;
        if (!_renderer.reloadFont(_config.fontPath, _config.fontSize)) {
            stderr.writefln("Warning: Failed to apply Pure D font size change");
            return;
        }
        _cellWidth = _renderer.cellWidth;
        _cellHeight = _renderer.cellHeight;
        int width, height;
        _window.getFramebufferSize(width, height);
        onResize(width, height);
    }

    void resetSearchAndLinks() {
        _searchHits.length = 0;
        _searchRanges.length = 0;
        _searchIndex = 0;
        _searchGeneration++;
        _searchRangesGeneration = 0;
        _searchRangesScrollbackCount = 0;
        _searchRangesOffset = int.min;
        _searchPromptActive = false;
        _searchPromptBuffer = "";
        _hyperlinks.length = 0;
        _lastHyperlinkSequence = 0;
        _lastHyperlinkOffset = int.min;
    }

    void triggerSearch() {
        startSearchPrompt();
    }

    void startSearchPrompt() {
        string query;
        auto pane = activePane();
        if (pane is null || pane.scrollback is null) {
            return;
        }
        if (pane.selection !is null && pane.selection.hasSelection) {
            query = pane.selection.getSelectedText(
                (col, row) => getCharAt(_activePaneId, col, row),
                pane.cols);
        }
        if (query.length == 0) {
            query = _searchQuery;
        }
        _searchPromptActive = true;
        _searchPromptBuffer = query;
        _searchHistoryIndex = cast(int)_searchHistory.length;
        _searchPromptDraft = _searchPromptBuffer;
        refreshSearchPromptDisplay();
    }

    void cancelSearchPrompt() {
        _searchPromptActive = false;
        _searchPromptBuffer = "";
        _searchPromptDraft = "";
        _searchHistoryIndex = cast(int)_searchHistory.length;
        refreshSearchPromptDisplay();
    }

    void confirmSearchPrompt() {
        auto query = _searchPromptBuffer;
        _searchPromptActive = false;
        _searchPromptBuffer = "";
        _searchPromptDraft = "";
        _searchHistoryIndex = cast(int)_searchHistory.length;
        refreshSearchPromptDisplay();
        if (query.length == 0) {
            return;
        }
        executeSearch(query);
    }

    void executeSearch(string query) {
        if (query.length == 0) {
            return;
        }
        auto pane = activePane();
        if (pane is null || pane.scrollback is null) {
            return;
        }
        _searchQuery = query;
        pushSearchHistory(query);
        _searchMatchLen = countCodepoints(query);
        if (_searchMatchLen == 0) {
            _searchMatchLen = 1;
        }

        _searchHits.length = 0;
        size_t sbCount = 0;
        if (pane.session !is null &&
            pane.session.scrollbackBuffer !is null &&
            pane.session.scrollbackMutex !is null) {
            pane.session.scrollbackMutex.lock();
            sbCount = pane.session.scrollbackBuffer.lineCount;
            _searchHits = findInScrollback(pane.session.scrollbackBuffer, query, 512);
            pane.session.scrollbackMutex.unlock();
        }

        auto ref liveFrame = pane.session.frames.readBuffer;
        auto frameHits = findInFrame(liveFrame, query, sbCount, 512, _searchHits.length);
        if (frameHits.length) {
            _searchHits ~= frameHits;
        }
        _searchGeneration++;
        _searchIndex = 0;
        applySearchHit();
    }

    string encodeCodepoint(dchar codepoint) {
        dchar[1] buffer = [codepoint];
        return toUTF8(buffer[]);
    }

    string popLastCodepoint(string text) {
        if (text.length == 0) {
            return text;
        }
        size_t i = text.length - 1;
        while (i > 0 && (text[i] & 0xC0) == 0x80) {
            i--;
        }
        return text[0 .. i];
    }

    void pushSearchHistory(string query) {
        if (query.length == 0) {
            return;
        }
        if (_searchHistory.length != 0 &&
            _searchHistory[$ - 1] == query) {
            return;
        }
        _searchHistory ~= query;
        if (_searchHistory.length > 50) {
            _searchHistory = _searchHistory[$ - 50 .. $];
        }
    }

    void nextSearchHit(bool backwards) {
        if (_searchHits.length == 0) {
            if (_searchQuery.length != 0) {
                executeSearch(_searchQuery);
            }
            return;
        }
        if (backwards) {
            _searchIndex--;
        } else {
            _searchIndex++;
        }
        applySearchHit();
    }

    void applySearchHit() {
        if (_searchHits.length == 0) {
            return;
        }
        auto pane = activePane();
        if (pane is null || pane.session is null) {
            return;
        }
        if (_searchIndex < 0) {
            _searchIndex = cast(int)_searchHits.length - 1;
        }
        if (_searchIndex >= cast(int)_searchHits.length) {
            _searchIndex = 0;
        }
        auto hit = _searchHits[_searchIndex];
        size_t sbCount = getScrollbackCount(pane);
        int bufferRow;
        if (hit.line < sbCount) {
            int offset = cast(int)(sbCount - hit.line);
            pane.scrollback.scrollTo(offset);
            bufferRow = cast(int)hit.line - cast(int)sbCount;
        } else {
            pane.scrollback.scrollToBottom();
            bufferRow = cast(int)(hit.line - sbCount);
        }
        int startCol = cast(int)hit.column;
        int endCol = startCol + cast(int)_searchMatchLen - 1;
        if (endCol < startCol) {
            endCol = startCol;
        }
        if (endCol >= pane.cols) {
            endCol = pane.cols - 1;
        }
        if (pane.selection !is null) {
            pane.selection.start(startCol, bufferRow, SelectionType.character);
            pane.selection.update(endCol, bufferRow);
            pane.selection.finish();
        }
    }

    SearchRange[] buildSearchRanges(PaneState pane, ref TerminalFrame frame) {
        if (pane is null || pane.scrollback is null) {
            _searchRanges.length = 0;
            return _searchRanges;
        }
        size_t sbCount = getScrollbackCount(pane);
        int currentOffset = pane.scrollback.offset;
        if (_searchHits.length == 0 || _searchMatchLen == 0 ||
            frame.rows <= 0 || frame.cols <= 0) {
            _searchRanges.length = 0;
            _searchRangesGeneration = _searchGeneration;
            _searchRangesScrollbackCount = sbCount;
            _searchRangesOffset = currentOffset;
            return _searchRanges;
        }

        if (_searchRangesGeneration == _searchGeneration &&
            _searchRangesScrollbackCount == sbCount &&
            _searchRangesOffset == currentOffset) {
            return _searchRanges;
        }

        long topIndex = cast(long)sbCount - pane.scrollback.offset;
        long bottomIndex = topIndex + frame.rows - 1;

        size_t capacity = _searchRanges.length;
        size_t maxRanges = cast(size_t)frame.cols * cast(size_t)frame.rows;
        if (capacity < maxRanges) {
            version (PURE_D_STRICT_NOGC) {
                // Cap results in strict nogc mode to avoid growth.
            } else {
                _searchRanges.length = maxRanges;
                capacity = _searchRanges.length;
            }
        }
        if (capacity == 0) {
            _searchRanges.length = 0;
            _searchRangesGeneration = _searchGeneration;
            _searchRangesScrollbackCount = sbCount;
            _searchRangesOffset = currentOffset;
            return _searchRanges;
        }

        size_t count = 0;
        foreach (hit; _searchHits) {
            long line = cast(long)hit.line;
            if (line < topIndex || line > bottomIndex) {
                continue;
            }
            int row = cast(int)(line - topIndex);
            int startCol = cast(int)hit.column;
            int endCol = startCol + cast(int)_searchMatchLen - 1;
            if (startCol < 0) {
                startCol = 0;
            }
            if (endCol >= frame.cols) {
                endCol = frame.cols - 1;
            }
            if (endCol < 0 || startCol >= frame.cols) {
                continue;
            }
            if (count >= capacity) {
                break;
            }
            _searchRanges[count++] = SearchRange(row, startCol, endCol);
        }
        _searchRanges.length = count;
        _searchRangesGeneration = _searchGeneration;
        _searchRangesScrollbackCount = sbCount;
        _searchRangesOffset = currentOffset;
        return _searchRanges;
    }

    void updateHyperlinkRanges(ref TerminalFrame frame, bool force) {
        if (!force) {
            return;
        }
        if (frame.rows <= 0 || frame.cols <= 0) {
            _hyperlinks.length = 0;
            return;
        }
        if (_hyperlinkScratch.length < frame.cols) {
            version (PURE_D_STRICT_NOGC) {
                return;
            } else {
                _hyperlinkScratch.length = frame.cols;
            }
        }
        size_t desired = cast(size_t)frame.cols * cast(size_t)frame.rows;
        if (_hyperlinks.length < desired) {
            version (PURE_D_STRICT_NOGC) {
                return;
            } else {
                _hyperlinks.length = desired;
            }
        }

        size_t count = 0;

        foreach (row; 0 .. frame.rows) {
            auto line = frame.cells[(row * frame.cols) .. ((row + 1) * frame.cols)];
            scanLineForLinks(line, row, _hyperlinks, count, _hyperlinkScratch);
        }
        _hyperlinks.length = count;
    }

    string hyperlinkAt(int col, int row) const {
        if (_hyperlinks.length == 0) {
            return "";
        }
        foreach (link; _hyperlinks) {
            if (link.row != row) {
                continue;
            }
            if (col >= link.startCol && col <= link.endCol) {
                return link.url;
            }
        }
        return "";
    }

    void updateHoverLink(int col, int row) {
        _hoverLinkActive = false;
        foreach (link; _hyperlinks) {
            if (link.row != row) {
                continue;
            }
            if (col >= link.startCol && col <= link.endCol) {
                _hoverLink = link;
                _hoverLinkActive = true;
                return;
            }
        }
    }

    void clearHoverLink() {
        _hoverLinkActive = false;
    }

    void openUrl(string url) {
        if (url.length == 0) {
            return;
        }
        try {
            spawnProcess(["xdg-open", url]);
        } catch (Exception ex) {
            stderr.writefln("Warning: Failed to open URL %s: %s", url, ex.msg);
        }
    }

    void updateBell(double deltaTime) {
        if (atomicLoad!(MemoryOrder.raw)(_bellTriggered)) {
            _bellIntensity = 1.0f;
            atomicStore!(MemoryOrder.raw)(_bellTriggered, false);
        }
        if (_bellIntensity > 0.0f) {
            _bellIntensity -= cast(float)(deltaTime * _bellDecayRate);
            if (_bellIntensity < 0.0f) {
                _bellIntensity = 0.0f;
            }
        }
    }

    size_t countCodepoints(string text) {
        size_t count = 0;
        foreach (_; text.byDchar) {
            count++;
        }
        return count;
    }

    void refreshCursorSettings() {
        _cursorThickness = _config.cursorThickness;
        CursorRenderStyle parsedStyle;
        if (parseCursorStyle(_config.cursorStyle, parsedStyle)) {
            _cursorStyleOverride = true;
            _cursorStyle = parsedStyle;
        } else {
            _cursorStyleOverride = false;
            _cursorStyle = mapCursorStyle(_rawCursorStyle);
        }
    }

    float[4] resolveSelectionBg(in PureDConfig cfg) {
        if (cfg.selectionBg.length == 4) {
            return [cfg.selectionBg[0], cfg.selectionBg[1],
                cfg.selectionBg[2], cfg.selectionBg[3]];
        }
        return [0.2f, 0.6f, 0.8f, 1.0f];
    }

    void refreshKeybindings() {
        _keybindings.closeWindow = resolveKeybinding("closeWindow", "Ctrl+Q");
        _keybindings.newWindow = resolveKeybinding("newWindow", "Ctrl+Shift+N");
        _keybindings.newTab = resolveKeybinding("newTab", "Ctrl+Shift+T");
        _keybindings.closeTab = resolveKeybinding("closeTab", "Ctrl+Shift+Q");
        _keybindings.splitVertical = resolveKeybinding("splitVertical", "Ctrl+Shift+E");
        _keybindings.splitHorizontal = resolveKeybinding("splitHorizontal", "Ctrl+Shift+O");
        _keybindings.resizeLeft = resolveKeybinding("resizeLeft", "Ctrl+Shift+Alt+Left");
        _keybindings.resizeRight = resolveKeybinding("resizeRight", "Ctrl+Shift+Alt+Right");
        _keybindings.resizeUp = resolveKeybinding("resizeUp", "Ctrl+Shift+Alt+Up");
        _keybindings.resizeDown = resolveKeybinding("resizeDown", "Ctrl+Shift+Alt+Down");
        _keybindings.focusNextPane = resolveKeybinding("focusNextPane", "Ctrl+Tab");
        _keybindings.focusPrevPane = resolveKeybinding("focusPrevPane", "Ctrl+Shift+Tab");
        _keybindings.nextTab = resolveKeybinding("nextTab", "Ctrl+PageDown");
        _keybindings.prevTab = resolveKeybinding("prevTab", "Ctrl+PageUp");
        _keybindings.find = resolveKeybinding("find", "Ctrl+Shift+F");
        _keybindings.findNext = resolveKeybinding("findNext", "F3");
        _keybindings.findPrev = resolveKeybinding("findPrev", "Shift+F3");
        _keybindings.copy = resolveKeybinding("copy", "Ctrl+Shift+C");
        _keybindings.paste = resolveKeybinding("paste", "Ctrl+Shift+V");
        _keybindings.pasteSelection = resolveKeybinding("pasteSelection", "Shift+Insert");
        _keybindings.zoomIn = resolveKeybinding("zoomIn", "Ctrl+Plus");
        _keybindings.zoomOut = resolveKeybinding("zoomOut", "Ctrl+Minus");
        _keybindings.zoomReset = resolveKeybinding("zoomReset", "Ctrl+0");
        _keybindings.fullscreen = resolveKeybinding("fullscreen", "F11");
        _keybindings.scrollPageUp = resolveKeybinding("scrollPageUp", "Shift+PageUp");
        _keybindings.scrollPageDown = resolveKeybinding("scrollPageDown", "Shift+PageDown");
        _keybindings.scrollTop = resolveKeybinding("scrollTop", "Shift+Home");
        _keybindings.scrollBottom = resolveKeybinding("scrollBottom", "Shift+End");
    }

    KeyChord resolveKeybinding(string name, string fallback) {
        KeyChord chord;
        if (_config.keybindings.length != 0) {
            auto entry = name in _config.keybindings;
            if (entry !is null) {
                chord = parseKeyChord(*entry);
                if (chord.valid) {
                    return chord;
                }
            }
        }
        chord = parseKeyChord(fallback);
        return chord;
    }

    float[4] resolveSelectionFg(in PureDConfig cfg, in float[4] selectionBg) {
        if (cfg.selectionFg.length == 4) {
            return [cfg.selectionFg[0], cfg.selectionFg[1],
                cfg.selectionFg[2], cfg.selectionFg[3]];
        }
        return highContrastText(selectionBg);
    }

    float[4] resolveSearchBg(in PureDConfig cfg) {
        if (cfg.searchBg.length == 4) {
            return [cfg.searchBg[0], cfg.searchBg[1],
                cfg.searchBg[2], cfg.searchBg[3]];
        }
        return [0.85f, 0.7f, 0.2f, 1.0f];
    }

    float[4] resolveSearchFg(in PureDConfig cfg, in float[4] searchBg) {
        if (cfg.searchFg.length == 4) {
            return [cfg.searchFg[0], cfg.searchFg[1],
                cfg.searchFg[2], cfg.searchFg[3]];
        }
        return highContrastText(searchBg);
    }

    float[4] resolveLinkFg(in PureDConfig cfg) {
        if (cfg.linkFg.length == 4) {
            return [cfg.linkFg[0], cfg.linkFg[1],
                cfg.linkFg[2], cfg.linkFg[3]];
        }
        return [0.2f, 0.6f, 1.0f, 1.0f];
    }

    float[4] highContrastText(in float[4] background) {
        float[4] black = [0.0f, 0.0f, 0.0f, 1.0f];
        float[4] white = [1.0f, 1.0f, 1.0f, 1.0f];
        auto contrastWithBlack = contrastRatio(background, black);
        auto contrastWithWhite = contrastRatio(background, white);
        return contrastWithBlack >= contrastWithWhite ? black : white;
    }

    float contrastRatio(in float[4] a, in float[4] b) {
        float l1 = relativeLuminance(a);
        float l2 = relativeLuminance(b);
        if (l1 < l2) {
            auto temp = l1;
            l1 = l2;
            l2 = temp;
        }
        return (l1 + 0.05f) / (l2 + 0.05f);
    }

    float relativeLuminance(in float[4] color) {
        float r = linearize(color[0]);
        float g = linearize(color[1]);
        float b = linearize(color[2]);
        return 0.2126f * r + 0.7152f * g + 0.0722f * b;
    }

    float linearize(float channel) {
        if (channel <= 0.03928f) {
            return channel / 12.92f;
        }
        return pow((channel + 0.055f) / 1.055f, 2.4f);
    }

    bool parseCursorStyle(string value, out CursorRenderStyle style) {
        auto cleaned = toLower(strip(value));
        if (cleaned.length == 0) {
            return false;
        }
        switch (cleaned) {
            case "block":
                style = CursorRenderStyle.block;
                return true;
            case "underline":
            case "under":
                style = CursorRenderStyle.underline;
                return true;
            case "bar":
            case "beam":
                style = CursorRenderStyle.bar;
                return true;
            case "outline":
            case "block-outline":
            case "box":
                style = CursorRenderStyle.outline;
                return true;
            default:
                return false;
        }
    }

    CursorRenderStyle mapCursorStyle(TerminalEmulator.CursorStyle style) const {
        final switch (style) {
            case TerminalEmulator.CursorStyle.block:
                return CursorRenderStyle.block;
            case TerminalEmulator.CursorStyle.underline:
                return CursorRenderStyle.underline;
            case TerminalEmulator.CursorStyle.bar:
                return CursorRenderStyle.bar;
        }
    }

    /**
     * Cleanup and terminate.
     */
    void terminate() {
        atomicStore!(MemoryOrder.raw)(_exitRequested, true);
        writefln("Shutting down... (rendered %d frames)", _totalFrameCount);
        persistSplitLayout();

        if (_snapshotPath.length != 0) {
            auto pane = activePane();
            if (pane !is null && pane.session !is null) {
                auto ref snapshotFrame = pane.scrollback.offset > 0 ?
                    pane.session.scrollFrame : pane.session.frames.readBuffer;
                if (snapshotFrame.cells.length != 0) {
                    saveSnapshot(snapshotFrame, pane.scrollback.offset, _snapshotPath);
                }
            }
        }

        if (_ipcServer !is null) {
            _ipcServer.stop();
            _ipcServer = null;
        }
        foreach (paneId, pane; _panes) {
            if (pane !is null && pane.session !is null) {
                pane.session.stop();
            }
        }
        _panes.clear();
        if (_renderer !is null) {
            _renderer.terminate();
            _renderer = null;
        }
        if (_glContext !is null) {
            _glContext.terminate();
            _glContext = null;
        }
        if (_window !is null) {
            _window.terminate();
            _window = null;
        }
    }

    // === ITerminalCallbacks implementation ===

    void onTitleChanged(string title) {
        onPaneTitleChanged(_activePaneId, title);
    }

    void onSendToApplication(scope const(void)[] data) {
        onPaneSendToApplication(_activePaneId, data);
    }

    void onBell() {
        onPaneBell(_activePaneId);
    }

    void onRequestExit() {
        onPaneRequestExit(_activePaneId);
    }

    void onCursorStyleChanged(TerminalEmulator.CursorStyle style) {
        onPaneCursorStyleChanged(_activePaneId, style);
    }

    void onCopyToClipboard(string text) {
        if (_clipboard !is null) {
            _clipboard.setClipboard(text);
        }
    }

    void onCopyToPrimary(string text) {
        if (_clipboard !is null) {
            _clipboard.setPrimary(text);
        }
    }

    string onPasteFromClipboard() {
        if (_clipboard is null) {
            return "";
        }
        return _clipboard.requestClipboard();
    }

    string onPasteFromPrimary() {
        if (_clipboard is null) {
            return "";
        }
        return _clipboard.requestPrimary();
    }

    void onPaneTitleChanged(int paneId, string title) {
        auto pane = paneForId(paneId);
        if (pane is null) {
            return;
        }
        if (_titleMutex is null) {
            pane.shellTitle = title;
            return;
        }
        _titleMutex.lock();
        scope(exit) _titleMutex.unlock();
        pane.shellTitle = title;
        int tabIndex = tabIndexForPane(paneId);
        if (tabIndex >= 0) {
            _tabs[tabIndex].title = title;
        }
        if (paneId == _activePaneId) {
            updateWindowTitle();
        }
    }

    void onPaneSendToApplication(int paneId, scope const(void)[] data) {
        auto pane = paneForId(paneId);
        if (pane is null || pane.session is null || !pane.session.isOpen) {
            return;
        }
        pane.session.pty.write(cast(const(ubyte)[])data);
    }

    void onPaneBell(int paneId) {
        if (paneId == _activePaneId) {
            atomicStore!(MemoryOrder.raw)(_bellTriggered, true);
        }
    }

    void onPaneRequestExit(int paneId) {
        if (paneId == _activePaneId) {
            atomicStore!(MemoryOrder.raw)(_exitRequested, true);
        }
    }

    void onPaneCursorStyleChanged(int paneId, TerminalEmulator.CursorStyle style) {
        if (paneId != _activePaneId) {
            return;
        }
        _rawCursorStyle = style;
        if (!_cursorStyleOverride) {
            _cursorStyle = mapCursorStyle(style);
        }
    }

private:
    /**
     * Read available PTY output and feed to emulator.
     */
    void checkPtyExit() {
        ensureTabs();
        if (_tabs.length == 0) {
            return;
        }

        int[] tabsToClose;
        foreach (i, tab; _tabs) {
            if (tab.scene is null) {
                continue;
            }
            int[] paneIds;
            tab.scene.collectLeafPaneIds(paneIds);
            bool anyOpen = false;
            foreach (paneId; paneIds) {
                auto pane = paneForId(paneId);
                if (pane is null || pane.session is null || pane.session.pty is null) {
                    continue;
                }
                if (pane.session.pty.checkChild()) {
                    writefln("Shell exited in pane %d with status %d",
                        paneId, pane.session.pty.exitStatus);
                    pane.session.stop();
                }
                if (pane.session.isOpen) {
                    anyOpen = true;
                }
            }
            if (!anyOpen && paneIds.length != 0) {
                tabsToClose ~= cast(int)i;
            }
        }

        if (tabsToClose.length == 0) {
            return;
        }
        foreach_reverse (idx; tabsToClose) {
            closeTab(idx);
        }
    }

    /**
     * Render a frame.
     */
    void render() {
        // Clear framebuffer
        _glContext.setClearColor(0.1f, 0.1f, 0.15f, 1.0f);  // Dark terminal background
        _glContext.clear();

        int fbWidth;
        int fbHeight;
        _window.getFramebufferSize(fbWidth, fbHeight);
        if (_viewports.length == 0) {
            updateViewports();
        }

        auto active = activePane();
        if (active is null || active.session is null) {
            return;
        }

        bool activeHasNewFrame = active.session.frames.consume();
        auto ref activeLiveFrame = active.session.frames.readBuffer;
        bool activeScrollbackChanged = false;

        if (activeHasNewFrame && activeLiveFrame.sequence != _lastFrameSequence) {
            auto now = MonoTime.currTime;
            auto latencyUs = (now - activeLiveFrame.publishTime).total!"usecs";
            _lastFrameSequence = activeLiveFrame.sequence;
            _latencyMs = latencyUs / 1000.0;
            if (_latencyAvgMs == 0.0) {
                _latencyAvgMs = _latencyMs;
            } else {
                _latencyAvgMs = _latencyAvgMs * 0.9 + _latencyMs * 0.1;
            }
        }
        if (activeHasNewFrame) {
            applyInputModes(activeLiveFrame);
        }
        activeScrollbackChanged = activeHasNewFrame ? updateScrollbackState(active) : false;
        if (active.scrollback.offset > 0) {
            if (activeHasNewFrame ||
                activeScrollbackChanged ||
                active.scrollback.offset != active.lastScrollbackOffset) {
                composeScrollbackFrame(active, activeLiveFrame, active.scrollback.offset);
            }
        }
        active.lastScrollbackOffset = active.scrollback.offset;

        foreach (vp; _viewports) {
            if (vp.paneId == _activePaneId) {
                continue;
            }
            auto pane = paneForId(vp.paneId);
            if (pane is null || pane.session is null) {
                continue;
            }
            bool hasNewFrame = pane.session.frames.consume();
            auto ref liveFrame = pane.session.frames.readBuffer;
            if (hasNewFrame) {
                updateScrollbackState(pane);
            }
            if (pane.scrollback.offset > 0 &&
                (hasNewFrame || pane.scrollback.offset != pane.lastScrollbackOffset)) {
                composeScrollbackFrame(pane, liveFrame, pane.scrollback.offset);
            }
            pane.lastScrollbackOffset = pane.scrollback.offset;
        }

        auto ref activeRenderFrame = active.scrollback.offset > 0 ?
            active.session.scrollFrame : activeLiveFrame;

        auto searchRanges = buildSearchRanges(active, activeRenderFrame);
        bool sequenceChanged = activeHasNewFrame &&
            activeLiveFrame.sequence != _lastHyperlinkSequence;
        if (sequenceChanged) {
            _lastHyperlinkSequence = activeLiveFrame.sequence;
        }
        bool refreshLinks = sequenceChanged ||
                            activeScrollbackChanged ||
                            active.scrollback.offset != _lastHyperlinkOffset;
        updateHyperlinkRanges(activeRenderFrame, refreshLinks);
        if (refreshLinks) {
            _lastHyperlinkOffset = active.scrollback.offset;
        }

        if (_renderer !is null) {
            _renderer.setBellIntensity(_bellIntensity);
            foreach (vp; _viewports) {
                auto pane = paneForId(vp.paneId);
                if (pane is null || pane.session is null) {
                    continue;
                }
                auto ref paneFrame = pane.scrollback.offset > 0 ?
                    pane.session.scrollFrame : pane.session.frames.readBuffer;
                bool cursorVisible = (pane is active) && pane.scrollback.offset == 0;
                Selection selection = pane is active ? pane.selection : null;
                int selectionOffset = pane is active ? pane.scrollback.offset : 0;
                auto paneSearch = pane is active ? searchRanges : null;
                auto paneLinks = pane is active ? _hyperlinks : null;
                HyperlinkRange hoverLink = _hoverLink;
                bool hoverActive = pane is active && _hoverLinkActive;
                const(dchar)[] overlayText = null;
                int overlayRow = -1;
                if (pane is active && _searchPromptActive &&
                    _searchPromptGlyphs.length > 0) {
                    overlayText = _searchPromptGlyphs;
                    overlayRow = paneFrame.rows - 1;
                }
                int glX = vp.x;
                int glY = fbHeight - vp.y - vp.height;
                _glContext.setViewportRect(glX, glY, vp.width, vp.height);
                _renderer.setViewport(vp.width, vp.height);
                _renderer.render(paneFrame, cursorVisible, selection, selectionOffset,
                    _selectionBg, _selectionFg, paneSearch, _searchBg, _searchFg,
                    paneLinks, _linkFg, hoverLink, hoverActive,
                    _cursorStyle, _cursorThickness,
                    overlayText, overlayRow, _searchBg, _searchFg);
            }
        }

        if (activeHasNewFrame && _snapshotPath.length != 0) {
            auto now = MonoTime.currTime;
            if (_lastSnapshotTime == MonoTime.init ||
                (now - _lastSnapshotTime).total!"msecs" >= 1000) {
                auto ref snapshotFrame = active.scrollback.offset > 0 ?
                    active.session.scrollFrame : activeLiveFrame;
                saveSnapshot(snapshotFrame, active.scrollback.offset, _snapshotPath);
                _lastSnapshotTime = now;
            }
        }

        // Update window title with stats periodically
        if (_frameCount % 60 == 0) {
            string shellTitle;
            auto titlePane = activePane();
            if (_titleMutex !is null) {
                _titleMutex.lock();
                shellTitle = titlePane is null ? "" : titlePane.shellTitle;
                _titleMutex.unlock();
            } else {
                shellTitle = titlePane is null ? "" : titlePane.shellTitle;
            }
            size_t instanceCount = _renderer !is null ? _renderer.lastInstanceCount : 0;
            import core.stdc.stdio : snprintf;
            char[256] titleBuf;
            int written = 0;
            int titleLen = cast(int)shellTitle.length;
            if (titleLen > 120) {
                titleLen = 120;
            }
            double frameMs = _fps > 0.0 ? (1000.0 / _fps) : 0.0;

            if (_latencyAvgMs > 0.0) {
                if (shellTitle.length > 0) {
                    written = snprintf(titleBuf.ptr, titleBuf.length,
                        "%.*s - %.1f FPS (lat %.2f ms, pty %.1f MB/s, inst %zu)",
                        titleLen, shellTitle.ptr, _fps, _latencyAvgMs, _ptyMbps, instanceCount);
                } else {
                    written = snprintf(titleBuf.ptr, titleBuf.length,
                        "Tilix Pure D - %.1f FPS (%.2f ms, lat %.2f ms, pty %.1f MB/s, inst %zu)",
                        _fps, frameMs, _latencyAvgMs, _ptyMbps, instanceCount);
                }
            } else if (shellTitle.length > 0) {
                written = snprintf(titleBuf.ptr, titleBuf.length,
                    "%.*s - %.1f FPS (pty %.1f MB/s, inst %zu)",
                    titleLen, shellTitle.ptr, _fps, _ptyMbps, instanceCount);
            } else {
                written = snprintf(titleBuf.ptr, titleBuf.length,
                    "Tilix Pure D - %.1f FPS (%.2f ms, pty %.1f MB/s, inst %zu)",
                    _fps, frameMs, _ptyMbps, instanceCount);
            }
            if (written > 0) {
                _window.setTitleRaw(titleBuf.ptr);
            }
        }

        // Debug: print first line of terminal every second
        debug {
            static int debugCounter = 0;
            debugCounter++;
            if (debugCounter >= 60) {
                debugCounter = 0;
                printDebugLine();
            }
        }
    }

    debug void printDebugLine() {
        import std.array : appender;
        auto line = appender!string();
        auto pane = activePane();
        if (pane is null || pane.session is null) {
            return;
        }
        auto ref frame = pane.session.frames.readBuffer;
        if (frame.cols <= 0 || frame.rows <= 0) return;
        foreach (x; 0 .. frame.cols) {
            size_t idx = cast(size_t)x;
            if (idx >= frame.cells.length) break;
            auto cell = frame.cells[idx];
            if (!cell.hasNonCharacterData) {
                auto ch = cell.ch;
                if (ch >= 32 && ch < 127) {
                    line ~= cast(char)ch;
                } else if (ch == 0 || ch == ' ') {
                    line ~= ' ';
                } else {
                    line ~= '?';
                }
            } else {
                line ~= '@';
            }
        }
        writefln("Line 0: [%s]", line.data);
    }

    /**
     * Update FPS counter.
     */
    void updateFPS(double deltaTime) {
        _frameTimeAccum += deltaTime;

        // Update FPS every second
        if (_frameTimeAccum >= 1.0) {
            _fps = _frameCount / _frameTimeAccum;
            auto pane = activePane();
            if (pane !is null && pane.session !is null && pane.session.parserWorker !is null) {
                auto totalBytes = pane.session.parserWorker.totalBytesProcessed();
                auto deltaBytes = totalBytes - _lastPtyBytes;
                _lastPtyBytes = totalBytes;
                _ptyMbps = (deltaBytes / _frameTimeAccum) / (1024.0 * 1024.0);
            } else {
                _ptyMbps = 0.0;
            }
            _frameCount = 0;
            _frameTimeAccum = 0.0;
        }
    }

    /**
     * Handle window resize.
     */
    void onResize(int width, int height) {
        _glContext.setViewport(width, height);
        if (_renderer !is null) {
            _renderer.setViewport(width, height);
        }
        int prevCols = _cols;
        int prevRows = _rows;
        updateViewports();

        if (_cols != prevCols || _rows != prevRows) {
            writefln("Window resized: %dx%d (terminal: %dx%d)", width, height, _cols, _rows);
        }
    }

    void onContentScale(float xScale, float yScale) {
        float scale = xScale > yScale ? xScale : yScale;
        applyContentScale(scale);
    }

    /**
     * Handle key press.
     */
    void onKey(int key, int scancode, int action, int mods) {
        _lastKeyMods = mods;
        _inputHandler.updateKeyState(scancode, action);
        auto pane = activePane();
        if (_searchPromptActive) {
            if (action == GLFW_PRESS || action == GLFW_REPEAT) {
                if (key == GLFW_KEY_ENTER) {
                    confirmSearchPrompt();
                    return;
                }
                if (key == GLFW_KEY_ESCAPE) {
                    cancelSearchPrompt();
                    return;
                }
                if (key == GLFW_KEY_BACKSPACE) {
                    _searchPromptBuffer = popLastCodepoint(_searchPromptBuffer);
                    _searchHistoryIndex = cast(int)_searchHistory.length;
                    _searchPromptDraft = _searchPromptBuffer;
                    refreshSearchPromptDisplay();
                    return;
                }
                if (key == GLFW_KEY_UP) {
                    if (_searchHistory.length != 0 &&
                        _searchHistoryIndex > 0) {
                        if (_searchHistoryIndex == cast(int)_searchHistory.length) {
                            _searchPromptDraft = _searchPromptBuffer;
                        }
                        _searchHistoryIndex--;
                        _searchPromptBuffer = _searchHistory[_searchHistoryIndex];
                        refreshSearchPromptDisplay();
                    }
                    return;
                }
                if (key == GLFW_KEY_DOWN) {
                    if (_searchHistory.length != 0 &&
                        _searchHistoryIndex < cast(int)_searchHistory.length) {
                        _searchHistoryIndex++;
                        if (_searchHistoryIndex >= cast(int)_searchHistory.length) {
                            _searchPromptBuffer = _searchPromptDraft;
                            _searchHistoryIndex = cast(int)_searchHistory.length;
                        } else {
                            _searchPromptBuffer = _searchHistory[_searchHistoryIndex];
                        }
                        refreshSearchPromptDisplay();
                    }
                    return;
                }
            }
            return;
        }
        if (action == GLFW_PRESS &&
            matchKeyChord(_keybindings.closeWindow, key, mods)) {
            _window.close();
            return;
        }

        if (action == GLFW_PRESS) {
            if (matchKeyChord(_keybindings.splitVertical, key, mods)) {
                splitActive(SplitOrientation.vertical);
                return;
            }
            if (matchKeyChord(_keybindings.splitHorizontal, key, mods)) {
                splitActive(SplitOrientation.horizontal);
                return;
            }
            if (matchKeyChord(_keybindings.newTab, key, mods)) {
                createTab();
                return;
            }
            if (matchKeyChord(_keybindings.newWindow, key, mods)) {
                spawnNewInstance();
                return;
            }
            if (matchKeyChord(_keybindings.closeTab, key, mods)) {
                closeTab(_activeTabIndex);
                return;
            }
        }

        if (action == GLFW_PRESS) {
            if (matchKeyChord(_keybindings.zoomIn, key, mods) ||
                (key == GLFW_KEY_KP_ADD &&
                 _keybindings.zoomIn.mods == normalizeMods(mods))) {
                adjustFontSize(1);
                return;
            }
            if (matchKeyChord(_keybindings.zoomOut, key, mods) ||
                (key == GLFW_KEY_KP_SUBTRACT &&
                 _keybindings.zoomOut.mods == normalizeMods(mods))) {
                adjustFontSize(-1);
                return;
            }
            if (matchKeyChord(_keybindings.zoomReset, key, mods) ||
                (key == GLFW_KEY_KP_0 &&
                 _keybindings.zoomReset.mods == normalizeMods(mods))) {
                resetFontSize();
                return;
            }
        }

        if (action == GLFW_PRESS &&
            matchKeyChord(_keybindings.fullscreen, key, mods)) {
            _window.toggleFullscreen();
            return;
        }

        if (action == GLFW_PRESS || action == GLFW_REPEAT) {
            float delta = 0.05f;
            if (matchKeyChord(_keybindings.resizeLeft, key, mods)) {
                resizeActiveSplit(SplitOrientation.vertical, -delta);
                return;
            }
            if (matchKeyChord(_keybindings.resizeRight, key, mods)) {
                resizeActiveSplit(SplitOrientation.vertical, delta);
                return;
            }
            if (matchKeyChord(_keybindings.resizeUp, key, mods)) {
                resizeActiveSplit(SplitOrientation.horizontal, -delta);
                return;
            }
            if (matchKeyChord(_keybindings.resizeDown, key, mods)) {
                resizeActiveSplit(SplitOrientation.horizontal, delta);
                return;
            }
        }

        if (action == GLFW_PRESS) {
            if (matchKeyChord(_keybindings.focusNextPane, key, mods)) {
                focusAdjacentPane(1);
                return;
            }
            if (matchKeyChord(_keybindings.focusPrevPane, key, mods)) {
                focusAdjacentPane(-1);
                return;
            }
            if (matchKeyChord(_keybindings.prevTab, key, mods)) {
                nextTab(-1);
                return;
            }
            if (matchKeyChord(_keybindings.nextTab, key, mods)) {
                nextTab(1);
                return;
            }
        }

        if (action == GLFW_PRESS &&
            matchKeyChord(_keybindings.find, key, mods)) {
            triggerSearch();
            return;
        }

        if (action == GLFW_PRESS) {
            if (matchKeyChord(_keybindings.findNext, key, mods)) {
                nextSearchHit(false);
                return;
            }
            if (matchKeyChord(_keybindings.findPrev, key, mods)) {
                nextSearchHit(true);
                return;
            }
        }

        // Handle scrollback navigation (Shift+PageUp/PageDown)
        if (action == GLFW_PRESS || action == GLFW_REPEAT) {
            if (matchKeyChord(_keybindings.scrollPageUp, key, mods)) {
                if (pane !is null && pane.scrollback !is null) {
                    pane.scrollback.scrollPages(1);
                }
                return;
            }
            if (matchKeyChord(_keybindings.scrollPageDown, key, mods)) {
                if (pane !is null && pane.scrollback !is null) {
                    pane.scrollback.scrollPages(-1);
                }
                return;
            }
            if (matchKeyChord(_keybindings.scrollTop, key, mods)) {
                if (pane !is null && pane.scrollback !is null) {
                    pane.scrollback.scrollToTop();
                }
                return;
            }
            if (matchKeyChord(_keybindings.scrollBottom, key, mods)) {
                if (pane !is null && pane.scrollback !is null) {
                    pane.scrollback.scrollToBottom();
                }
                return;
            }
        }

        if (action == GLFW_PRESS) {
            if (matchKeyChord(_keybindings.copy, key, mods)) {
                copySelectionToClipboard();
                return;
            }
            if (matchKeyChord(_keybindings.paste, key, mods)) {
                string text = _clipboard is null ? "" : _clipboard.requestClipboard();
                pasteText(text);
                return;
            }
            if (matchKeyChord(_keybindings.pasteSelection, key, mods)) {
                string text = _clipboard is null ? "" : _clipboard.requestPrimary();
                pasteText(text);
                return;
            }
        }

        // Handle special keys via InputHandler
        if (action == GLFW_PRESS || action == GLFW_REPEAT) {
            auto escSeq = _inputHandler.translateKey(key, scancode, action, mods);
            if (escSeq !is null) {
                sendToPty(escSeq);
            } else if (key == GLFW_KEY_UNKNOWN) {
                auto fallback = _inputHandler.translateUnknownKey(scancode, mods);
                if (fallback !is null) {
                    sendToPty(fallback);
                }
            }
        }
    }

    /**
     * Handle character input (Unicode).
     */
    void onChar(uint codepoint) {
        if (_searchPromptActive) {
            if (codepoint != 0) {
                _searchPromptBuffer ~= encodeCodepoint(cast(dchar)codepoint);
                _searchHistoryIndex = cast(int)_searchHistory.length;
                _searchPromptDraft = _searchPromptBuffer;
                refreshSearchPromptDisplay();
            }
            return;
        }
        auto pane = activePane();
        if (pane is null || pane.session is null || !pane.session.isOpen) {
            return;
        }

        // Use InputHandler for Alt+key handling
        auto data = _inputHandler.translateChar(codepoint, _lastKeyMods);
        if (data !is null) {
            sendToPty(data);
        }
    }

    /**
     * Handle mouse button events.
     */
    void onMouseButton(int button, int action, int mods) {
        Viewport viewport;
        if (!viewportAt(_mouseX, _mouseY, viewport)) {
            return;
        }
        setActivePane(viewport.paneId);
        auto pane = activePane();
        if (pane is null) {
            return;
        }

        if (action == GLFW_PRESS &&
            button == GLFW_MOUSE_BUTTON_LEFT &&
            (mods & GLFW_MOD_ALT) &&
            _inputHandler.mouseMode == MouseMode.none) {
            if (beginSplitDrag(_mouseX, _mouseY)) {
                _mouseButtons |= (1 << button);
                return;
            }
        }

        if (action == GLFW_RELEASE &&
            button == GLFW_MOUSE_BUTTON_LEFT &&
            _splitDrag.active) {
            _mouseButtons &= ~(1 << button);
            endSplitDrag();
            return;
        }

        double localX = _mouseX - viewport.x;
        double localY = _mouseY - viewport.y;
        int colsInView = viewport.width / _cellWidth;
        int rowsInView = viewport.height / _cellHeight;
        if (colsInView <= 0 || rowsInView <= 0) {
            return;
        }

        int col = cast(int)(localX / _cellWidth);
        int row = cast(int)(localY / _cellHeight);

        // Clamp to valid range
        col = col < 0 ? 0 : (col >= colsInView ? colsInView - 1 : col);
        row = row < 0 ? 0 : (row >= rowsInView ? rowsInView - 1 : row);

        // Convert to buffer coordinates (account for scrollback)
        int bufferRow = pane.scrollback.bufferRow(row);

        if (action == GLFW_PRESS &&
            button == GLFW_MOUSE_BUTTON_MIDDLE &&
            _inputHandler.mouseMode == MouseMode.none) {
            string text = _clipboard is null ? "" : _clipboard.requestPrimary();
            pasteText(text);
            return;
        }

        if (action == GLFW_PRESS) {
            // Track button state
            _mouseButtons |= (1 << button);

            // Check for selection (left button without mouse mode)
            if (button == GLFW_MOUSE_BUTTON_LEFT && _inputHandler.mouseMode == MouseMode.none) {
                if (mods & GLFW_MOD_CONTROL) {
                    auto url = hyperlinkAt(col, row);
                    if (url.length != 0) {
                        openUrl(url);
                        return;
                    }
                }
                // Detect click count for word/line selection
                pane.clickDetector.click(col, bufferRow);
                auto selType = pane.clickDetector.selectionType();

                if (mods & GLFW_MOD_SHIFT) {
                    // Shift+click extends selection
                    if (pane.selection !is null) {
                        pane.selection.extend(col, bufferRow);
                    }
                } else {
                    // Start new selection
                    if (pane.selection !is null) {
                        pane.selection.start(col, bufferRow, selType);
                    }
                }
            } else {
                // Send to application if mouse mode enabled
                auto data = _inputHandler.translateMouseButton(button, action, mods, col, row);
                if (data !is null) {
                    sendToPty(data);
                }
            }
        } else if (action == GLFW_RELEASE) {
            _mouseButtons &= ~(1 << button);

            if (button == GLFW_MOUSE_BUTTON_LEFT &&
                pane.selection !is null &&
                pane.selection.active) {
                pane.selection.finish();
                copySelectionToPrimary();
            } else {
                auto data = _inputHandler.translateMouseButton(button, action, mods, col, row);
                if (data !is null) {
                    sendToPty(data);
                }
            }
        }
    }

    /**
     * Handle scroll wheel events.
     */
    void onScroll(double xoffset, double yoffset) {
        Viewport viewport;
        if (!viewportAt(_mouseX, _mouseY, viewport)) {
            return;
        }
        setActivePane(viewport.paneId);
        auto pane = activePane();
        if (pane is null) {
            return;
        }
        double localX = _mouseX - viewport.x;
        double localY = _mouseY - viewport.y;
        int colsInView = viewport.width / _cellWidth;
        int rowsInView = viewport.height / _cellHeight;
        if (colsInView <= 0 || rowsInView <= 0) {
            return;
        }
        int col = cast(int)(localX / _cellWidth);
        int row = cast(int)(localY / _cellHeight);

        // If mouse mode is active, send to application
        if (_inputHandler.mouseMode != MouseMode.none) {
            auto data = _inputHandler.translateScroll(xoffset, yoffset, 0, col, row);
            if (data !is null) {
                sendToPty(data);
            }
        } else {
            // Otherwise, scroll the viewport
            pane.scrollback.handleScrollWheel(yoffset);
        }
    }

    /**
     * Handle mouse cursor position updates.
     */
    void onCursorPos(double xpos, double ypos) {
        _mouseX = xpos;
        _mouseY = ypos;

        if (_splitDrag.active) {
            updateSplitDrag(xpos, ypos);
            return;
        }

        Viewport viewport;
        if (!viewportAt(xpos, ypos, viewport)) {
            clearHoverLink();
            return;
        }
        setActivePane(viewport.paneId);
        auto pane = activePane();
        if (pane is null) {
            clearHoverLink();
            return;
        }

        double localX = xpos - viewport.x;
        double localY = ypos - viewport.y;
        int colsInView = viewport.width / _cellWidth;
        int rowsInView = viewport.height / _cellHeight;
        if (colsInView <= 0 || rowsInView <= 0) {
            return;
        }

        int col = cast(int)(localX / _cellWidth);
        int row = cast(int)(localY / _cellHeight);

        // Clamp to valid range
        col = col < 0 ? 0 : (col >= colsInView ? colsInView - 1 : col);
        row = row < 0 ? 0 : (row >= rowsInView ? rowsInView - 1 : row);

        if (_inputHandler.mouseMode == MouseMode.none &&
            (_lastKeyMods & GLFW_MOD_CONTROL)) {
            updateHoverLink(col, row);
        } else {
            clearHoverLink();
        }

        int bufferRow = pane.scrollback.bufferRow(row);

        // Update selection if dragging
        if (pane.selection !is null && pane.selection.active && (_mouseButtons & 1)) {
            pane.selection.update(col, bufferRow);
        }

        // Send motion to application if mouse tracking enabled
        if (_inputHandler.mouseMode == MouseMode.buttonEvent ||
            _inputHandler.mouseMode == MouseMode.anyEvent) {
            auto data = _inputHandler.translateMouseMotion(_mouseButtons, 0, col, row);
            if (data !is null) {
                sendToPty(data);
            }
        }
    }

    void onFocusChanged(bool focused) {
        auto data = _inputHandler.translateFocus(focused);
        if (data !is null) {
            sendToPty(data);
        }
    }

    /**
     * Helper to send data to PTY.
     */
    void sendToPty(const(ubyte)[] data) {
        auto pane = activePane();
        if (pane !is null &&
            pane.session !is null &&
            pane.session.isOpen &&
            data.length > 0) {
            pane.session.pty.write(data);
        }
    }

    void pasteText(string text) {
        auto pane = activePane();
        if (pane is null || pane.session is null || !pane.session.isOpen || text.length == 0) {
            return;
        }
        auto start = _inputHandler.bracketedPasteStart();
        if (start !is null) {
            sendToPty(start);
        }
        sendToPty(cast(const(ubyte)[])text);
        auto end = _inputHandler.bracketedPasteEnd();
        if (end !is null) {
            sendToPty(end);
        }
    }

    void copySelectionToPrimary() {
        auto pane = activePane();
        if (_clipboard is null || pane is null || pane.selection is null ||
            !pane.selection.hasSelection) {
            return;
        }
        auto text = pane.selection.getSelectedText(
            (col, row) => getCharAt(_activePaneId, col, row),
            pane.cols);
        if (text.length == 0) {
            return;
        }
        _clipboard.setPrimary(text);
    }

    void copySelectionToClipboard() {
        auto pane = activePane();
        if (_clipboard is null || pane is null || pane.selection is null ||
            !pane.selection.hasSelection) {
            return;
        }
        auto text = pane.selection.getSelectedText(
            (col, row) => getCharAt(_activePaneId, col, row),
            pane.cols);
        if (text.length == 0) {
            return;
        }
        _clipboard.setClipboard(text);
    }

    /**
     * Get character at buffer position (for selection word detection).
     */
    dchar getCharAt(int paneId, int col, int row) {
        auto pane = paneForId(paneId);
        if (pane is null || pane.session is null) {
            return ' ';
        }
        auto ref frame = pane.session.frames.readBuffer;
        if (frame.cols <= 0 || frame.rows <= 0) return ' ';
        if (col < 0 || col >= frame.cols) return ' ';

        size_t sbCount = getScrollbackCount(pane);
        long globalIndex = cast(long)sbCount + row;
        if (globalIndex < 0) return ' ';

        if (globalIndex < cast(long)sbCount) {
            auto cell = getScrollbackCell(pane, cast(size_t)globalIndex, col);
            if (cell.hasNonCharacterData) return ' ';
            return cell.ch == 0 ? ' ' : cell.ch;
        }

        int screenRow = cast(int)(globalIndex - cast(long)sbCount);
        if (screenRow < 0 || screenRow >= frame.rows) return ' ';

        int idx = screenRow * frame.cols + col;
        if (idx < 0) return ' ';
        size_t uidx = cast(size_t)idx;
        if (uidx >= frame.cells.length) return ' ';
        auto cell = frame.cells[uidx];
        if (cell.hasNonCharacterData) return ' ';
        return cell.ch == 0 ? ' ' : cell.ch;
    }

    void initializeFrames(TerminalSession session, int cols, int rows) {
        if (session is null) {
            return;
        }
        session.frames.reset();
        resizeFrameBuffers(session, cols, rows);
        updateFrameFromEmulator(session);
        session.frames.publish();
        session.frames.consume();
    }

    void resizeFrameBuffers(TerminalSession session, int cols, int rows) {
        if (session is null) {
            return;
        }
        foreach (i; 0 .. 3) {
            session.frames.bufferAt(i).ensureSize(cols, rows);
        }
    }

    void updateFrameFromEmulator(TerminalSession session) {
        if (session is null || session.emulator is null) {
            return;
        }
        auto screen = session.emulator.getScreenBuffer();
        auto ref back = session.frames.writeBuffer;
        back.updateFromCells(
            screen,
            session.emulator.cols,
            session.emulator.rows,
            session.emulator.cursorCol,
            session.emulator.cursorRow,
            session.emulator.isAlternateScreen,
            session.emulator.applicationCursorMode,
            session.emulator.mouseMode,
            session.emulator.mouseEncoding,
            session.emulator.bracketedPasteModeEnabled,
            session.emulator.focusReportingEnabled
        );
    }

    void applyInputModes(ref TerminalFrame frame) {
        if (_inputHandler is null) {
            return;
        }
        _inputHandler.setApplicationCursorMode(frame.applicationCursorMode);
        _inputHandler.setMouseMode(frame.mouseMode);
        _inputHandler.setMouseEncoding(frame.mouseEncoding);
        _inputHandler.setBracketedPasteMode(frame.bracketedPasteMode);
        _inputHandler.setFocusReporting(frame.focusReporting);
    }

    void applyContentScale(float scale) {
        _contentScale = scale > 0 ? scale : 1.0f;
        if (_renderer !is null) {
            _renderer.setContentScale(_contentScale);
            _cellWidth = _renderer.cellWidth;
            _cellHeight = _renderer.cellHeight;
        }
        int width, height;
        _window.getFramebufferSize(width, height);
        onResize(width, height);
    }

    bool updateScrollbackState(PaneState pane) {
        if (pane is null || pane.scrollback is null) {
            return false;
        }
        size_t sbCount = getScrollbackCount(pane);
        if (sbCount > pane.lastScrollbackCount) {
            pane.scrollback.linesAdded(cast(int)(sbCount - pane.lastScrollbackCount));
        } else if (sbCount < pane.lastScrollbackCount) {
            pane.scrollback.clear();
            pane.scrollback.linesAdded(cast(int)sbCount);
        }
        bool changed = sbCount != pane.lastScrollbackCount;
        pane.lastScrollbackCount = sbCount;
        return changed;
    }

    size_t getScrollbackCount(PaneState pane) {
        if (pane is null ||
            pane.session is null ||
            pane.session.scrollbackBuffer is null ||
            pane.session.scrollbackMutex is null) {
            return 0;
        }
        pane.session.scrollbackMutex.lock();
        scope(exit) pane.session.scrollbackMutex.unlock();
        return pane.session.scrollbackBuffer.lineCount;
    }

    TerminalEmulator.TerminalCell getScrollbackCell(PaneState pane,
            size_t lineIndex, int col) {
        TerminalEmulator.TerminalCell cell;
        if (pane is null ||
            pane.session is null ||
            pane.session.scrollbackBuffer is null ||
            pane.session.scrollbackMutex is null) {
            return cell;
        }
        pane.session.scrollbackMutex.lock();
        scope(exit) pane.session.scrollbackMutex.unlock();
        auto line = pane.session.scrollbackBuffer.lineView(lineIndex);
        if (line !is null && col >= 0 && col < line.length) {
            cell = line[cast(size_t)col];
        }
        return cell;
    }

    void composeScrollbackFrame(PaneState pane, ref TerminalFrame liveFrame, int offset) {
        if (pane is null || pane.session is null) {
            return;
        }
        pane.session.scrollFrame.ensureSize(liveFrame.cols, liveFrame.rows);
        pane.session.scrollFrame.cursorCol = liveFrame.cursorCol;
        pane.session.scrollFrame.cursorRow = liveFrame.cursorRow;
        pane.session.scrollFrame.alternateScreen = liveFrame.alternateScreen;

        int rows = liveFrame.rows;
        int cols = liveFrame.cols;
        size_t sbCount = 0;

        pane.session.scrollbackMutex.lock();
        sbCount = pane.session.scrollbackBuffer !is null
            ? pane.session.scrollbackBuffer.lineCount
            : 0;

        long topIndex = cast(long)sbCount - offset;
        foreach (row; 0 .. rows) {
            long globalIndex = topIndex + row;
            auto dest = pane.session.scrollFrame.cells[(row * cols) .. ((row + 1) * cols)];

            if (globalIndex < 0) {
                fillBlankLine(dest);
                continue;
            }

            if (globalIndex < cast(long)sbCount) {
                auto line = pane.session.scrollbackBuffer.lineView(cast(size_t)globalIndex);
                if (line is null) {
                    fillBlankLine(dest);
                } else {
                    copyLine(dest, line);
                }
                continue;
            }

            int screenRow = cast(int)(globalIndex - cast(long)sbCount);
            if (screenRow < 0 || screenRow >= rows) {
                fillBlankLine(dest);
                continue;
            }

            auto src = liveFrame.cells[(screenRow * cols) .. ((screenRow + 1) * cols)];
            copyLine(dest, src);
        }
        pane.session.scrollbackMutex.unlock();
    }

    static void fillBlankLine(ref TerminalEmulator.TerminalCell[] dest) {
        foreach (i; 0 .. dest.length) {
            dest[i] = TerminalEmulator.TerminalCell.init;
        }
    }

    static void copyLine(ref TerminalEmulator.TerminalCell[] dest,
                         const TerminalEmulator.TerminalCell[] src) {
        auto count = dest.length < src.length ? dest.length : src.length;
        foreach (i; 0 .. count) {
            dest[i] = cast(TerminalEmulator.TerminalCell)src[i];
        }
        foreach (i; count .. dest.length) {
            dest[i] = TerminalEmulator.TerminalCell.init;
        }
    }
}

/**
 * Encode a Unicode codepoint to UTF-8.
 *
 * Returns: Number of bytes written (1-4), or 0 on error
 */
size_t encodeUtf8(dchar codepoint, ref char[4] buffer) {
    if (codepoint < 0x80) {
        buffer[0] = cast(char)codepoint;
        return 1;
    } else if (codepoint < 0x800) {
        buffer[0] = cast(char)(0xC0 | (codepoint >> 6));
        buffer[1] = cast(char)(0x80 | (codepoint & 0x3F));
        return 2;
    } else if (codepoint < 0x10000) {
        buffer[0] = cast(char)(0xE0 | (codepoint >> 12));
        buffer[1] = cast(char)(0x80 | ((codepoint >> 6) & 0x3F));
        buffer[2] = cast(char)(0x80 | (codepoint & 0x3F));
        return 3;
    } else if (codepoint < 0x110000) {
        buffer[0] = cast(char)(0xF0 | (codepoint >> 18));
        buffer[1] = cast(char)(0x80 | ((codepoint >> 12) & 0x3F));
        buffer[2] = cast(char)(0x80 | ((codepoint >> 6) & 0x3F));
        buffer[3] = cast(char)(0x80 | (codepoint & 0x3F));
        return 4;
    }
    return 0;  // Invalid codepoint
}

/**
 * Convert GLFW key code to terminal escape sequence.
 *
 * Params:
 *   key = GLFW key code
 *   mods = Modifier keys (Ctrl, Alt, Shift)
 *
 * Returns: Escape sequence string, or null if not a special key
 */
const(ubyte)[] keyToEscapeSequence(int key, int mods) {
    import bindbc.glfw;

    // Application cursor key mode sequences (CSI sequences)
    // These are the default for most terminals
    switch (key) {
        // Arrow keys
        case GLFW_KEY_UP:    return cast(const(ubyte)[])"\x1b[A";
        case GLFW_KEY_DOWN:  return cast(const(ubyte)[])"\x1b[B";
        case GLFW_KEY_RIGHT: return cast(const(ubyte)[])"\x1b[C";
        case GLFW_KEY_LEFT:  return cast(const(ubyte)[])"\x1b[D";

        // Navigation keys
        case GLFW_KEY_HOME:      return cast(const(ubyte)[])"\x1b[H";
        case GLFW_KEY_END:       return cast(const(ubyte)[])"\x1b[F";
        case GLFW_KEY_INSERT:    return cast(const(ubyte)[])"\x1b[2~";
        case GLFW_KEY_DELETE:    return cast(const(ubyte)[])"\x1b[3~";
        case GLFW_KEY_PAGE_UP:   return cast(const(ubyte)[])"\x1b[5~";
        case GLFW_KEY_PAGE_DOWN: return cast(const(ubyte)[])"\x1b[6~";

        // Function keys F1-F12
        case GLFW_KEY_F1:  return cast(const(ubyte)[])"\x1bOP";
        case GLFW_KEY_F2:  return cast(const(ubyte)[])"\x1bOQ";
        case GLFW_KEY_F3:  return cast(const(ubyte)[])"\x1bOR";
        case GLFW_KEY_F4:  return cast(const(ubyte)[])"\x1bOS";
        case GLFW_KEY_F5:  return cast(const(ubyte)[])"\x1b[15~";
        case GLFW_KEY_F6:  return cast(const(ubyte)[])"\x1b[17~";
        case GLFW_KEY_F7:  return cast(const(ubyte)[])"\x1b[18~";
        case GLFW_KEY_F8:  return cast(const(ubyte)[])"\x1b[19~";
        case GLFW_KEY_F9:  return cast(const(ubyte)[])"\x1b[20~";
        case GLFW_KEY_F10: return cast(const(ubyte)[])"\x1b[21~";
        case GLFW_KEY_F11: return cast(const(ubyte)[])"\x1b[23~";
        case GLFW_KEY_F12: return cast(const(ubyte)[])"\x1b[24~";

        // Special keys
        case GLFW_KEY_BACKSPACE: return cast(const(ubyte)[])"\x7f";  // DEL character
        case GLFW_KEY_TAB:       return cast(const(ubyte)[])"\t";
        case GLFW_KEY_ENTER:     return cast(const(ubyte)[])"\r";

        default:
            break;
    }

    // Handle Ctrl+letter combinations
    if (mods & GLFW_MOD_CONTROL) {
        // Ctrl+A through Ctrl+Z generate ASCII 1-26
        if (key >= GLFW_KEY_A && key <= GLFW_KEY_Z) {
            static ubyte[1] ctrlChar;
            ctrlChar[0] = cast(ubyte)(key - GLFW_KEY_A + 1);
            return ctrlChar[];
        }
        // Ctrl+[ is ESC (27)
        if (key == GLFW_KEY_LEFT_BRACKET) {
            return cast(const(ubyte)[])"\x1b";
        }
        // Ctrl+\ is FS (28)
        if (key == GLFW_KEY_BACKSLASH) {
            static ubyte[1] fs = [28];
            return fs[];
        }
        // Ctrl+] is GS (29)
        if (key == GLFW_KEY_RIGHT_BRACKET) {
            static ubyte[1] gs = [29];
            return gs[];
        }
    }

    return null;  // Not a special key
}

/**
 * Main entry point for Pure D backend.
 */
void main() {
    writeln("=== Tilix Pure D Terminal ===");
    writeln("Super Phase 6.1: PTY + Emulator Integration");
    writeln("");

    auto app = new PureDTerminal();

    if (!app.initialize()) {
        stderr.writefln("Fatal: Failed to initialize application");
        return;
    }

    scope(exit) app.terminate();

    app.run();

    writeln("Goodbye!");
}
