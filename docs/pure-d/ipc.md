# Pure D IPC (Cap'n Proto)

Socket:
- `$XDG_RUNTIME_DIR/tilix-pure.sock` (falls back to `/tmp/tilix-pure.sock`)

Schema:
- `pured/ipc/tilix.capnp`
- Generated D bindings: `pured/ipc/tilix_capnp.d`

Regenerate bindings:
```sh
capnp compile --src-prefix=pured/ipc -o dlang:pured/ipc pured/ipc/tilix.capnp
```

Client (DUB):
```sh
dub build --config=ipc-client
./build/pure/tilix-ipc-client set-title "Pure D IPC"
./build/pure/tilix-ipc-client paste "hello from ipc"
```

Commands:
- `newTab`
- `pasteText`
- `setTitle`
- `spawnProfile`

Notes:
- IPC server runs inside the Pure D backend and queues commands for the main loop.
- `newTab` opens a new scenegraph tab in the running Pure D window.
- `spawnProfile` spawns a new process with `--profile <name>` if provided.
