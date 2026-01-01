open Nat

type coq_Coordinate = int

type coq_Dimension = int

type coq_Rect = { x : coq_Coordinate; y : coq_Coordinate; w : coq_Dimension;
                  h : coq_Dimension }

val x : coq_Rect -> coq_Coordinate

val y : coq_Rect -> coq_Coordinate

val w : coq_Rect -> coq_Dimension

val h : coq_Rect -> coq_Dimension

type coq_Layout =
| Window of int * coq_Rect
| HSplit of coq_Layout * coq_Layout * int
| VSplit of coq_Layout * coq_Layout * int

val coq_Layout_rect :
  (int -> coq_Rect -> 'a1) -> (coq_Layout -> 'a1 -> coq_Layout -> 'a1 -> int
  -> 'a1) -> (coq_Layout -> 'a1 -> coq_Layout -> 'a1 -> int -> 'a1) ->
  coq_Layout -> 'a1

val coq_Layout_rec :
  (int -> coq_Rect -> 'a1) -> (coq_Layout -> 'a1 -> coq_Layout -> 'a1 -> int
  -> 'a1) -> (coq_Layout -> 'a1 -> coq_Layout -> 'a1 -> int -> 'a1) ->
  coq_Layout -> 'a1

val area : coq_Layout -> int
