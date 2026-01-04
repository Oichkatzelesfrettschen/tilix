(**
 * Formal Specification of Terminal State
 *
 * Verifies cursor bounds and basic buffer operations.
 *)

From Stdlib Require Import Arith.Arith.
From Stdlib Require Import Init.Nat.

Set Primitive Projections.

Record TerminalState : Set := mkTerm {
  cols : nat;
  rows : nat;
  cursor_x : nat;
  cursor_y : nat
}.

(** Invariant: Cursor must be within bounds *)
Definition InBounds (t : TerminalState) : Prop :=
  (cursor_x t) < (cols t) /\ (cursor_y t) < (rows t).

(** Operations *)

Definition move_right (t : TerminalState) : TerminalState :=
  if (cursor_x t) + 1 <? (cols t) then
    mkTerm (cols t) (rows t) ((cursor_x t) + 1) (cursor_y t)
  else t.

Definition move_left (t : TerminalState) : TerminalState :=
  if 0 <? (cursor_x t) then
    mkTerm (cols t) (rows t) ((cursor_x t) - 1) (cursor_y t)
  else t.

Definition move_down (t : TerminalState) : TerminalState :=
  if (cursor_y t) + 1 <? (rows t) then
    mkTerm (cols t) (rows t) (cursor_x t) ((cursor_y t) + 1)
  else t.

Definition move_up (t : TerminalState) : TerminalState :=
  if 0 <? (cursor_y t) then
    mkTerm (cols t) (rows t) (cursor_x t) ((cursor_y t) - 1)
  else t.

(** Proofs *)

Theorem right_safe : forall t, InBounds t -> InBounds (move_right t).
Proof.
  intros t H.
  unfold move_right.
  destruct (cursor_x t + 1 <? cols t) eqn:Heq.
  - unfold InBounds in *.
    destruct H as [Hx Hy].
    split; simpl.
    + apply Nat.ltb_lt in Heq. assumption.
    + assumption.
  - assumption.
Qed.

Theorem left_safe : forall t, InBounds t -> InBounds (move_left t).
Proof.
  intros t H.
  unfold move_left.
  destruct (0 <? cursor_x t) eqn:Heq.
  - unfold InBounds in *.
    destruct H as [Hx Hy].
    split; simpl.
    + apply Nat.lt_le_trans with (cursor_x t).
      * apply Nat.sub_lt; auto. apply Nat.ltb_lt in Heq. assumption.
      * apply Nat.lt_le_incl. assumption.
    + assumption.
  - assumption.
Qed.

Theorem down_safe : forall t, InBounds t -> InBounds (move_down t).
Proof.
  intros t H.
  unfold move_down.
  destruct (cursor_y t + 1 <? rows t) eqn:Heq.
  - unfold InBounds in *.
    destruct H as [Hx Hy].
    split; simpl.
    + assumption.
    + apply Nat.ltb_lt in Heq. assumption.
  - assumption.
Qed.

Theorem up_safe : forall t, InBounds t -> InBounds (move_up t).
Proof.
  intros t H.
  unfold move_up.
  destruct (0 <? cursor_y t) eqn:Heq.
  - unfold InBounds in *.
    destruct H as [Hx Hy].
    split; simpl.
    + assumption.
    + apply Nat.lt_le_trans with (cursor_y t).
      * apply Nat.sub_lt; auto. apply Nat.ltb_lt in Heq. assumption.
      * apply Nat.lt_le_incl. assumption.
  - assumption.
Qed.
