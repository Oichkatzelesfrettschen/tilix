open Nat

type coq_Coordinate = int

type coq_Dimension = int

type coq_Rect = { x : coq_Coordinate; y : coq_Coordinate; w : coq_Dimension;
                  h : coq_Dimension }

(** val x : coq_Rect -> coq_Coordinate **)

let x r =
  r.x

(** val y : coq_Rect -> coq_Coordinate **)

let y r =
  r.y

(** val w : coq_Rect -> coq_Dimension **)

let w r =
  r.w

(** val h : coq_Rect -> coq_Dimension **)

let h r =
  r.h

type coq_Layout =
| Window of int * coq_Rect
| HSplit of coq_Layout * coq_Layout * int
| VSplit of coq_Layout * coq_Layout * int

(** val coq_Layout_rect :
    (int -> coq_Rect -> 'a1) -> (coq_Layout -> 'a1 -> coq_Layout -> 'a1 ->
    int -> 'a1) -> (coq_Layout -> 'a1 -> coq_Layout -> 'a1 -> int -> 'a1) ->
    coq_Layout -> 'a1 **)

let rec coq_Layout_rect f f0 f1 = function
| Window (id, r) -> f id r
| HSplit (l0, r, ratio) ->
  f0 l0 (coq_Layout_rect f f0 f1 l0) r (coq_Layout_rect f f0 f1 r) ratio
| VSplit (t, b, ratio) ->
  f1 t (coq_Layout_rect f f0 f1 t) b (coq_Layout_rect f f0 f1 b) ratio

(** val coq_Layout_rec :
    (int -> coq_Rect -> 'a1) -> (coq_Layout -> 'a1 -> coq_Layout -> 'a1 ->
    int -> 'a1) -> (coq_Layout -> 'a1 -> coq_Layout -> 'a1 -> int -> 'a1) ->
    coq_Layout -> 'a1 **)

let rec coq_Layout_rec f f0 f1 = function
| Window (id, r) -> f id r
| HSplit (l0, r, ratio) ->
  f0 l0 (coq_Layout_rec f f0 f1 l0) r (coq_Layout_rec f f0 f1 r) ratio
| VSplit (t, b, ratio) ->
  f1 t (coq_Layout_rec f f0 f1 t) b (coq_Layout_rec f f0 f1 b) ratio

(** val area : coq_Layout -> int **)

let rec area = function
| Window (_, r) -> mul r.w r.h
| HSplit (l0, r, _) -> add (area l0) (area r)
| VSplit (t, b, _) -> add (area t) (area b)
