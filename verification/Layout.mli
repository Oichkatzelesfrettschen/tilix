
type __ = Obj.t

val fst : ('a1 * 'a2) -> 'a1

type comparison =
| Eq
| Lt
| Gt

val add : int -> int -> int

val mul : int -> int -> int

val sub : int -> int -> int

module Nat :
 sig
  val divmod : int -> int -> int -> int -> int * int

  val div : int -> int -> int
 end

module Pos :
 sig
  val succ : int -> int

  val add : int -> int -> int

  val add_carry : int -> int -> int

  val pred_double : int -> int

  val mul : int -> int -> int

  val compare_cont : comparison -> int -> int -> comparison

  val compare : int -> int -> comparison

  val iter_op : ('a1 -> 'a1 -> 'a1) -> int -> 'a1 -> 'a1

  val to_nat : int -> int

  val of_succ_nat : int -> int
 end

module Z :
 sig
  val double : int -> int

  val succ_double : int -> int

  val pred_double : int -> int

  val pos_sub : int -> int -> int

  val add : int -> int -> int

  val opp : int -> int

  val sub : int -> int -> int

  val mul : int -> int -> int

  val compare : int -> int -> comparison

  val leb : int -> int -> bool

  val ltb : int -> int -> bool

  val to_nat : int -> int

  val of_nat : int -> int

  val pos_div_eucl : int -> int -> int * int

  val div_eucl : int -> int -> int * int

  val div : int -> int -> int

  val gtb : int -> int -> bool
 end

type layoutConfig = { min_size : int; handle_size : int; char_width : 
                      int; char_height : int }

type axis =
| Horizontal
| Vertical

type layout =
| Leaf of int
| Node of axis * int * layout * layout

type layoutRect = { x : int; y : int; w : int; h : int }

val dim_on : axis -> layoutRect -> int

type valid = __

val count_leaves : layout -> int

val balance : layoutConfig -> layoutRect -> layout -> layout

val snap_to_grid : int -> int -> int

val calculate_resize : layoutConfig -> int -> int -> int -> axis -> int option
