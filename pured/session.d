/**
 * Terminal session encapsulating PTY, emulator, parser, and scrollback buffer.
 */
module pured.session;

version (PURE_D_BACKEND):

import pured.pty;
import pured.ptyreader;
import pured.emulator;
import pured.parserworker;
import pured.terminal.frame : TerminalFrame;
import pured.terminal.scrollback_buffer : ScrollbackBuffer;
import pured.util.triplebuffer : TripleBuffer;
import core.sync.mutex : Mutex;
import std.stdio : stderr;

class TerminalSession {
public:
    PTY pty;
    PtyReader ptyReader;
    PureDEmulator emulator;
    ParserWorker parserWorker;
    TripleBuffer!TerminalFrame frames;
    ScrollbackBuffer scrollbackBuffer;
    Mutex scrollbackMutex;
    TerminalFrame scrollFrame;
    size_t scrollbackMaxLines;

    this() {
        scrollbackMutex = new Mutex();
    }

    bool initialize(int cols, int rows, ITerminalCallbacks callbacks,
            size_t maxScrollbackLines) {
        scrollbackMaxLines = maxScrollbackLines;
        frames.reset();
        emulator = new PureDEmulator(cols, rows, callbacks);
        scrollbackBuffer = new ScrollbackBuffer();
        scrollbackBuffer.initialize(cols, scrollbackMaxLines);

        parserWorker = new ParserWorker(
            emulator,
            frames,
            scrollbackBuffer,
            scrollbackMutex,
            scrollbackMaxLines
        );

        pty = new PTY();
        if (!pty.spawn(cast(ushort)cols, cast(ushort)rows)) {
            stderr.writefln("Error: Failed to spawn PTY");
            return false;
        }

        ptyReader = new PtyReader(pty.masterFd);
        return true;
    }

    void start() {
        if (parserWorker !is null) {
            parserWorker.start();
        }
        if (ptyReader !is null) {
            ptyReader.start((data) => parserWorker.enqueue(data));
        }
    }

    void stop() {
        if (ptyReader !is null) {
            ptyReader.stop();
            ptyReader = null;
        }
        if (parserWorker !is null) {
            parserWorker.stop();
            parserWorker = null;
        }
        if (pty !is null) {
            pty.close();
            pty = null;
        }
    }

    void resize(int cols, int rows) {
        if (pty !is null && pty.isOpen) {
            pty.resize(cast(ushort)cols, cast(ushort)rows);
        }
        if (parserWorker !is null) {
            parserWorker.resize(cols, rows);
        }
    }

    @property bool isOpen() const {
        return pty !is null && pty.isOpen;
    }
}
