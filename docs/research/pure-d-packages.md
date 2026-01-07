# Pure D Package Audit (2026-01-07)

This document lists DUB packages relevant to the Pure D rebuild and their
latest versions as reported by `https://code.dlang.org/api/packages/<pkg>/latest`.

## Core packages in use
- mir-algorithm 3.22.4 (ndslice, numeric core)
- intel-intrinsics 1.13.0 (SIMD)
- bindbc-opengl 1.1.1 (OpenGL)
- bindbc-glfw 1.1.2 (windowing/input)
- bindbc-freetype 1.3.3 (glyph rasterization)
- bindbc-harfbuzz 0.2.1 (text shaping)
- bindbc-fontconfig 1.0.0 (font discovery)
- bindbc-loader 1.1.5 (OpenGL loader)
- arsd-official:terminalemulator 12.1.0 (terminal state machine)
- capnproto-dlang 0.1.2 (IPC serialization + D bindings)

## Additional candidates
- mir-glas 0.2.4 (BLAS/LAPACK-style math)
- mir-ion 2.3.5 (fast JSON/YAML/Msgpack)
- mir-toml 0.1.1 (TOML frontend)
- xkbcommon-d 0.5.1 (keymap handling)
- xcb-d 2.1.1+1.11.1 (XCB binding)
- xcb-util-wm-d 0.5.0+0.4.1 (EWMH/ICCCM)
- wayland-client-d 1.8.90 (Wayland client bindings)
- wayland-scanner-d 1.0.0 (Wayland protocol scanner)
- fswatch 0.6.1 (cross-platform file watcher)
- dinotify 0.5.0 (Linux inotify wrapper)
- msgpack-ll 0.1.4 (nogc MessagePack; crash snapshots)
- msgpack-d 1.0.5 (MessagePack serialization)
- zstd 0.2.1 (Zstandard compression)
- zased 0.1.1 (static Zstd variant)
- lz4-d ~master (LZ4 binding)
- sqlite3 1.0.0 (snapshot or telemetry storage)

## Registry scan (dub search, 2026-01-07)
- xcb-d 2.1.1+1.11.1 (XCB bindings)
- xcb-util-wm-d 0.5.0+0.4.1 (EWMH/ICCCM helpers)
- xkbcommon-d 0.5.1 (keyboard mapping)
- wayland 0.4.0 (Wayland bindings)
- wayland-client-d 1.8.90 (Wayland client)
- wayland-scanner-d 1.0.0 (protocol scanner)
- capnproto-dlang 0.1.2 (pure D Cap'n Proto bindings)

## Not found (via dub search)
- bindbc-xcb
- bindbc-xkbcommon
- bindbc-x11
- bindbc-wayland

## Notes
- For XPresent/low-latency swaps, use xcb-d + xcb-util-wm-d.
- HarfBuzz + Fontconfig are recommended for shaping + fallback fonts.
- Use wayland-client-d + wayland-scanner-d for Wayland protocol integration.
- fswatch/dinotify can replace polling for config hot reload.
- Compression/serialization libs can back crash recovery snapshots.
