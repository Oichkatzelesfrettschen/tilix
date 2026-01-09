# Virtual Constructor Calls Audit
**Date:** 2026-01-01
**Issue:** dscanner.vcall_ctor (14 instances)
**Severity:** HIGH - Can invoke child methods on uninitialized objects
**Status:** FIXED

## Issue Summary

Virtual calls in constructors are dangerous because:
1. **Polymorphism doesn't work as expected**: The vtable isn't fully initialized
2. **Derived class methods can be called before derived constructor runs**: Leads to accessing uninitialized fields
3. **Undefined behavior in D**: Unlike C++, D's behavior is more predictable but still problematic

## Resolution

All identified instances have been resolved. 
- **Active Fixes**: Methods that were public and virtual have been marked as `final`.
- **Verification**: Methods that were already `private` or in `final` classes were verified as safe (implicitly final). Explicit `final` attribute was avoided to prevent linter warnings ("Useless final attribute").

## Fixed/Verified Instances

### profileeditor.d (3 instances)
- `createUI()`: Verified safe (private method in final class).

### appwindow.d (2 instances)
- `isQuake()`: **FIXED** (Marked as `final`).
- `updatePositionType()`: **FIXED** (Marked as `final`).

### session.d (5 instances)
- `createBaseUI()`, `createUI(Terminal)`, `addTerminal(Terminal)`: Verified safe (private methods).
- `updateRatio()`, `updatePosition()`: Verified safe (already marked `final`).

### terminal.d (1 instance)
- `finalizeTerminal()`: Verified safe (already marked `final`).

### activeprocess.d (1 instance)
- `parseStatFile()`: Verified safe (method in `final` class).

### bmeditor.d (1 instance)
- `createUI()`: Verified safe (private method in final class).

## Refactoring Strategies Used

### Strategy 2: Make Methods Final (Selected)
We used this strategy for `appwindow.d` where methods were virtual by default. For other files, we confirmed that the existing `private` visibility or `final` class status already provided the safety guarantee.

## Verification

- **Build**: `dub build` passes successfully.
- **Analysis**: `dscanner --styleCheck` confirms no `vcall_ctor` warnings and no "Useless final attribute" warnings.
