# Pure D Crash Recovery

The Pure D backend saves a binary snapshot of the visible terminal grid and
restores it on the next launch (best-effort).

Snapshot path:
- `$XDG_RUNTIME_DIR/tilix-pure.snapshot` (falls back to `/tmp/tilix-pure.snapshot`)

Contents:
- Visible grid (`TerminalFrame` cells)
- Cursor position
- Scrollback offset
- Frame sequence number

Notes:
- Snapshots are taken periodically when new frames arrive and on clean shutdown.
- This is a best-effort restore; a new PTY session will replace the snapshot.
- Snapshot format is a raw memory dump of `TerminalCell` and is not portable
  across different architectures or incompatible arsd versions.
- Validation: `scripts/pure-d/headless_tests.d` covers snapshot save/load round trips.
