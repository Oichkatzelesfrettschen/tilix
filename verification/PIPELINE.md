# Formal Verification Pipeline & Roadmap

**Date:** 2026-01-01
**Status:** Active Integration

## The Pipeline: Coq $\to$ OCaml $\to$ D

We utilize a **Verified Port** strategy to integrate formal methods without imposing a heavy runtime dependency on OCaml or Coq.

1.  **Specify (Coq):** Define algorithms and data structures in `.v` files. Prove correctness theorems.
2.  **Extract (OCaml):** Use `Extraction` to generate functional `.ml` code. This serves as the "Ground Truth" reference.
3.  **Port (D):** Manually translate the OCaml code to idiomatic D (`_verified.d` modules).
4.  **Verify (D):** Use `unittest` blocks in D to test against the formal invariants.

## Verified Components

| Component | Coq Spec | D Implementation | Description |
|-----------|----------|------------------|-------------|
| **Layout** | `Layout.v` | `layout_verified.d` | BSP Tree, Validity Predicates, Resizing logic. |
| **Graph** | `Graph.v` | `graph_verified.d` | BFS, Dijkstra. |
| **Balancing**| `Layout.v`* | `layout_verified.d` | *In Progress:* Tree balancing for even terminal sizing. |

## Refactoring Roadmap

### 1. Replace `PanedModel` (Legacy)
**Target:** `source/gx/tilix/session.d`
**Goal:** The `PanedModel` class manually traverses the widget tree to calculate even splitter positions.
**Action:**
*   Extend `Layout.v` with a `balance` function that calculates split positions based on leaf weights.
*   Verify that `balance` produces Valid layouts.
*   Replace `PanedModel` usage in `Session.redistributePanes` with `Layout.balance`.

### 2. Graph-Based Navigation
**Target:** `Session.focusDirection`
**Goal:** Replace geometric pixel-scanning with graph traversal.
**Action:**
*   Build an adjacency graph from the `Layout` tree.
*   Use `Graph.bfs` to find the nearest neighbor in the directional subgraph.

---
*Generated for Tilix Development*
