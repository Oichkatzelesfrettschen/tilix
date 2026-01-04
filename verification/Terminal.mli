
val add : int -> int -> int

val sub : int -> int -> int

val leb : int -> int -> bool

val ltb : int -> int -> bool

type terminalState = { cols : int; rows : int; cursor_x : int; cursor_y : int }

val move_right : terminalState -> terminalState

val move_left : terminalState -> terminalState

val move_down : terminalState -> terminalState

val move_up : terminalState -> terminalState
