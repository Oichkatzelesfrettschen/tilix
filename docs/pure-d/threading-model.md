# Pure D Threading Model (Draft)

Goal: keep render loop uncapped and isolate PTY I/O + parsing from GPU work.

## Threads
- Render/UI thread: GLFW event loop, OpenGL rendering, input capture.
- PTY reader thread: epoll-based read on PTY master, pushes bytes into ring buffer.
- Parser thread: consumes bytes, feeds `arsd.terminalemulator`, writes frame snapshots.

## Data Flow
1. PTY reader writes raw bytes into a ring buffer with backpressure.
2. Parser thread drains the ring buffer, uses SIMD delimiter scan to chunk input, updates emulator state.
3. Parser thread writes a `TerminalFrame` snapshot into the triple buffer and publishes.
4. Render thread consumes the newest frame and draws without blocking.

## Queues and Handoffs
- Byte ring buffer: single-producer (PTY), single-consumer (parser).
- Frame triple buffer: single-producer (parser), single-consumer (render).
- Input queue: render thread writes input directly to PTY (no extra hop).

## Sync Rules
- No locks on render path; only atomic swaps/loads for frame selection.
- Parser thread never touches GL state.
- Render thread never calls `arsd.terminalemulator` methods.

## Next Implementation Targets
- Epoll loop for PTY reader with wake-up on shutdown.
- Lock-free ring buffer for byte stream (aligned to cache lines).
- Parser thread lifecycle tied to window session.
