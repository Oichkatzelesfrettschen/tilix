# Tilix Technical Debt Audit (2026-01-05)

This comprehensive audit identifies 22 technical debt items across the Tilix codebase, categorized by severity and prioritized for remediation.

## Executive Summary

- **Total Issues**: 22
- **Critical**: 4 (Regex caching, File size, TODO debt, Hardcoded metrics)
- **High**: 4 (Error handling, Massive methods, Resource leaks, GC pressure)
- **Medium**: 7 (Queue overflow, Singletons, Concatenations, Missing tests)
- **Low**: 5 (Code smell, Typos, Magic numbers)
- **Architectural**: 2 (VTE abstraction, Global state)

## CRITICAL ISSUES

### 1. Regex Compilation in Hot Path
**File**: `source/gx/tilix/terminal/terminal.d:2032-2065`
**Impact**: Performance degradation on repeated link clicks
**Root Cause**: No regex compilation caching mechanism for custom URL patterns
**Fix**: Implement a compiled regex cache keyed by pattern string
**Effort**: Medium (2-3 hours)

```d
// Current (line 2044):
GRegex regex = compileGRegex(tr);  // Compiled on every access

// Recommended:
private GRegex[string] _regexCache;
GRegex getCompiledRegex(string pattern) {
    if (pattern !in _regexCache) {
        _regexCache[pattern] = compileGRegex(pattern);
    }
    return _regexCache[pattern];
}
```

---

### 2. Massive terminal.d File (4,677 lines)
**File**: `source/gx/tilix/terminal/terminal.d`
**Impact**: Extremely difficult to understand, test, and maintain
**Root Cause**: Lack of architectural decomposition
**Fix**: Decompose into specialized modules
**Effort**: High (4-6 days)

**Recommended Decomposition**:
- `terminal/ui.d` - UI creation (createUI, createTitlePane)
- `terminal/events.d` - Event handling (on* methods)
- `terminal/renderer.d` - Rendering logic
- `terminal/config.d` - Configuration management
- `terminal/triggers.d` - Process/trigger handling

---

### 3. Unresolved TODO in iothread.d
**File**: `source/gx/tilix/terminal/iothread.d:389`
**Impact**: Blocking reads could freeze entire I/O thread
**Root Cause**: Incomplete async I/O implementation
**Fix**: Implement select/poll with non-blocking reads
**Effort**: High (5-8 hours)

```d
// Current:
// TODO: Use select/poll for non-blocking read

// Recommended:
import core.sys.posix.sys.select;
fd_set readfds;
FD_ZERO(&readfds);
FD_SET(pty_fd, &readfds);
if (select(pty_fd + 1, &readfds, null, null, &timeout) > 0) {
    // Non-blocking read
}
```

---

### 4. Hardcoded Metrics in session.d
**File**: `source/gx/tilix/session.d:1465-1466`
**Impact**: Layout calculations inaccurate for non-default fonts
**Root Cause**: Metrics not queried from VTE widget
**Fix**: Fetch actual char dimensions from VTE
**Effort**: Medium (2-3 hours)

```d
// Current:
// TODO: Fetch real char metrics from terminal
LayoutConfig cfg = LayoutConfig(50, 1, 8, 16);  // Hardcoded

// Recommended:
LayoutConfig cfg = LayoutConfig(
    currentTerminal.getColumnCount(),
    1,
    currentTerminal.getCharWidth(),
    currentTerminal.getCharHeight()
);
```

---

## HIGH SEVERITY ISSUES

### 5. Missing Error Handling in Color Parsing
**File**: `source/gx/tilix/terminal/terminal.d:2256-2265`
**Impact**: Invalid color settings silently fail
**Fix**: Validate colors, fall back to defaults
**Effort**: Medium (3 hours)

### 6. applyPreference() Massive Switch
**File**: `source/gx/tilix/terminal/terminal.d:2233-2400+`
**Impact**: ~150 line method, hard to test
**Fix**: Use strategy pattern with handler map
**Effort**: Medium (4-5 hours)

### 7. Destruction Resource Leaks
**Files**: 15 files across codebase
**Impact**: Potential memory leaks
**Fix**: Create RAII wrappers for GTK widgets
**Effort**: High (1 day)

### 8. String Allocation in Hot Loop
**File**: `source/gx/tilix/terminal/terminal.d:1647-1662`
**Impact**: Excessive GC pressure
**Fix**: Pre-allocate arrays, use object pooling
**Effort**: Low (1-2 hours)

---

## MEDIUM SEVERITY ISSUES

### 9. Lock-Free Queue Capacity Hard-Coded
**File**: `source/gx/tilix/terminal/iothread.d:92`
**Impact**: Frames silently dropped if output > 4KB
**Fix**: Add overflow detection or configurable capacity
**Effort**: Medium (3-4 hours)

### 10. Global Singleton ProcessMonitor
**File**: `source/gx/tilix/terminal/monitor.d:55-117`
**Impact**: Testing difficult, hidden dependencies
**Fix**: Explicit initialization, dependency injection
**Effort**: Medium (3-4 hours)

### 11. Cascading String Concatenations
**File**: `source/gx/tilix/terminal/terminal.d` (multiple locations)
**Impact**: Multiple allocations
**Fix**: Use appender or format()
**Effort**: Low (1 hour)

### 12. No Unit Tests for Terminal Core
**Files**: terminal.d (4,677 lines), session.d (1,927 lines), appwindow.d (2,281 lines)
**Impact**: Risky changes, no regression detection
**Fix**: Add unit tests for core logic
**Effort**: High (2-3 days)

### 13-15. Additional Medium Issues
- Regex pattern caching unclear (terminal.d:2612)
- Inconsistent null checks (session.d)
- Commented debug code (terminal.d:2213)

---

## LOW SEVERITY ISSUES

### 16-20. Code Smell Items
- Inconsistent variable naming
- Magic numbers (font size, frame time)
- Incomplete error messages
- Untested backend rendering
- Typo: "Ouput" vs "Output" (terminal.d:228)

---

## ARCHITECTURAL GAPS

### 21. No Clear Abstraction for VTE Operations
**Impact**: 100+ direct VTE calls, hard to mock
**Fix**: Create VTEAdapter facade layer
**Effort**: High (1 day)

### 22. Global State Permeates Application
**Instances**: gsSettings, gsProfile, ProcessMonitor.instance
**Impact**: Hard to test, hidden dependencies
**Fix**: Dependency injection for preferences
**Effort**: High (2-3 days)

---

## PRIORITIZATION ROADMAP

### Immediate (Next Sprint)
1. Fix hardcoded layout metrics (session.d:1465) - **blocks layout accuracy**
2. Add regex compilation cache (terminal.d:2032) - **impacts UX**
3. Complete TODO in iothread.d:389 - **blocks I/O reliability**
4. Fix color parsing error handling (terminal.d:2256)

### Short Term (Next 2 Sprints)
5. Decompose Terminal class from 4,677 to <1,000 lines
6. Add unit tests for core logic (triggers, color parsing, URL handling)
7. Implement resource cleanup RAII pattern
8. Optimize GC pressure in hot loops

### Medium Term (Next Quarter)
9. Create VTE adapter layer
10. Replace global state with dependency injection
11. Add formal verification tests to core modules
12. Set up CI enforcement of warnings-as-errors

### Ongoing
- Code review focus on error handling gaps
- Regular technical debt cleanup sprints
- Performance profiling and optimization

---

## TESTING GAPS

**Files without unit tests**:
- `terminal.d` (4,677 lines) - **0 tests**
- `session.d` (1,927 lines) - **0 tests**
- `appwindow.d` (2,281 lines) - **0 tests**
- `backend/opengl.d` - **0 tests**

**Files WITH tests**:
- `layout_verified.d` (formal methods)
- `layout_verified_test.d`
- `session_verified.d` (formal methods)
- `graph_verified.d` (formal methods)
- `solver.d` (unittest blocks)

**Recommendation**: Aim for 70% coverage of core logic paths within 2 quarters.

---

## METRICS

| Metric | Value |
|--------|-------|
| Largest file | terminal.d (4,677 lines) |
| Files >1000 lines | 3 (terminal, session, appwindow) |
| TODO/FIXME items | 2 (both critical) |
| Global singletons | 3 (ProcessMonitor, settings objects) |
| Untested modules | 15+ |
| Regex compilations/click | O(n) patterns |

---

## REFERENCES

- Architecture doc: `docs/architecture/backend-interface-map.md`
- TODO list: `docs/TODO.md`
- Build guide: `docs/BUILD_DUB.md`
- Contributing: `CONTRIBUTING.md`
