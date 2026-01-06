# Mir ndslice Grid Adapter

`TerminalFrame` now exposes a `grid()` view backed by `mir.ndslice` for cache-friendly
row/column traversal without changing the underlying `TerminalCell[]` storage.

## Usage
```d
auto grid = frame.grid();
// grid[row, col] access
```

## Notes
- Storage remains a flat `TerminalCell[]` for compatibility with `arsd.terminalemulator`.
- `grid()` is a view; no copy is created.
