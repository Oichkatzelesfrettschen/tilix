# Terminal.d VTE Usage Audit (2026-01-05)

**Purpose**: Document all direct VTE dependencies in Terminal.d for migration to IRenderingContainer abstraction.

## Summary Statistics

- **Total VTE method calls**: 125
- **VTE imports**: 6 (vte.Pty, vte.Regex, vte.Terminal, vtec.vtetypes, gx.gtk.vte, exvte)
- **Main VTE field**: `ExtendedVTE vte` (line 214)
- **Signal handler tracking**: `gulong[] vteHandlers` (line 215)
- **File size**: 4,677 lines

## VTE Usage Categories

### 1. Initialization (createUI)
**Location**: Line 897
```d
vte = new ExtendedVTE();
vte.setHexpand(true);
vte.setVexpand(true);
vte.setAllowHyperlink(true);
```
**Migration**: Replace with `IRenderingContainer container = new VTE3Container();`

### 2. Signal Handlers (15+ signals)
**Locations**: Lines 907-1012
- `addOnChildExited` → `container.addOnChildExited`
- `addOnBell` → `container.addOnBell`
- `addOnWindowTitleChanged` → `container.addOnWindowTitleChanged`
- `addOnIconTitleChanged` → N/A (not in IRenderingContainer)
- `addOnCurrentDirectoryUriChanged` → `container.addOnCurrentDirectoryUriChanged`
- `addOnCurrentFileUriChanged` → N/A (VTE-specific)
- `addOnFocusIn/Out` → Widget-level (via `container.widget`)
- `addOnNotificationReceived` → ExtendedVTE-specific
- `addOnContentsChanged` → `container.addOnContentsChanged`
- `addOnTerminalScreenChanged` → ExtendedVTE-specific
- `addOnSizeAllocate` → Widget-level
- `addOnCommit` → `container.addOnCommit`

**Migration Strategy**:
- Core signals: Use IRenderingContainer methods
- VTE-specific signals: Keep via `(VTE3Container)container._vte`
- Widget signals: Use `container.widget.addOn*`

### 3. State Queries
**Pattern**: `vte.get*()`
```d
vte.getEncoding()          → container.encoding
vte.getHasSelection()      → container.hasSelection
vte.getCursorPosition()    → container.getCursorPosition()
vte.getTextRange()         → container.getText()
vte.getColumnCount()       → container.columnCount
vte.getRowCount()          → container.rowCount
vte.getChildPid()          → container.getChildPid()
vte.getCharWidth()         → container.charWidth
vte.getCharHeight()        → container.charHeight
vte.getFontScale()         → container.fontScale
vte.getWindowTitle()       → container.windowTitle
vte.getCurrentDirectoryUri() → container.currentDirectoryUri
```

### 4. State Setters
**Pattern**: `vte.set*()`
```d
vte.setInputEnabled()      → container.inputEnabled = bool
vte.setEncoding()          → container.setEncoding()
vte.setAllowHyperlink()    → VTE-specific (requires cast)
vte.setFont()              → container.setFont()
vte.setFontScale()         → container.fontScale = double
vte.setColors()            → container.setColors()
vte.setColorCursor()       → container.setColorCursor()
vte.setColorHighlight()    → container.setColorHighlight()
vte.setCursorShape()       → container.setCursorShape()
vte.setCursorBlinkMode()   → container.setCursorBlinkMode()
vte.setAudibleBell()       → container.setAudibleBell()
vte.setAllowBold()         → container.setAllowBold()
vte.setRewrapOnResize()    → container.setRewrapOnResize()
```

### 5. Scrolling Operations
**Pattern**: `vte.getVadjustment().setValue()`
```d
vte.getVadjustment()                   → container.getAdjustment()
vte.getVadjustment().getValue() - 1    → container.scrollLines(-1)
vte.getVadjustment().getValue() + 1    → container.scrollLines(1)
vte.getVadjustment().getValue() - page → container.scrollPages(-1)
vte.getVadjustment().getValue() + page → container.scrollPages(1)
```

### 6. Clipboard Operations
```d
vte.copyClipboard()   → container.copyClipboard()
vte.copyPrimary()     → container.copyPrimary()
vte.pasteClipboard()  → container.pasteClipboard()
vte.pastePrimary()    → container.pastePrimary()
```

### 7. PTY and Process Management
```d
vte.spawnSync()       → container.spawnSync()
vte.getPty()          → container.getPty()
vte.feedChild()       → container.feedChild()
vte.getChildPid()     → container.getChildPid()
```

### 8. Search Operations
```d
vte.searchSetWrapAround() → container.searchSetWrapAround()
vte.searchFindNext()      → container.searchFindNext()
vte.searchFindPrevious()  → container.searchFindPrevious()
```

### 9. Widget Hierarchy
```d
vte (as Widget)       → container.widget
sw.add(vte)           → sw.add(container.widget)
terminalOverlay.addOverlay(vte) → terminalOverlay.addOverlay(container.widget)
```

### 10. VTE-Specific Operations (Require Cast)
**These are NOT in IRenderingContainer and require casting to VTE3Container**:
```d
vte.setAllowHyperlink()          // VTE-specific feature
vte.addOnIconTitleChanged()      // VTE-specific signal
vte.addOnCurrentFileUriChanged() // VTE-specific signal
vte.addOnNotificationReceived()  // ExtendedVTE-specific
vte.addOnTerminalScreenChanged() // ExtendedVTE-specific
vte.getCurrentFileUri            // VTE-specific property
vte.matchAddGregex()             // Regex matching (needs redesign)
vte.matchRemove()                // Regex matching
vte.matchCheck()                 // Regex matching
vte.setDisableBGDraw()           // ExtendedVTE-specific patch
```

## Migration Plan

### Phase 1: Add Container Field (Non-Breaking)
1. Add `IRenderingContainer _container;` field
2. Keep `ExtendedVTE vte;` field temporarily
3. Initialize both in createUI:
   ```d
   _container = new VTE3Container();
   vte = (cast(VTE3Container)_container)._vte;  // Temporary bridge
   ```

### Phase 2: Migrate Methods Incrementally
1. **Start with getters**: Replace `vte.getX()` with `_container.X`
2. **Then setters**: Replace `vte.setX()` with `_container.setX()`
3. **Then signals**: Replace signal handlers one category at a time
4. **Finally PTY/spawn**: Critical path - test thoroughly

### Phase 3: Remove VTE Field
1. Replace all `vte.` calls with `_container.`
2. For VTE-specific operations, cast: `auto vte3 = cast(VTE3Container)_container;`
3. Remove `ExtendedVTE vte;` field
4. Remove VTE imports

### Phase 4: Abstract Widget References
1. Replace `vte` widget references with `_container.widget`
2. Update sw.add(), overlay operations

## Risk Areas

1. **Regex matching**: Complex VTE-specific API, needs abstraction design
2. **Signal handler lifetimes**: Ensure handlers disconnect properly
3. **Widget hierarchy**: Terminal assumes vte IS-A Widget
4. **VTE-specific features**: Hyperlinks, notifications, screen changes
5. **Performance**: Ensure no degradation from indirection

## Testing Strategy

1. Build with warnings-as-errors at each phase
2. Manual testing: spawn process, type text, scroll, copy/paste
3. Test all Terminal actions (maximize, find, profile switch)
4. Verify signal handlers fire correctly
5. Check memory leaks (vteHandlers cleanup)

## Files to Update

- `source/gx/tilix/terminal/terminal.d` (primary)
- `source/gx/tilix/terminal/search.d` (uses VTE for regex)
- `source/gx/tilix/terminal/regex.d` (VTE regex wrapper)
- `source/gx/tilix/terminal/layout.d` (VTE layout utilities)

## Estimated Effort

- Phase 1 (Add container): 30 minutes
- Phase 2 (Migrate methods): 3-4 hours (125 call sites)
- Phase 3 (Remove VTE field): 1 hour
- Phase 4 (Widget abstraction): 1 hour
- Testing: 2 hours

**Total**: ~8 hours for complete migration
