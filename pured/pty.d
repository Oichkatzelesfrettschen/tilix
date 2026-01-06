/**
 * PTY (Pseudo-Terminal) Management
 *
 * Provides PTY creation and I/O for spawning shell processes.
 * Uses POSIX PTY APIs for Linux compatibility.
 *
 * Key features:
 * - Fork shell process with PTY
 * - Non-blocking read from PTY master
 * - Write input to PTY master
 * - Terminal size management (TIOCSWINSZ)
 *
 * Copyright: 2026
 * License: MPL-2.0
 */
module pured.pty;

version (PURE_D_BACKEND):

import core.sys.posix.unistd;
import core.sys.posix.fcntl;
import core.sys.posix.signal;
import core.sys.posix.sys.wait;
import core.sys.posix.termios;
import core.sys.posix.sys.ioctl;
import core.stdc.errno;
import core.stdc.string : strerror;
import core.stdc.stdlib : getenv;
import std.string : toStringz, fromStringz;
import std.stdio : stderr, writefln;
import std.conv : to;

/// Window size structure for TIOCSWINSZ
struct winsize {
    ushort ws_row;
    ushort ws_col;
    ushort ws_xpixel;
    ushort ws_ypixel;
}

// PTY ioctls
enum TIOCSWINSZ = 0x5414;
enum TIOCGWINSZ = 0x5413;

// From pty.h - not in core.sys.posix
extern(C) nothrow @nogc {
    int openpty(int* amaster, int* aslave, char* name,
                const termios* termp, const winsize* winp);
    int forkpty(int* amaster, char* name,
                const termios* termp, const winsize* winp);
    int login_tty(int fd);
}

// POSIX functions not in D runtime
extern(C) nothrow @nogc {
    void _exit(int status);
    int setenv(const(char)* name, const(char)* value, int overwrite);
}

/**
 * PTY wrapper for terminal I/O.
 *
 * Manages a pseudo-terminal connected to a shell process.
 */
class PTY {
private:
    int _masterFd = -1;
    pid_t _childPid = -1;
    bool _childExited = false;
    int _exitStatus = 0;

    // Terminal dimensions
    ushort _cols = 80;
    ushort _rows = 24;

public:
    /**
     * Spawn a shell process with PTY.
     *
     * Params:
     *   cols = Terminal width in columns
     *   rows = Terminal height in rows
     *   shell = Shell command (default: user's shell or /bin/sh)
     *
     * Returns: true if spawn succeeded
     */
    bool spawn(ushort cols = 80, ushort rows = 24, string shell = null) {
        _cols = cols;
        _rows = rows;

        // Determine shell to use
        if (shell is null || shell.length == 0) {
            auto shellEnv = getenv("SHELL");
            if (shellEnv !is null) {
                shell = fromStringz(shellEnv).idup;
            } else {
                shell = "/bin/sh";
            }
        }

        // Set up window size
        winsize ws;
        ws.ws_col = cols;
        ws.ws_row = rows;
        ws.ws_xpixel = 0;
        ws.ws_ypixel = 0;

        // Fork with PTY
        _childPid = forkpty(&_masterFd, null, null, &ws);

        if (_childPid < 0) {
            stderr.writefln("PTY: forkpty failed: %s",
                fromStringz(strerror(errno)));
            return false;
        }

        if (_childPid == 0) {
            // Child process - exec shell
            execShell(shell);
            // Should not return
            _exit(1);
        }

        // Parent process
        // Set master FD to non-blocking
        int flags = fcntl(_masterFd, F_GETFL, 0);
        if (flags != -1) {
            fcntl(_masterFd, F_SETFL, flags | O_NONBLOCK);
        }

        return true;
    }

    /**
     * Read available data from PTY.
     *
     * Non-blocking read - returns empty slice if no data available.
     *
     * Params:
     *   buffer = Buffer to read into
     *
     * Returns: Slice of buffer containing read data, or null on error/EOF
     */
    ubyte[] read(ubyte[] buffer) {
        if (_masterFd < 0) return null;

        auto n = core.sys.posix.unistd.read(_masterFd, buffer.ptr, buffer.length);

        if (n > 0) {
            return buffer[0 .. n];
        } else if (n == 0) {
            // EOF - child closed PTY
            return null;
        } else {
            // Error
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                // No data available (non-blocking)
                return buffer[0 .. 0];
            }
            // Real error
            return null;
        }
    }

    /**
     * Write data to PTY (send to shell).
     *
     * Params:
     *   data = Data to write
     *
     * Returns: Number of bytes written, or -1 on error
     */
    ptrdiff_t write(const(ubyte)[] data) {
        if (_masterFd < 0) return -1;

        return core.sys.posix.unistd.write(_masterFd, data.ptr, data.length);
    }

    /**
     * Write string to PTY.
     */
    ptrdiff_t write(string s) {
        return write(cast(const(ubyte)[])s);
    }

    /**
     * Resize the PTY.
     *
     * Params:
     *   cols = New width in columns
     *   rows = New height in rows
     */
    void resize(ushort cols, ushort rows) {
        if (_masterFd < 0) return;

        _cols = cols;
        _rows = rows;

        winsize ws;
        ws.ws_col = cols;
        ws.ws_row = rows;
        ws.ws_xpixel = 0;
        ws.ws_ypixel = 0;

        ioctl(_masterFd, TIOCSWINSZ, &ws);
    }

    /**
     * Check if child process has exited.
     */
    bool checkChild() {
        if (_childPid <= 0 || _childExited) return _childExited;

        int status;
        auto result = waitpid(_childPid, &status, WNOHANG);

        if (result > 0) {
            _childExited = true;
            if (WIFEXITED(status)) {
                _exitStatus = WEXITSTATUS(status);
            } else if (WIFSIGNALED(status)) {
                _exitStatus = 128 + WTERMSIG(status);
            }
        }

        return _childExited;
    }

    /**
     * Close the PTY and terminate child if running.
     */
    void close() {
        if (_masterFd >= 0) {
            core.sys.posix.unistd.close(_masterFd);
            _masterFd = -1;
        }

        if (_childPid > 0 && !_childExited) {
            // Send SIGHUP then SIGKILL if needed
            kill(_childPid, SIGHUP);

            // Wait briefly
            int status;
            auto result = waitpid(_childPid, &status, WNOHANG);
            if (result == 0) {
                // Still running, force kill
                kill(_childPid, SIGKILL);
                waitpid(_childPid, &status, 0);
            }
            _childExited = true;
        }
    }

    /// Get master file descriptor (for polling)
    @property int masterFd() const { return _masterFd; }

    /// Check if PTY is open
    @property bool isOpen() const { return _masterFd >= 0 && !_childExited; }

    /// Get child exit status
    @property int exitStatus() const { return _exitStatus; }

    /// Current columns
    @property ushort cols() const { return _cols; }

    /// Current rows
    @property ushort rows() const { return _rows; }

private:
    /**
     * Execute shell in child process.
     */
    void execShell(string shell) nothrow {
        // Set up environment
        auto term = "xterm-256color".ptr;

        // Standard shell exec with login
        // Note: toStringz allocates, but this is in child process
        // that will immediately exec or _exit, so GC won't run
        const(char)* shellZ;
        try {
            shellZ = shell.toStringz;
        } catch (Exception) {
            shellZ = "/bin/sh".ptr;
        }

        // Use -l for login shell
        const(char)*[3] argv = [shellZ, "-l".ptr, null];

        // Set TERM
        setenv("TERM", term, 1);

        // Exec
        execvp(shellZ, cast(char**)argv.ptr);

        // If exec failed, try /bin/sh
        execl("/bin/sh".ptr, "/bin/sh".ptr, null);
    }
}

// POSIX wait macros
private extern(C) nothrow @nogc {
    bool WIFEXITED(int status) { return (status & 0x7f) == 0; }
    int WEXITSTATUS(int status) { return (status >> 8) & 0xff; }
    bool WIFSIGNALED(int status) { return ((status & 0x7f) + 1) >> 1 > 0; }
    int WTERMSIG(int status) { return status & 0x7f; }
}
