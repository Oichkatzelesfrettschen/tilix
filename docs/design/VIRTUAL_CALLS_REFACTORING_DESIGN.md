# Virtual Constructor Calls - Refactoring Design
**Date:** 2026-01-01
**Objective:** Eliminate all 14 virtual constructor call warnings from dscanner

---

## Problem Classification

Based on code analysis, all 14 instances fall into two patterns:

### Pattern A: Virtual Methods in Delegate Callbacks (11 instances)
Methods called through delegates registered during construction:
- **terminal.d:3755** - `finalizeTerminal()` in destroy callback
- **appwindow.d:1801, 2145** - `isQuake()` and others in window callbacks
- **session.d:1642, 1646, 1651** - `updatePosition()`, `updateRatio()` in paned callbacks

**Risk:** Medium - callbacks could fire before full construction completes
**Fix Strategy:** Mark methods `final` if not overridden, or cache state

### Pattern B: Direct Virtual Calls in Constructor Body (3+ instances)
Methods called directly during construction:
- **session.d:986, 990, 1062** - `createBaseUI()`, `createUI()`, `addTerminal()`
- **profileeditor.d:125, 460, 1225** - TBD (need to check)
- **activeprocess.d:28** - TBD
- **bmeditor.d:231** - TBD

**Risk:** HIGH - derived class methods invoked on partially constructed object
**Fix Strategy:** Two-stage initialization or make methods `final`

---

## Refactoring Strategies

### Strategy 1: Mark Method `final` (Safest, Preferred)

**When to use:**
- Method is not overridden by any derived class
- Method doesn't need to be overridable

**Example:**
```d
// BEFORE
void finalizeTerminal() {
    // cleanup code
}

// AFTER
final void finalizeTerminal() {  // Cannot be overridden
    // cleanup code
}
```

**Verification:**
```bash
# Check if method is overridden
grep -r "override.*methodName" source/
```

### Strategy 2: Two-Stage Initialization

**When to use:**
- Method MUST remain virtual (has overrides)
- Constructor calls virtual methods directly (Pattern B)

**Example:**
```d
// BEFORE (dangerous)
this(string name) {
    super();
    createBaseUI();  // Virtual call in constructor!
    addTerminal(terminal);  // Virtual call!
}

// AFTER (safe)
this(string name) {
    super();
    // No virtual calls in constructor
}

// Call this after construction
final void initialize(Terminal terminal) {
    createBaseUI();  // Safe - object fully constructed
    addTerminal(terminal);  // Safe
}

// Usage site changes from:
auto session = new Session("name", terminal);

// To:
auto session = new Session("name");
session.initialize(terminal);
```

### Strategy 3: Cache State Before Callback

**When to use:**
- Callback-based virtual calls (Pattern A)
- Method cannot be made final
- State is simple enough to cache

**Example:**
```d
// BEFORE
this() {
    addOnWindowState(delegate(...) {
        if (!isQuake()) {  // Virtual call
            // ...
        }
    });
}

// AFTER
this() {
    immutable bool quakeMode = isQuake();  // Cache once
    addOnWindowState(delegate(...) {
        if (!quakeMode) {  // Use cached value
            // ...
        }
    });
}
```

---

## Implementation Plan by File

### terminal.d (1 instance)

**Line 3755: `finalizeTerminal()` in destroy callback**

```d
final void finalizeTerminal() {  // Add 'final' keyword
    // ... existing cleanup code
}
```

**Verification:**
1. Check ExtendedVTE doesn't override: ✓ Already verified
2. Build and run tests
3. Verify dscanner warning disappears

---

### appwindow.d (2 instances)

**Line 1801: `isQuake()` in window state callback**

**Strategy:** Mark final if not overridden, else cache

```bash
# Check for overrides
grep -r "override.*isQuake" source/
```

If no overrides:
```d
final bool isQuake() {  // Add 'final'
    return _qpid.length > 0;
}
```

If has overrides:
```d
this(...) {
    immutable bool quakeMode = isQuake();
    addOnWindowState(delegate(...) {
        if (getWindow() !is null && !quakeMode && ...) {
            // ...
        }
    });
}
```

**Line 2145:** TBD after reading context

---

### session.d (6 instances)

**Lines 986, 990, 1062: Direct virtual calls in constructor**

**High Priority - Two-stage initialization required**

Current pattern:
```d
this(string sessionName, Terminal terminal) {
    super();
    initSession();
    createBaseUI();  // Virtual!
    addTerminal(terminal);  // Virtual!
    createUI(terminal);  // Virtual!
}
```

Refactored:
```d
this(string sessionName) {
    super();
    initSession();
    // No virtual calls
}

final void initialize(Terminal terminal) {
    createBaseUI();  // Now safe
    addTerminal(terminal);
    createUI(terminal);
}

// Or make methods final if not overridden:
final void createBaseUI() { ... }
final void addTerminal(Terminal terminal) { ... }
final void createUI(Terminal terminal) { ... }
```

**Decision point:** Check if Session has derived classes that override these methods

**Lines 1642, 1646, 1651: Callback-based virtual calls**

```d
// Paned constructor with callbacks to updatePosition/updateRatio
final void updateRatio() { ... }  // Make final if not overridden
final void updatePosition(bool force = false) { ... }
```

---

### profileeditor.d (3 instances)
**Status:** Need to read context (lines 125, 460, 1225)

---

### activeprocess.d (1 instance)
**Status:** Need to read context (line 28)

---

### bmeditor.d (1 instance)
**Status:** Need to read context (line 231)

---

## Implementation Order

1. **Phase 1: Low-hanging fruit (Callbacks with no overrides)**
   - terminal.d:3755 - Mark `finalizeTerminal()` final
   - session.d:1642,1646,1651 - Mark `updateRatio/updatePosition()` final
   - Estimated time: 15 minutes

2. **Phase 2: Check remaining files**
   - Read profileeditor.d, activeprocess.d, bmeditor.d contexts
   - Apply Strategy 1 or 3 where applicable
   - Estimated time: 20 minutes

3. **Phase 3: High-priority refactoring (Direct virtual calls)**
   - session.d:986,990,1062 - Two-stage init or make methods final
   - appwindow.d:1801,2145 - Apply appropriate strategy
   - Estimated time: 30 minutes

4. **Phase 4: Testing**
   - Build after each phase
   - Run unit tests
   - Verify dscanner shows 0 vcall_ctor warnings
   - Estimated time: 15 minutes

**Total estimated time:** 80 minutes (1 hour 20 minutes)

---

## Verification Checklist

For each fix:
- [ ] Check if method has overrides: `grep -r "override.*methodName" source/`
- [ ] Apply appropriate strategy
- [ ] Build successfully: `meson compile -C build`
- [ ] Run tests: `meson test -C build`
- [ ] Re-run dscanner: `dscanner --styleCheck source/ > /tmp/dscanner-after.json`
- [ ] Verify warning count decreased

Final verification:
```bash
# Count remaining vcall_ctor warnings
jq '[.issues[] | select(.key == "dscanner.vcall_ctor")] | length' /tmp/dscanner-after.json
# Expected: 0
```

---

## Rollback Plan

If any fix breaks functionality:
1. Git stash changes: `git stash`
2. Verify tests pass on original code
3. Review the specific fix
4. Consider alternative strategy
5. Reapply with modifications

---

## Success Criteria

1. **Zero vcall_ctor warnings** from dscanner
2. **All unit tests passing** (3/3 as baseline)
3. **No behavioral changes** - Tilix functions identically
4. **Code is cleaner** - Explicit about which methods can be overridden

---

## Next Steps

1. Complete reading remaining 3 files (profileeditor.d, activeprocess.d, bmeditor.d)
2. Create git branch: `git checkout -b fix/virtual-constructor-calls`
3. Execute Phase 1 fixes
4. Test and verify
5. Continue through phases 2-4
6. Final verification with dscanner
