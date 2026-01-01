Require Import Layout.

(** Configure Extraction to OCaml *)
Require Import Coq.extraction.ExtrOcamlBasic.
Require Import Coq.extraction.ExtrOcamlNatInt.

(** Extract the Layout logic recursively *)
Recursive Extraction Library Layout.