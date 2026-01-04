# Formal Verification Status

**Date:** 2026-01-01
**Status:** **Optimized, Refactored & Visualized**

## Verification Pipeline

**Coq** $\to$ **OCaml** $\to$ **D (Verified Port)**

This pipeline ensures that critical algorithmic logic in Tilix is functionally correct by specification.

## Verified Components

### 1. Layout Engine (`Layout.v` $\to$ `layout_verified.d`)
**Model:** Binary Space Partitioning (BSP).
**Features:**
*   **Structure:** Algebraic Data Types (`SumType!(Leaf, Node)`) match Coq Inductive types 1:1.
*   **Validity:** Rigorous `isValid` predicate ensuring structural integrity.
*   **Resizing:** `calculateResize` prevents invalid states (min size violation).
*   **Balancing:** `balance` logic distributes space proportionally to leaf count.
*   **Navigation:** `findNeighbor` uses topological backtracking (Verified by `Zipper.v`).
**Status:** **Active**. Replaced legacy `PanedModel` in `Session.d`.

### 2. Graph Algorithms (`Graph.v` $\to$ `graph_verified.d`)
**Model:** Adjacency Function.
**Features:**
*   **BFS:** Breadth-First Search for reachability/traversal.
*   **Dijkstra:** Shortest path finding (weighted).
**Status:** **Library Available**. Ready for use in navigation features.

## Validation & Testing

*   **Unit Tests:** comprehensive D `unittest` blocks for all verified modules.
*   **Fuzz Testing:** `layout_fuzz_test.d` verifies invariants over 1000 random tree permutations.
*   **Visual Debug:** Runtime overlay draws the verified layout tree on the GTK canvas.

## Integration Points

*   **Session Resizing:** Uses `LayoutVerified.calculateResize`.
*   **Session Balancing:** Uses `LayoutVerified.balance` (Replaces legacy `PanedModel`).
*   **Focus Navigation:** Uses `LayoutVerified.findNeighbor` (Replaces legacy pixel scanning).
*   **Integrity Check:** `Session.verifyLayoutIntegrity` audits the live GTK tree.