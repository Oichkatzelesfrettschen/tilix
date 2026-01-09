# Length Subtraction Audit
**Date:** 2026-01-01
**Issue:** dscanner.suspicious.length_subtraction
**Severity:** HIGH - Potential underflow if length is 0 (size_t is unsigned)
**Status:** PARTIALLY FIXED (Verified active issues fixed, others unreproducible)

## Issue Summary
Subtracting from `.length` on an array is dangerous because `.length` returns a `size_t` (unsigned). If the array is empty or the subtraction result would be negative, it wraps around to a huge number (underflow), leading to `RangeError` or memory corruption.

## Identified Instances & Resolution

### source/gx/tilix/sidebar.d (Verified & Fixed)
- **Location:** Line 248 (Logic: `rows[rows.length - 1]`)
- **Issue:** Accessing `rows.length - 1` without ensuring `rows.length > 0`. If `rows` is empty, `0-1` underflows to `size_t.max`, causing a crash.
- **Resolution:** Added `rows.length > 0` check.
- **Status:** **FIXED**

### source/gx/tilix/terminal/exvte.d (Unreproducible)
- **Reported:** Lines 92, 96, 99, 147, 151, 154
- **Analysis:** Code inspection shows `~=` (append) and `std.algorithm.remove`. No explicit subtraction from `.length` found. Re-running `dscanner` individually on this file yielded **0 warnings**.
- **Status:** **FALSE POSITIVE / UNREPRODUCIBLE**

### source/gx/tilix/terminal/terminal.d (Unreproducible)
- **Reported:** Line 608
- **Analysis:** Logic was `if (index >= length) index = 0;`. No subtraction. Re-running `dscanner` individually yielded **0 warnings**.
- **Status:** **FALSE POSITIVE / UNREPRODUCIBLE**

### source/gx/tilix/bookmark/manager.d (Unreproducible)
- **Reported:** Line 175
- **Analysis:** Logic was `if (list.length > 0 && index + 1 < list.length)`. No subtraction. Re-running `dscanner` individually yielded **0 warnings**.
- **Status:** **FALSE POSITIVE / UNREPRODUCIBLE**

## Verification
- `dscanner` confirms no "suspicious length subtraction" warnings in `sidebar.d` after fix.
- Manual inspection confirms logic safety in `sidebar.d`.