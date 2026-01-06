module pured.ipc.server;

version (PURE_D_BACKEND):

import capnproto.FileDescriptor : FileDescriptor;
import capnproto.MessageBuilder : MessageBuilder;
import capnproto.SerializePacked : SerializePacked;
import core.atomic : atomicLoad, atomicStore, MemoryOrder;
import core.sync.mutex : Mutex;
import core.thread : Thread;
import core.sys.posix.sys.socket : socket, bind, listen, accept, sockaddr, AF_UNIX, SOCK_STREAM;
import core.sys.posix.sys.un : sockaddr_un;
import core.sys.posix.unistd : close, unlink;
import core.stdc.errno : errno, EINTR;
import std.stdio : stderr, writefln, File;
import std.string : toStringz;
import pured.ipc.tilix_capnp : Request, Response, Command;

enum IpcCommandType {
    newTab,
    pasteText,
    setTitle,
    spawnProfile,
}

struct IpcCommand {
    IpcCommandType type;
    string payload;
    ulong id;
}

class IpcServer {
private:
    string _socketPath;
    int _serverFd = -1;
    Thread _thread;
    Mutex _queueMutex;
    IpcCommand[] _queue;
    shared bool _running;

public:
    this(string socketPath) {
        _socketPath = socketPath;
        _queueMutex = new Mutex();
    }

    void start() {
        if (isRunning) {
            return;
        }
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
        if (_serverFd >= 0) {
            close(_serverFd);
            _serverFd = -1;
        }
        if (_thread !is null) {
            _thread.join();
            _thread = null;
        }
        if (_socketPath.length) {
            unlink(_socketPath.toStringz);
        }
    }

    @property bool isRunning() const {
        return atomicLoad!(MemoryOrder.raw)(_running);
    }

    bool pollCommand(out IpcCommand cmd) {
        _queueMutex.lock();
        scope(exit) _queueMutex.unlock();
        if (_queue.length == 0) {
            return false;
        }
        cmd = _queue[0];
        _queue = _queue[1 .. $];
        return true;
    }

private:
    void runLoop() {
        if (!setupSocket()) {
            return;
        }

        while (atomicLoad!(MemoryOrder.raw)(_running)) {
            int client = accept(_serverFd, null, null);
            if (client < 0) {
                if (errno == EINTR) {
                    continue;
                }
                if (!atomicLoad!(MemoryOrder.raw)(_running)) {
                    break;
                }
                continue;
            }
            handleClient(client);
        }
    }

    bool setupSocket() {
        if (_socketPath.length == 0) {
            return false;
        }

        _serverFd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (_serverFd < 0) {
            stderr.writefln("IPC: failed to create socket");
            return false;
        }

        unlink(_socketPath.toStringz);

        sockaddr_un addr;
        addr.sun_family = AF_UNIX;
        if (_socketPath.length + 1 > addr.sun_path.length) {
            stderr.writefln("IPC: socket path too long: %s", _socketPath);
            close(_serverFd);
            _serverFd = -1;
            return false;
        }
        foreach (i; 0 .. _socketPath.length) {
            addr.sun_path[i] = _socketPath[i];
        }
        addr.sun_path[_socketPath.length] = 0;

        if (bind(_serverFd, cast(sockaddr*)&addr, cast(uint)addr.sizeof) != 0) {
            stderr.writefln("IPC: bind failed");
            return false;
        }
        if (listen(_serverFd, 8) != 0) {
            stderr.writefln("IPC: listen failed");
            return false;
        }
        return true;
    }

    void handleClient(int fd) {
        try {
            File file;
            bool opened = false;
            scope(exit) {
                if (!opened) {
                    close(fd);
                }
            }
            file.fdopen(fd, "r+b");
            opened = true;
            auto descriptor = new FileDescriptor(file);
            auto message = SerializePacked.readFromUnbuffered(descriptor);
            auto request = message.getRoot!Request;
            auto cmd = request.getCommand();
            IpcCommand command;
            command.id = request.getId();

            bool ok = true;
            string responseMessage = "queued";

            switch (cmd.which()) {
                case Command.Which.newTab:
                    command.type = IpcCommandType.newTab;
                    break;
                case Command.Which.pasteText:
                    command.type = IpcCommandType.pasteText;
                    command.payload = cmd.getPasteText();
                    break;
                case Command.Which.setTitle:
                    command.type = IpcCommandType.setTitle;
                    command.payload = cmd.getSetTitle();
                    break;
                case Command.Which.spawnProfile:
                    command.type = IpcCommandType.spawnProfile;
                    command.payload = cmd.getSpawnProfile();
                    break;
                case Command.Which._NOT_IN_SCHEMA:
                    ok = false;
                    responseMessage = "unknown command";
                    break;
                default:
                    ok = false;
                    responseMessage = "unknown command";
                    break;
            }

            if (ok) {
                enqueue(command);
            }

            MessageBuilder responseMessageBuilder;
            auto response = responseMessageBuilder.initRoot!Response;
            response.setId(command.id);
            response.setOk(ok);
            response.setMessage(responseMessage);
            SerializePacked.writeToUnbuffered(descriptor, responseMessageBuilder);
        } catch (Exception ex) {
            stderr.writefln("IPC: failed to handle client: %s", ex.msg);
        }
    }

    void enqueue(IpcCommand command) {
        _queueMutex.lock();
        _queue ~= command;
        _queueMutex.unlock();
    }
}
