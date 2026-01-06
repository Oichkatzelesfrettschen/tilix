/**
 * PTY Reader (epoll)
 *
 * Background PTY reader thread using epoll for low-latency input.
 * The callback is invoked with a slice that is only valid during the call.
 */
module pured.ptyreader;

version (PURE_D_BACKEND):

import core.atomic : atomicLoad, atomicStore, MemoryOrder;
import core.sys.linux.epoll;
import core.sys.posix.unistd : read, close;
import core.stdc.errno : errno, EAGAIN, EWOULDBLOCK, EINTR;
import core.thread : Thread;
import std.stdio : stderr, writefln;

class PtyReader {
private:
    int _fd = -1;
    size_t _bufferSize;
    Thread _thread;
    shared bool _running;
    void delegate(const(ubyte)[]) _onData;

public:
    this(int fd, size_t bufferSize = 16 * 1024) {
        _fd = fd;
        _bufferSize = bufferSize;
    }

    void start(void delegate(const(ubyte)[]) onData) {
        if (_fd < 0) {
            stderr.writefln("PTY reader: invalid fd");
            return;
        }
        if (isRunning) {
            return;
        }
        _onData = onData;
        atomicStore!(MemoryOrder.raw)(_running, true);
        _thread = new Thread(&runLoop);
        _thread.isDaemon = true;
        _thread.start();
    }

    void stop() {
        if (!isRunning) {
            return;
        }
        atomicStore!(MemoryOrder.raw)(_running, false);
        if (_thread !is null) {
            _thread.join();
            _thread = null;
        }
    }

    @property bool isRunning() const {
        return atomicLoad!(MemoryOrder.raw)(_running);
    }

private:
    void runLoop() {
        int epfd = epoll_create1(0);
        if (epfd < 0) {
            stderr.writefln("PTY reader: epoll_create1 failed");
            return;
        }
        scope(exit) close(epfd);

        epoll_event ev;
        ev.events = EPOLLIN | EPOLLERR | EPOLLHUP;
        ev.data.fd = _fd;

        if (epoll_ctl(epfd, EPOLL_CTL_ADD, _fd, &ev) != 0) {
            stderr.writefln("PTY reader: epoll_ctl failed");
            return;
        }

        ubyte[] buffer = new ubyte[_bufferSize];
        epoll_event[1] events;

        while (atomicLoad!(MemoryOrder.raw)(_running)) {
            int n = epoll_wait(epfd, events.ptr, 1, 50);
            if (n < 0) {
                if (errno == EINTR) {
                    continue;
                }
                break;
            }
            if (n == 0) {
                continue;
            }

            auto flags = events[0].events;
            if ((flags & (EPOLLERR | EPOLLHUP)) != 0) {
                break;
            }

            if ((flags & EPOLLIN) != 0) {
                for (;;) {
                    auto r = read(_fd, buffer.ptr, buffer.length);
                    if (r > 0) {
                        if (_onData !is null) {
                            _onData(buffer[0 .. r]);
                        }
                    } else if (r == 0) {
                        atomicStore!(MemoryOrder.raw)(_running, false);
                        return;
                    } else {
                        if (errno == EAGAIN || errno == EWOULDBLOCK) {
                            break;
                        }
                        if (errno == EINTR) {
                            continue;
                        }
                        atomicStore!(MemoryOrder.raw)(_running, false);
                        return;
                    }
                }
            }
        }
    }
}
