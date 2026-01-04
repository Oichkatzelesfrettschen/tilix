(**
 * Extraction Configuration
 * Generates OCaml code from Coq specifications.
 *)

From Stdlib Require Import extraction.ExtrOcamlBasic.
From Stdlib Require Import extraction.ExtrOcamlNatInt.
From Stdlib Require Import extraction.ExtrOcamlZInt.

Require Import verification.Layout.
Require Import verification.Graph.
Require Import verification.Session.
Require Import verification.Terminal.

(* Extract Layout to OCaml *)
(* We extract the main functions; types are included automatically *)
Extraction "verification/Layout.ml" Valid calculate_resize balance count_leaves.

(* Extract Graph to OCaml *)
Extraction "verification/Graph.ml" bfs.

(* Extract Session to OCaml *)
(* SessionState is a Record, usually extractable types. 
   We extract 'Init' and 'Step'? They are Props. 
   Usually we extract executable functions. 
   Session.v defines a relational spec (Inductive Step). 
   To extract, we would need a functional implementation (like `step_function`).
   Currently Session.v is purely specification (Prop).
   So we just check it compiles. No extraction for Session yet.
*)

(* Extract Terminal to OCaml *)
Extraction "verification/Terminal.ml" move_right move_left move_down move_up.