
(** val add : int -> int -> int **)

let rec add = (+)

(** val sub : int -> int -> int **)

let rec sub = fun n m -> Stdlib.max 0 (n-m)

(** val leb : int -> int -> bool **)

let rec leb n m =
  (fun fO fS n -> if n=0 then fO () else fS (n-1))
    (fun _ -> true)
    (fun n' ->
    (fun fO fS n -> if n=0 then fO () else fS (n-1))
      (fun _ -> false)
      (fun m' -> leb n' m')
      m)
    n

(** val ltb : int -> int -> bool **)

let ltb n m =
  leb (Stdlib.Int.succ n) m

type terminalState = { cols : int; rows : int; cursor_x : int; cursor_y : int }

(** val move_right : terminalState -> terminalState **)

let move_right t =
  if ltb (add t.cursor_x (Stdlib.Int.succ 0)) t.cols
  then { cols = t.cols; rows = t.rows; cursor_x =
         (add t.cursor_x (Stdlib.Int.succ 0)); cursor_y = t.cursor_y }
  else t

(** val move_left : terminalState -> terminalState **)

let move_left t =
  if ltb 0 t.cursor_x
  then { cols = t.cols; rows = t.rows; cursor_x =
         (sub t.cursor_x (Stdlib.Int.succ 0)); cursor_y = t.cursor_y }
  else t

(** val move_down : terminalState -> terminalState **)

let move_down t =
  if ltb (add t.cursor_y (Stdlib.Int.succ 0)) t.rows
  then { cols = t.cols; rows = t.rows; cursor_x = t.cursor_x; cursor_y =
         (add t.cursor_y (Stdlib.Int.succ 0)) }
  else t

(** val move_up : terminalState -> terminalState **)

let move_up t =
  if ltb 0 t.cursor_y
  then { cols = t.cols; rows = t.rows; cursor_x = t.cursor_x; cursor_y =
         (sub t.cursor_y (Stdlib.Int.succ 0)) }
  else t
