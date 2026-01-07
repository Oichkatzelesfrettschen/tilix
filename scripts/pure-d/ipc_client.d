module ipc_client;

import capnproto.FileDescriptor : FileDescriptor;
import capnproto.MessageBuilder : MessageBuilder;
import capnproto.SerializePacked : SerializePacked;
import core.stdc.errno : errno;
import core.sys.posix.sys.socket : socket, connect, AF_UNIX, SOCK_STREAM, sockaddr;
import core.sys.posix.sys.un : sockaddr_un;
import core.sys.posix.unistd : close;
import std.path : buildPath;
import std.process : environment;
import std.stdio : stderr, writeln, File;
import std.string : toStringz;
import pured.ipc.tilix_capnp : Request, Response, Command;

void main(string[] args) {
    if (args.length < 2) {
        stderr.writeln("Usage: ipc_client <new-tab|paste|set-title|spawn-profile|split-vertical|split-horizontal|close-tab|focus-next-tab|focus-prev-tab> [payload]");
        return;
    }

    string runtimeDir = environment.get("XDG_RUNTIME_DIR", "");
    if (runtimeDir.length == 0) {
        runtimeDir = "/tmp";
    }
    auto socketPath = buildPath(runtimeDir, "tilix-pure.sock");

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        stderr.writeln("Failed to create socket.");
        return;
    }
    scope(exit) close(fd);

    sockaddr_un addr;
    addr.sun_family = AF_UNIX;
    if (socketPath.length + 1 > addr.sun_path.length) {
        stderr.writeln("Socket path too long.");
        return;
    }
    foreach (i; 0 .. socketPath.length) {
        addr.sun_path[i] = socketPath[i];
    }
    addr.sun_path[socketPath.length] = 0;

    if (connect(fd, cast(sockaddr*)&addr, cast(uint)addr.sizeof) != 0) {
        stderr.writeln("Failed to connect to IPC socket.");
        return;
    }

    MessageBuilder builder;
    auto request = builder.initRoot!Request;
    request.setId(1);
    auto command = request.initCommand();

    string action = args[1];
    string payload = args.length > 2 ? args[2] : "";

    if (action == "new-tab") {
        command.setNewTab();
    } else if (action == "paste") {
        command.setPasteText(payload);
    } else if (action == "set-title") {
        command.setSetTitle(payload);
    } else if (action == "spawn-profile") {
        command.setSpawnProfile(payload);
    } else if (action == "split-vertical" || action == "split-horizontal") {
        auto split = command.initSplitPane();
        split.setOrientation(action == "split-horizontal" ? "horizontal" : "vertical");
    } else if (action == "close-tab") {
        command.setCloseTab();
    } else if (action == "focus-next-tab") {
        command.setFocusNextTab();
    } else if (action == "focus-prev-tab") {
        command.setFocusPrevTab();
    } else {
        stderr.writeln("Unknown command: ", action);
        return;
    }

    File file;
    file.fdopen(fd, "r+b");
    auto descriptor = new FileDescriptor(file);
    SerializePacked.writeToUnbuffered(descriptor, builder);

    auto responseMessage = SerializePacked.readFromUnbuffered(descriptor);
    auto response = responseMessage.getRoot!Response;
    writeln("ok=", response.getOk(), " message=", response.getMessage());
}
