# Formal Methods Expansion Design: TLA+ & Z3

**Date:** 2026-01-01
**Status:** Draft
**Target:** Tilix Core

## 1. Executive Summary
This document outlines the architecture for integrating TLA+ and Z3 into the Tilix development workflow. While Coq (Phase 1) handles static structural invariants, TLA+ will address dynamic concurrency risks, and Z3 will be employed for constraint validation in the layout engine.

## 2. Architecture Overview

| Tool | Domain | Target Component | Integration Mode |
|------|--------|------------------|------------------|
| **Coq** | Static Data Structures | `Layout` (Trees, Rects) | Verified Port (Manual D impl) |
| **TLA+** | Concurrency & Time | `Session` / `Terminal` Lifecycle | Offline Specification & Model Checking |
| **Z3** | Constraint Satisfaction | Layout Resizing & Edge Cases | Offline Validation / Test Generation |

## 3. Component Design

### 3.1. TLA+ : Session Lifecycle & Concurrency
**Problem:** The `Session` class manages child processes (VTE), tabs, and splits. Race conditions occur between:
1.  User closing a split.
2.  Child process exiting (signal).
3.  Layout re-balancing.

**Specification (`verification/Session.tla`):**
*   **Variables:** `running_processes`, `layout_tree`, `focus_state`.
*   **Actions:** `SpawnProcess`, `KillProcess`, `CloseSplit`, `FocusNext`.
*   **Invariants:**
    *   `NoOrphanedProcesses`: Every running process has a corresponding window in the layout.
    *   `FocusAlwaysValid`: Focus is never on a non-existent window (unless empty).
    *   `LayoutConsistency`: The number of leaves in the layout tree equals `Len(running_processes)`.

**Integration:**
The D implementation of `Session` will be refactored to explicitly mirror the State Machine defined in TLA+. Comments in D will reference TLA+ actions.

### 3.2. Z3 : Layout Constraint Solver
**Problem:** When resizing a complex tiling layout (e.g., 3 columns, 2 rows nested), maintaining "minimum terminal size" (e.g., 80x24 chars) is a constraint satisfaction problem.

**Specification (`verification/layout_constraints.py`):**
*   **Inputs:** Current Tree, Resize Delta, Min Dimensions.
*   **Solver:** Z3 Optimizer.
*   **Goal:** Find new dimensions $(w_1', h_1', ...)$ such that:
    *   $\sum w_i = W_{total}$
    *   $\forall i, w_i \ge w_{min}$
    *   Minimize $\sum |w_i - w_i^{target}|$ (Least disturbance).

**Integration:**
We will implement a lightweight heuristic solver in D (`source/gx/tilix/terminal/solver.d`) that approximates the Z3 model. The Z3 script serves as an "Oracle" for generating property-based test cases to fuzz the D implementation.

## 4. Implementation Roadmap
1.  **Specify:** Write `Session.tla` and `layout_constraints.py`.
2.  **Verify:** Model check `Session.tla` (simulated success) and run Z3 scripts.
3.  **Implement:**
    *   `session_verified.d`: A State-Machine-based session controller.
    *   `solver.d`: A constraint-aware resizing logic.
4.  **Document:** Update guidelines on how to modify these specs when features change.
