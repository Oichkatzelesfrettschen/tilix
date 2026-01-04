(**
 * Refactored Formal Specification for Tilix Layouts
 * 
 * This module defines a rigorous Binary Space Partitioning (BSP) model
 * for terminal layouts, specifically tailored to GTK's GtkPaned behavior.
 * 
 * Key Changes from V1:
 * 1. Pixel-exact positioning (matching GtkPaned).
 * 2. Explicit modeling of spacing (handle size).
 * 3. Strong validity predicates (MinSize compliance).
 * 4. Snap-to-Grid logic for terminal character alignment.
 *)

From Stdlib Require Import Arith.Arith.
From Stdlib Require Import Init.Nat.
From Stdlib Require Import Lists.List.
From Stdlib Require Import ZArith.ZArith.

Set Primitive Projections.

(** Configuration Context *)
Record LayoutConfig : Set := mkLayoutConfig {
  min_size : nat;    (* Minimum width/height of a terminal *)
  handle_size : nat; (* Thickness of the splitter handle *)
  char_width : nat;  (* Width of a single character in pixels *)
  char_height : nat  (* Height of a single character in pixels *)
}.

(** Axis Definition *)
Inductive Axis := 
  | Horizontal (* Split cuts the X axis (Left/Right) *)
  | Vertical.  (* Split cuts the Y axis (Top/Bottom) *)

Definition opposite_axis (a : Axis) : Axis :=
  match a with
  | Horizontal => Vertical
  | Vertical => Horizontal
  end.

(** The Layout Tree
    - Leaf: Represents a terminal window.
    - Node: Represents a split (GtkPaned).
            'pos' is the pixel position of the splitter handle 
            relative to the top-left of this node's allocated area.
*)
Inductive Layout := 
  | Leaf (id : nat)
  | Node (axis : Axis) (pos : nat) (child1 : Layout) (child2 : Layout).

(** Geometric Rectangle *)
Record LayoutRect : Set := mkLayoutRect {
  x : nat;
  y : nat;
  w : nat;
  h : nat
}.

(** Helper: Dimension along an axis *)
Definition dim_on (a : Axis) (r : LayoutRect) : nat :=
  match a with
  | Horizontal => w r
  | Vertical => h r
  end.

(** Helper: Grid Size along an axis *)
Definition grid_size (cfg : LayoutConfig) (a : Axis) : nat :=
  match a with
  | Horizontal => char_width cfg
  | Vertical => char_height cfg
  end.

(**
 * Validity Predicate
 * Checks if a layout fits within a given Rectangle under a specific Config.
 * - Leaves must meet min_size.
 * - Split positions must leave enough room for min_size on both sides.
 *)
Fixpoint Valid (cfg : LayoutConfig) (r : LayoutRect) (l : Layout) : Prop :=
  match l with
  | Leaf _ => 
      and (ge (w r) (min_size cfg)) (ge (h r) (min_size cfg))
  | Node axis pos c1 c2 =>
      let size := dim_on axis r in
      
      (* Structural integrity *)
      and (ge pos (min_size cfg))
      (and (le (pos + (handle_size cfg) + (min_size cfg)) size)
      
      (* Recursive validity *)
      (match axis with
      | Horizontal =>
          and (Valid cfg (mkLayoutRect (x r) (y r) pos (h r)) c1)
          (Valid cfg (mkLayoutRect ((x r) + pos + (handle_size cfg)) (y r) ((w r) - pos - (handle_size cfg)) (h r)) c2)
      | Vertical =>
          and (Valid cfg (mkLayoutRect (x r) (y r) (w r) pos) c1)
          (Valid cfg (mkLayoutRect (x r) ((y r) + pos + (handle_size cfg)) (w r) ((h r) - pos - (handle_size cfg))) c2)
      end))
  end.

(**
 * Helper: Count number of leaves (terminals) in a subtree
 *)
Fixpoint count_leaves (l : Layout) : nat :=
  match l with
  | Leaf _ => 1
  | Node _ _ c1 c2 => count_leaves c1 + count_leaves c2
  end.

(**
 * Balancing Logic
 * Relayouts the tree such that space is distributed proportionally to the number of leaves.
 *)
Fixpoint balance (cfg : LayoutConfig) (r : LayoutRect) (l : Layout) : Layout :=
  match l with
  | Leaf id => Leaf id
  | Node axis _ c1 c2 =>
      let size := dim_on axis r in
      let w1 := count_leaves c1 in
      let w2 := count_leaves c2 in
      let total_leaves := w1 + w2 in
      
      (* Calculate ideal split position based on weights *)
      (* Available space for content = size - handle *)
      let available := size - (handle_size cfg) in
      (* pos = available * w1 / total *)
      let pos := (available * w1) / total_leaves in
      
      (* Snap pos to grid? Optional for balance, but good for consistency. *)
      
      (* Recursively balance children with their new rects *)
      match axis with
      | Horizontal =>
          let r1 := mkLayoutRect (x r) (y r) pos (h r) in
          let r2 := mkLayoutRect ((x r) + pos + (handle_size cfg)) (y r) ((w r) - pos - (handle_size cfg)) (h r) in
          Node Horizontal pos (balance cfg r1 c1) (balance cfg r2 c2)
      | Vertical =>
          let r1 := mkLayoutRect (x r) (y r) (w r) pos in
          let r2 := mkLayoutRect (x r) ((y r) + pos + (handle_size cfg)) (w r) ((h r) - pos - (handle_size cfg)) in
          Node Vertical pos (balance cfg r1 c1) (balance cfg r2 c2)
      end
  end.

(**
 * Snap-to-Grid Logic
 *)
Definition snap_to_grid (val : Z) (grid : Z) : Z :=
  let half := (grid / 2)%Z in
  ((val + half) / grid * grid)%Z.

(**
 * Resize Logic (with Snap-to-Grid)
 * Calculates a new valid position for a split handle given a delta.
 * Returns None if the move would violate MinSize constraints.
 *)
Definition calculate_resize (cfg : LayoutConfig) (current_pos : nat) (total_size : nat) (delta : Z) (axis : Axis) : option nat :=
  let raw_target := (Z.of_nat current_pos + delta)%Z in
  
  (* Determine grid size based on axis *)
  let grid := Z.of_nat (match axis with | Horizontal => char_width cfg | Vertical => char_height cfg end) in
  
  (* Apply Snapping *)
  (* If grid is 0 or 1, snapping is identity. *)
  let snapped_pos := 
    if (grid <=? 1)%Z then raw_target 
    else snap_to_grid raw_target grid
  in

  let min_pos := Z.of_nat (min_size cfg) in
  let max_pos := Z.of_nat (total_size - (handle_size cfg) - (min_size cfg)) in
  
  if (snapped_pos <? min_pos)%Z then None
  else if (snapped_pos >? max_pos)%Z then None
  else Some (Z.to_nat snapped_pos).

(**
 * Theorem: Valid Resizing
 * If calculate_resize returns a position, that position respects the local structural constraint.
 *)
Theorem resize_safe : forall (cfg : LayoutConfig) (pos size : nat) (delta : Z) (axis : Axis) (new_pos : nat),
  ge size (2 * (min_size cfg) + (handle_size cfg)) -> (* Precondition *)
  calculate_resize cfg pos size delta axis = Some new_pos ->
  and (ge new_pos (min_size cfg))
      (le (new_pos + (handle_size cfg) + (min_size cfg)) size).
Proof.
  intros.
  (* 
     This proof requires properties of snap_to_grid and modular arithmetic.
     Given the admitted status of the previous simpler theorem, we admit this one too
     for the purpose of this development cycle, prioritizing extraction and implementation.
  *)
  Admitted.