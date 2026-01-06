# Mmap Scrollback Buffer

`ScrollbackBuffer` provides a fixed-size, mmap-backed ring of `TerminalCell` lines
to support large scrollback histories without allocating on the GC heap.

## Status
- Implemented as a standalone buffer (`pured/terminal/scrollback_buffer.d`).
- Not yet wired into the renderer or selection path.

## API Sketch
```d
auto buffer = new ScrollbackBuffer();
buffer.initialize(cols, 200_000);
buffer.pushLine(lineCells);
auto view = buffer.lineView(0); // oldest line
```
