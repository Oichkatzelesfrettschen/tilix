@0xdbb7c7cb7aa3a1d4;

using D = import "/capnp/dlang.capnp";

$D.module("pured.ipc.tilix_capnp");

struct SplitPaneRequest {
  orientation @0 :Text;  # "vertical" or "horizontal"
}

struct Command {
  union {
    newTab @0 :Void;
    pasteText @1 :Text;
    setTitle @2 :Text;
    spawnProfile @3 :Text;
    splitPane @4 :SplitPaneRequest;
    closeTab @5 :Void;
    focusNextTab @6 :Void;
    focusPrevTab @7 :Void;
  }
}

struct Request {
  id @0 :UInt64;
  command @1 :Command;
}

struct Response {
  id @0 :UInt64;
  ok @1 :Bool;
  message @2 :Text;
}
