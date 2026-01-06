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
import pured.pty;
import pured.ptyreader;
import pured.emulator;
import pured.parserworker;
import pured.renderer;
import pured.config;
import pured.theme_importer;
import pured.platform.input;
import pured.platform.clipboard;
import pured.terminal.frame : TerminalFrame;
import pured.terminal.selection;
import pured.terminal.scrollback;
import pured.terminal.scrollback_buffer : ScrollbackBuffer;
import pured.terminal.search : SearchHit, SearchRange, findInScrollback, findInFrame;
import pured.terminal.hyperlink : HyperlinkRange, scanLineForLinks;
import pured.ipc.server : IpcServer, IpcCommand, IpcCommandType;
import pured.util.triplebuffer : TripleBuffer;
import arsd.terminalemulator : TerminalEmulator;
import std.stdio : stderr, writefln, writeln;
import std.string : strip, toLower;
import std.utf : byDchar;
import std.math : pow;
import std.process : spawnProcess;
import std.path : buildPath;
import std.process : environment;
import core.atomic : atomicLoad, atomicStore, MemoryOrder;
import core.thread : Thread;
import core.time : MonoTime, dur;
import core.sync.mutex : Mutex;
import std.datetime : SysTime;
import std.file : exists, timeLastModified, thisExePath;
import bindbc.glfw;

/**
 * Pure D Terminal Application
 *
 * Main class coordinating window, rendering, PTY, and terminal emulation.
 */
class PureDTerminal : ITerminalCallbacks {
private:
    GLFWWindow _window;
    GLContext _glContext;
    PTY _pty;
    PtyReader _ptyReader;
    PureDEmulator _emulator;
    ParserWorker _parserWorker;
    CellRenderer _renderer;
    TripleBuffer!TerminalFrame _frames;

    // Input handling
    InputHandler _inputHandler;
    ClipboardBridge _clipboard;
    Selection _selection;
    ScrollbackViewport _scrollback;
    ClickDetector _clickDetector;
    ScrollbackBuffer _scrollbackBuffer;
    Mutex _scrollbackMutex;
    TerminalFrame _scrollFrame;
    size_t _scrollbackMaxLines = 200_000;
    size_t _lastScrollbackCount;
    int _lastScrollbackOffset;

    // Mouse state
    double _mouseX = 0;
    double _mouseY = 0;
    int _mouseButtons = 0;
    int _lastKeyMods = 0;

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
    string _shellTitle;
    shared bool _exitRequested;
    float _contentScale = 1.0f;
    PureDConfig _config;
    Thread _configWatcher;
    Mutex _configMutex;
    PureDConfig _pendingConfig;
    shared bool _configPending;
    string _configPath;
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

    HyperlinkRange[] _hyperlinks;
    char[] _hyperlinkScratch;
    ulong _lastHyperlinkSequence;
    int _lastHyperlinkOffset = int.min;

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
        _selectionBg = resolveSelectionBg(_config);
        _selectionFg = resolveSelectionFg(_config, _selectionBg);
        _searchBg = resolveSearchBg(_config);
        _searchFg = resolveSearchFg(_config, _searchBg);
        _linkFg = resolveLinkFg(_config);
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

        // Set initial viewport and calculate terminal size
        int width, height;
        _window.getFramebufferSize(width, height);
        _glContext.setViewport(width, height);
        _renderer.setViewport(width, height);
        _cols = width / _cellWidth;
        _rows = height / _cellHeight;

        // Create terminal emulator
        _emulator = new PureDEmulator(_cols, _rows, this);
        _rawCursorStyle = _emulator.cursorStyle;
        refreshCursorSettings();
        initializeFrames();

        // Create input handling
        _inputHandler = new InputHandler();
        _scrollback = new ScrollbackViewport(_rows);
        _scrollbackBuffer = new ScrollbackBuffer();
        _scrollbackMutex = new Mutex();
        _scrollbackMaxLines = _config.scrollbackMaxLines;
        _scrollbackBuffer.initialize(_cols, _scrollbackMaxLines);
        _lastScrollbackCount = 0;
        _selection = new Selection((col, row) => getCharAt(col, row));

        // Create and spawn PTY
        _pty = new PTY();
        if (!_pty.spawn(cast(ushort)_cols, cast(ushort)_rows)) {
            stderr.writefln("Error: Failed to spawn PTY");
            _window.terminate();
            return false;
        }

        _titleMutex = new Mutex();
        _shellTitle = "";

        _parserWorker = new ParserWorker(
            _emulator,
            _frames,
            _scrollbackBuffer,
            _scrollbackMutex,
            _scrollbackMaxLines
        );
        _parserWorker.start();

        _ptyReader = new PtyReader(_pty.masterFd);
        _ptyReader.start((data) => _parserWorker.enqueue(data));

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
        writefln("  PTY: master fd=%d", _pty.masterFd);

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
                    spawnNewInstance();
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
        refreshCursorSettings();
        _selectionBg = resolveSelectionBg(_config);
        _selectionFg = resolveSelectionFg(_config, _selectionBg);
        _searchBg = resolveSearchBg(_config);
        _searchFg = resolveSearchFg(_config, _searchBg);
        _linkFg = resolveLinkFg(_config);

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
            if (_parserWorker !is null) {
                _parserWorker.setScrollbackMaxLines(_scrollbackMaxLines);
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

    void triggerSearch() {
        string query;
        if (_selection.hasSelection) {
            query = _selection.getSelectedText((col, row) => getCharAt(col, row), _cols);
        }
        if (query.length == 0) {
            query = _searchQuery;
        }
        if (query.length == 0) {
            return;
        }
        _searchQuery = query;
        _searchMatchLen = countCodepoints(query);
        if (_searchMatchLen == 0) {
            _searchMatchLen = 1;
        }

        _searchHits.length = 0;
        size_t sbCount = 0;
        if (_scrollbackBuffer !is null && _scrollbackMutex !is null) {
            _scrollbackMutex.lock();
            sbCount = _scrollbackBuffer.lineCount;
            _searchHits = findInScrollback(_scrollbackBuffer, query, 512);
            _scrollbackMutex.unlock();
        }

        auto ref liveFrame = _frames.readBuffer;
        auto frameHits = findInFrame(liveFrame, query, sbCount, 512, _searchHits.length);
        if (frameHits.length) {
            _searchHits ~= frameHits;
        }
        _searchGeneration++;
        _searchIndex = 0;
        applySearchHit();
    }

    void nextSearchHit(bool backwards) {
        if (_searchHits.length == 0) {
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
        if (_searchIndex < 0) {
            _searchIndex = cast(int)_searchHits.length - 1;
        }
        if (_searchIndex >= cast(int)_searchHits.length) {
            _searchIndex = 0;
        }
        auto hit = _searchHits[_searchIndex];
        size_t sbCount = getScrollbackCount();
        int bufferRow;
        if (hit.line < sbCount) {
            int offset = cast(int)(sbCount - hit.line);
            _scrollback.scrollTo(offset);
            bufferRow = cast(int)hit.line - cast(int)sbCount;
        } else {
            _scrollback.scrollToBottom();
            bufferRow = cast(int)(hit.line - sbCount);
        }
        int startCol = cast(int)hit.column;
        int endCol = startCol + cast(int)_searchMatchLen - 1;
        if (endCol < startCol) {
            endCol = startCol;
        }
        if (endCol >= _cols) {
            endCol = _cols - 1;
        }
        _selection.start(startCol, bufferRow, SelectionType.character);
        _selection.update(endCol, bufferRow);
        _selection.finish();
    }

    SearchRange[] buildSearchRanges(ref TerminalFrame frame) {
        size_t sbCount = getScrollbackCount();
        int currentOffset = _scrollback.offset;
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

        long topIndex = cast(long)sbCount - _scrollback.offset;
        long bottomIndex = topIndex + frame.rows - 1;

        if (_searchRanges.length < _searchHits.length) {
            _searchRanges.length = _searchHits.length;
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

        size_t count = 0;
        _hyperlinks.length = 0;

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

        if (_ipcServer !is null) {
            _ipcServer.stop();
            _ipcServer = null;
        }
        if (_ptyReader !is null) {
            _ptyReader.stop();
            _ptyReader = null;
        }
        if (_parserWorker !is null) {
            _parserWorker.stop();
            _parserWorker = null;
        }
        if (_pty !is null) {
            _pty.close();
            _pty = null;
        }
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
        if (_titleMutex is null) {
            _shellTitle = title;
            return;
        }
        _titleMutex.lock();
        scope(exit) _titleMutex.unlock();
        _shellTitle = title;
    }

    void onSendToApplication(scope const(void)[] data) {
        // This is called when the emulator wants to send data to the PTY
        // (e.g., response to terminal queries)
        if (_pty !is null && _pty.isOpen) {
            _pty.write(cast(const(ubyte)[])data);
        }
    }

    void onBell() {
        atomicStore!(MemoryOrder.raw)(_bellTriggered, true);
    }

    void onRequestExit() {
        atomicStore!(MemoryOrder.raw)(_exitRequested, true);
    }

    void onCursorStyleChanged(TerminalEmulator.CursorStyle style) {
        _rawCursorStyle = style;
        if (!_cursorStyleOverride) {
            _cursorStyle = mapCursorStyle(style);
        }
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

private:
    /**
     * Read available PTY output and feed to emulator.
     */
    void checkPtyExit() {
        if (_pty is null || !_pty.isOpen) return;

        // Check if child exited
        if (_pty.checkChild()) {
            writefln("Shell exited with status %d", _pty.exitStatus);
            _window.close();
            return;
        }
    }

    /**
     * Render a frame.
     */
    void render() {
        // Clear framebuffer
        _glContext.setClearColor(0.1f, 0.1f, 0.15f, 1.0f);  // Dark terminal background
        _glContext.clear();

        // Render terminal cells using the cell renderer
        bool hasNewFrame = _frames.consume();
        auto ref liveFrame = _frames.readBuffer;
        bool cursorVisible = true;

        if (hasNewFrame && liveFrame.sequence != _lastFrameSequence) {
            auto now = MonoTime.currTime;
            auto latencyUs = (now - liveFrame.publishTime).total!"usecs";
            _lastFrameSequence = liveFrame.sequence;
            _latencyMs = latencyUs / 1000.0;
            if (_latencyAvgMs == 0.0) {
                _latencyAvgMs = _latencyMs;
            } else {
                _latencyAvgMs = _latencyAvgMs * 0.9 + _latencyMs * 0.1;
            }
        }

        if (hasNewFrame) {
            applyInputModes(liveFrame);
        }
        bool scrollbackChanged = hasNewFrame ? updateScrollbackState() : false;
        if (_scrollback.offset > 0) {
            if (hasNewFrame || scrollbackChanged || _scrollback.offset != _lastScrollbackOffset) {
                composeScrollbackFrame(liveFrame, _scrollback.offset);
            }
            cursorVisible = false;
        }
        _lastScrollbackOffset = _scrollback.offset;

        if (_renderer !is null) {
            auto ref renderFrame = _scrollback.offset > 0 ? _scrollFrame : liveFrame;
            auto searchRanges = buildSearchRanges(renderFrame);
            bool sequenceChanged = hasNewFrame && liveFrame.sequence != _lastHyperlinkSequence;
            if (sequenceChanged) {
                _lastHyperlinkSequence = liveFrame.sequence;
            }
            bool refreshLinks = sequenceChanged ||
                                scrollbackChanged ||
                                _scrollback.offset != _lastHyperlinkOffset;
            updateHyperlinkRanges(renderFrame, refreshLinks);
            if (refreshLinks) {
                _lastHyperlinkOffset = _scrollback.offset;
            }
            _renderer.setBellIntensity(_bellIntensity);
            _renderer.render(renderFrame, cursorVisible, _selection, _scrollback.offset,
                _selectionBg, _selectionFg, searchRanges, _searchBg, _searchFg,
                _hyperlinks, _linkFg, _cursorStyle, _cursorThickness);
        }

        // Update window title with stats periodically
        if (_frameCount % 60 == 0) {
            string shellTitle;
            if (_titleMutex !is null) {
                _titleMutex.lock();
                shellTitle = _shellTitle;
                _titleMutex.unlock();
            } else {
                shellTitle = _shellTitle;
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
        auto ref frame = _frames.readBuffer;
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
            if (_parserWorker !is null) {
                auto totalBytes = _parserWorker.totalBytesProcessed();
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

        // Recalculate terminal dimensions
        int newCols = width / _cellWidth;
        int newRows = height / _cellHeight;

        if (newCols != _cols || newRows != _rows) {
            _cols = newCols;
            _rows = newRows;

            // Resize PTY
            if (_pty !is null && _pty.isOpen) {
                _pty.resize(cast(ushort)_cols, cast(ushort)_rows);
            }

            // Resize emulator
            resizeFrameBuffers(_cols, _rows);
            _scrollback.resize(_rows);
            if (_parserWorker !is null) {
                _parserWorker.resize(_cols, _rows);
            } else {
                updateFrameFromEmulator();
                _frames.publish();
                _frames.consume();
            }

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
        // Close on Ctrl+Q (keep as hardcoded shortcut)
        if (action == GLFW_PRESS && key == GLFW_KEY_Q && (mods & GLFW_MOD_CONTROL)) {
            _window.close();
            return;
        }

        if (action == GLFW_PRESS &&
            key == GLFW_KEY_F &&
            (mods & GLFW_MOD_CONTROL) &&
            (mods & GLFW_MOD_SHIFT)) {
            triggerSearch();
            return;
        }

        if (action == GLFW_PRESS && key == GLFW_KEY_F3) {
            bool backwards = (mods & GLFW_MOD_SHIFT) != 0;
            nextSearchHit(backwards);
            return;
        }

        // Handle scrollback navigation (Shift+PageUp/PageDown)
        if (action == GLFW_PRESS || action == GLFW_REPEAT) {
            if (mods & GLFW_MOD_SHIFT) {
                if (key == GLFW_KEY_PAGE_UP) {
                    _scrollback.scrollPages(1);
                    return;
                } else if (key == GLFW_KEY_PAGE_DOWN) {
                    _scrollback.scrollPages(-1);
                    return;
                } else if (key == GLFW_KEY_HOME) {
                    _scrollback.scrollToTop();
                    return;
                } else if (key == GLFW_KEY_END) {
                    _scrollback.scrollToBottom();
                    return;
                }
            }
        }

        if (action == GLFW_PRESS) {
            bool ctrl = (mods & GLFW_MOD_CONTROL) != 0;
            bool shift = (mods & GLFW_MOD_SHIFT) != 0;

            if (ctrl && shift && key == GLFW_KEY_C) {
                copySelectionToClipboard();
                return;
            }
            if (ctrl && shift && key == GLFW_KEY_V) {
                string text = _clipboard is null ? "" : _clipboard.requestClipboard();
                pasteText(text);
                return;
            }
            if (shift && key == GLFW_KEY_INSERT) {
                string text = _clipboard is null ? "" : _clipboard.requestClipboard();
                pasteText(text);
                return;
            }
        }

        // Handle special keys via InputHandler
        if (action == GLFW_PRESS || action == GLFW_REPEAT) {
            auto escSeq = _inputHandler.translateKey(key, scancode, action, mods);
            if (escSeq !is null) {
                sendToPty(escSeq);
            }
        }
    }

    /**
     * Handle character input (Unicode).
     */
    void onChar(uint codepoint) {
        if (_pty is null || !_pty.isOpen) return;

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
        int col = cast(int)(_mouseX / _cellWidth);
        int row = cast(int)(_mouseY / _cellHeight);

        // Clamp to valid range
        col = col < 0 ? 0 : (col >= _cols ? _cols - 1 : col);
        row = row < 0 ? 0 : (row >= _rows ? _rows - 1 : row);

        // Convert to buffer coordinates (account for scrollback)
        int bufferRow = _scrollback.bufferRow(row);

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
                int clickCount = _clickDetector.click(col, bufferRow);
                auto selType = _clickDetector.selectionType();

                if (mods & GLFW_MOD_SHIFT) {
                    // Shift+click extends selection
                    _selection.extend(col, bufferRow);
                } else {
                    // Start new selection
                    _selection.start(col, bufferRow, selType);
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

            if (button == GLFW_MOUSE_BUTTON_LEFT && _selection.active) {
                _selection.finish();
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
        int col = cast(int)(_mouseX / _cellWidth);
        int row = cast(int)(_mouseY / _cellHeight);

        // If mouse mode is active, send to application
        if (_inputHandler.mouseMode != MouseMode.none) {
            auto data = _inputHandler.translateScroll(xoffset, yoffset, 0, col, row);
            if (data !is null) {
                sendToPty(data);
            }
        } else {
            // Otherwise, scroll the viewport
            _scrollback.handleScrollWheel(yoffset);
        }
    }

    /**
     * Handle mouse cursor position updates.
     */
    void onCursorPos(double xpos, double ypos) {
        _mouseX = xpos;
        _mouseY = ypos;

        int col = cast(int)(xpos / _cellWidth);
        int row = cast(int)(ypos / _cellHeight);

        // Clamp to valid range
        col = col < 0 ? 0 : (col >= _cols ? _cols - 1 : col);
        row = row < 0 ? 0 : (row >= _rows ? _rows - 1 : row);

        int bufferRow = _scrollback.bufferRow(row);

        // Update selection if dragging
        if (_selection.active && (_mouseButtons & 1)) {
            _selection.update(col, bufferRow);
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
        if (_pty !is null && _pty.isOpen && data.length > 0) {
            _pty.write(data);
        }
    }

    void pasteText(string text) {
        if (_pty is null || !_pty.isOpen || text.length == 0) {
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
        if (_clipboard is null || !_selection.hasSelection) {
            return;
        }
        auto text = _selection.getSelectedText((col, row) => getCharAt(col, row), _cols);
        if (text.length == 0) {
            return;
        }
        _clipboard.setPrimary(text);
    }

    void copySelectionToClipboard() {
        if (_clipboard is null || !_selection.hasSelection) {
            return;
        }
        auto text = _selection.getSelectedText((col, row) => getCharAt(col, row), _cols);
        if (text.length == 0) {
            return;
        }
        _clipboard.setClipboard(text);
    }

    /**
     * Get character at buffer position (for selection word detection).
     */
    dchar getCharAt(int col, int row) {
        auto ref frame = _frames.readBuffer;
        if (frame.cols <= 0 || frame.rows <= 0) return ' ';
        if (col < 0 || col >= frame.cols) return ' ';

        size_t sbCount = getScrollbackCount();
        long globalIndex = cast(long)sbCount + row;
        if (globalIndex < 0) return ' ';

        if (globalIndex < cast(long)sbCount) {
            auto cell = getScrollbackCell(cast(size_t)globalIndex, col);
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

    void initializeFrames() {
        _frames.reset();
        resizeFrameBuffers(_cols, _rows);
        updateFrameFromEmulator();
        _frames.publish();
        _frames.consume();
    }

    void resizeFrameBuffers(int cols, int rows) {
        foreach (i; 0 .. 3) {
            _frames.bufferAt(i).ensureSize(cols, rows);
        }
        if (_renderer !is null) {
            _renderer.prepareBuffers(cols, rows);
        }
    }

    void updateFrameFromEmulator() {
        if (_emulator is null) return;
        auto screen = _emulator.getScreenBuffer();
        auto ref back = _frames.writeBuffer;
        back.updateFromCells(
            screen,
            _emulator.cols,
            _emulator.rows,
            _emulator.cursorCol,
            _emulator.cursorRow,
            _emulator.isAlternateScreen,
            _emulator.applicationCursorMode,
            _emulator.mouseMode,
            _emulator.mouseEncoding,
            _emulator.bracketedPasteModeEnabled,
            _emulator.focusReportingEnabled
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

    bool updateScrollbackState() {
        size_t sbCount = getScrollbackCount();
        if (sbCount > _lastScrollbackCount) {
            _scrollback.linesAdded(cast(int)(sbCount - _lastScrollbackCount));
        } else if (sbCount < _lastScrollbackCount) {
            _scrollback.clear();
            _scrollback.linesAdded(cast(int)sbCount);
        }
        bool changed = sbCount != _lastScrollbackCount;
        _lastScrollbackCount = sbCount;
        return changed;
    }

    size_t getScrollbackCount() {
        if (_scrollbackBuffer is null || _scrollbackMutex is null) {
            return 0;
        }
        _scrollbackMutex.lock();
        scope(exit) _scrollbackMutex.unlock();
        return _scrollbackBuffer.lineCount;
    }

    TerminalEmulator.TerminalCell getScrollbackCell(size_t lineIndex, int col) {
        TerminalEmulator.TerminalCell cell;
        if (_scrollbackBuffer is null || _scrollbackMutex is null) {
            return cell;
        }
        _scrollbackMutex.lock();
        scope(exit) _scrollbackMutex.unlock();
        auto line = _scrollbackBuffer.lineView(lineIndex);
        if (line !is null && col >= 0 && col < line.length) {
            cell = line[cast(size_t)col];
        }
        return cell;
    }

    void composeScrollbackFrame(ref TerminalFrame liveFrame, int offset) {
        _scrollFrame.ensureSize(liveFrame.cols, liveFrame.rows);
        _scrollFrame.cursorCol = liveFrame.cursorCol;
        _scrollFrame.cursorRow = liveFrame.cursorRow;
        _scrollFrame.alternateScreen = liveFrame.alternateScreen;

        int rows = liveFrame.rows;
        int cols = liveFrame.cols;
        size_t sbCount = 0;

        _scrollbackMutex.lock();
        sbCount = _scrollbackBuffer !is null ? _scrollbackBuffer.lineCount : 0;

        long topIndex = cast(long)sbCount - offset;
        foreach (row; 0 .. rows) {
            long globalIndex = topIndex + row;
            auto dest = _scrollFrame.cells[(row * cols) .. ((row + 1) * cols)];

            if (globalIndex < 0) {
                fillBlankLine(dest);
                continue;
            }

            if (globalIndex < cast(long)sbCount) {
                auto line = _scrollbackBuffer.lineView(cast(size_t)globalIndex);
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
        _scrollbackMutex.unlock();
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
