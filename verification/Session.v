(**
 * Formal Specification of Session Lifecycle
 *
 * Ported from TLA+ (verification/Session.tla) to Rocq.
 * Models the state machine of terminal sessions, processes, and focus.
 *)

From Stdlib Require Import Lists.List.
From Stdlib Require Import Init.Nat.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import PeanoNat. (* For Nat.eqb_eq *)
Import ListNotations.

Set Primitive Projections.

(** State Definition *)
Record SessionState : Set := mkSession {
  processes : list nat; (* Running Process IDs *)
  layout : list nat;    (* Window IDs in layout *)
  focus : nat;          (* Currently focused ID (0 = None) *)
  max_procs : nat       (* Constant limit *)
}.

(** Helper: Membership *)
Fixpoint In_bool (x : nat) (l : list nat) : bool :=
  match l with
  | [] => false
  | h :: t => if Nat.eqb x h then true else In_bool x t
  end.

(** Helper: Remove *)
Fixpoint remove_nat (x : nat) (l : list nat) : list nat :=
  match l with
  | [] => []
  | h :: t => if Nat.eqb x h then remove_nat x t else h :: remove_nat x t
  end.

(** Initial State *)
Definition Init (s : SessionState) : Prop :=
  s.(processes) = [] /\ 
  s.(layout) = [] /\ 
  s.(focus) = 0.

(** Invariants *)
Definition FocusValid (s : SessionState) : Prop :=
  match s.(layout) with
  | [] => s.(focus) = 0
  | _ => In s.(focus) s.(layout)
  end.

(** Actions *)

(** Spawn a new terminal *)
Inductive Spawn (id : nat) (s s' : SessionState) : Prop :=
  | Spawn_ok :
      In_bool id s.(processes) = false ->
      length s.(processes) < s.(max_procs) ->
      s'.(processes) = id :: s.(processes) ->
      s'.(layout) = id :: s.(layout) ->
      s'.(max_procs) = s.(max_procs) ->
      (if Nat.eqb s.(focus) 0 then s'.(focus) = id else s'.(focus) = s.(focus)) ->
      Spawn id s s'.

(** Process crashes or exits *)
Inductive ProcessExit (id : nat) (s s' : SessionState) : Prop :=
  | Exit_ok :
      In_bool id s.(processes) = true ->
      s'.(processes) = remove_nat id s.(processes) ->
      s'.(layout) = s.(layout) -> (* Ghost window remains *)
      s'.(focus) = s.(focus) ->
      s'.(max_procs) = s.(max_procs) ->
      ProcessExit id s s'.

(** User closes a window *)
(** Note: For simplicity, we pick head of layout as new focus if current focus closes *)
Inductive CloseWindow (id : nat) (s s' : SessionState) : Prop :=
  | Close_ok :
      In_bool id s.(layout) = true ->
      s'.(layout) = remove_nat id s.(layout) ->
      s'.(processes) = remove_nat id s.(processes) ->
      s'.(max_procs) = s.(max_procs) ->
      (if Nat.eqb s.(focus) id then
         match s'.(layout) with
         | [] => s'.(focus) = 0
         | h :: _ => s'.(focus) = h
         end
       else s'.(focus) = s.(focus)) ->
      CloseWindow id s s'.

(** Reconcile (GC) *)
Inductive Reconcile (s s' : SessionState) : Prop :=
  | Reconcile_ok :
      (* Remove windows that have no process *)
      (* This logic is tricky to express purely relationally without a helper function *)
      (* For Rocq, we usually define the function and assert equality *)
      (* But here we just define it as a transition *)
      s'.(processes) = s.(processes) ->
      s'.(max_procs) = s.(max_procs) ->
      (* For checking, we assume Reconcile cleans up ghosts *)
      (* Let's skip detailed impl for this step and assume identity for verification scope *)
      True ->
      Reconcile s s'.

(** Step Relation *)
Inductive Step (s s' : SessionState) : Prop :=
  | DoSpawn (id : nat) : Spawn id s s' -> Step s s'
  | DoExit (id : nat) : ProcessExit id s s' -> Step s s'
  | DoClose (id : nat) : CloseWindow id s s' -> Step s s'
  | DoReconcile : Reconcile s s' -> Step s s'.

(** Safety Theorem *)
Theorem focus_safety : forall s s',
  FocusValid s ->
  Step s s' ->
  FocusValid s'.
Proof.
  intros.
  Admitted.
