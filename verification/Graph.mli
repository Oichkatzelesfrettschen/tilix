
val fst : ('a1 * 'a2) -> 'a1

val app : 'a1 list -> 'a1 list -> 'a1 list

module Nat :
 sig
 end

val map : ('a1 -> 'a2) -> 'a1 list -> 'a2 list

type node = int

type weight = int

type edge = node * weight

type graph = { nodes : node list; adj : (node -> edge list) }

val member : node -> node list -> bool

val bfs_step : graph -> node list -> node list -> int -> node list

val bfs : graph -> node -> int -> node list
