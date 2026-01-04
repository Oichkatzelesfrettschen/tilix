(**
 * Zipper Data Structure for Layout Navigation
 * 
 * Provides a formal model for traversing the Layout tree up/down/sideways.
 * Used to verify 'findNeighbor' logic.
 *)

Require Import Layout.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
Import ListNotations.

(** Context Node: Describes the parent of the current focus *)
Inductive ContextNode :=
  | CNode (axis : Axis) (pos : nat) (is_left : bool) (other : Layout).
  (* is_left = true means focus is child1, other is child2 *)

Definition Context := list ContextNode.
Definition Location := (Layout * Context)%type.

(** Navigation Primitives *)

Definition up (loc : Location) : option Location :=
  match loc with
  | (_, nil) => None (* Already at root *)
  | (focus, (CNode ax p is_left other) :: ctx) =>
      let new_focus := 
        if is_left 
        then Node ax p focus other
        else Node ax p other focus
      in Some (new_focus, ctx)
  end.

Definition down_left (loc : Location) : option Location :=
  match loc with
  | (Leaf _, _) => None
  | (Node ax p c1 c2, ctx) =>
      Some (c1, CNode ax p true c2 :: ctx)
  end.

Definition down_right (loc : Location) : option Location :=
  match loc with
  | (Leaf _, _) => None
  | (Node ax p c1 c2, ctx) =>
      Some (c2, CNode ax p false c1 :: ctx)
  end.

(** Find a specific Leaf ID (DFS) *)
Fixpoint find_leaf (l : Layout) (target : nat) : option Location :=
  match l with
  | Leaf id => 
      if Nat.eqb id target then Some (l, []) else None
  | Node ax p c1 c2 =>
      match find_leaf c1 target with
      | Some (f, ctx) => Some (f, CNode ax p true c2 :: ctx)
      | None => 
          match find_leaf c2 target with
          | Some (f, ctx) => Some (f, CNode ax p false c1 :: ctx)
          | None => None
          end
      end
  end.

(** Closest Leaf Helper (Minimize/Maximize) *)
Fixpoint find_closest (l : Layout) (relevant_axis : Axis) (minimize : bool) : nat :=
  match l with
  | Leaf id => id
  | Node ax _ c1 c2 =>
      if match ax, relevant_axis with
         | Horizontal, Horizontal => true
         | Vertical, Vertical => true
         | _, _ => false (* Orthogonal *)
         end
      then
        (* Matching Axis *)
        if minimize then find_closest c1 relevant_axis minimize
        else find_closest c2 relevant_axis minimize
      else
        (* Orthogonal: Default to 'minimize' (Top/Left) *)
        find_closest c1 relevant_axis minimize
  end.

(** Neighbor Finder Logic *)
Fixpoint find_neighbor_aux (ctx : Context) (dir_axis : Axis) (forward : bool) : option nat :=
  match ctx with
  | [] => None (* Reached root without finding split *)
  | CNode ax p is_left other :: rest =>
      (* Check if this node splits in the direction we want *)
      let axis_match := 
        match ax, dir_axis with
        | Horizontal, Horizontal => true
        | Vertical, Vertical => true
        | _, _ => false
        end
      in
      
      if axis_match then
        if andb forward is_left then
          (* Moving Forward (Right/Down) and we are Left Child.
             So we move to Right Child (other) and find closest (minimize). *)
          Some (find_closest other dir_axis true)
        else if andb (negb forward) (negb is_left) then
          (* Moving Backward (Left/Up) and we are Right Child.
             So we move to Left Child (other) and find closest (maximize). *)
          Some (find_closest other dir_axis false)
        else
          (* Continue up *)
          find_neighbor_aux rest dir_axis forward
      else
        (* Continue up *)
        find_neighbor_aux rest dir_axis forward
  end.

Definition find_neighbor (root : Layout) (id : nat) (dir_axis : Axis) (forward : bool) : option nat :=
  match find_leaf root id with
  | None => None
  | Some (_, ctx) => find_neighbor_aux ctx dir_axis forward
  end.
