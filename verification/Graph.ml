
(** val fst : ('a1 * 'a2) -> 'a1 **)

let fst = function
| (x, _) -> x

(** val app : 'a1 list -> 'a1 list -> 'a1 list **)

let rec app l m =
  match l with
  | [] -> m
  | a :: l1 -> a :: (app l1 m)

module Nat =
 struct
 end

(** val map : ('a1 -> 'a2) -> 'a1 list -> 'a2 list **)

let rec map f = function
| [] -> []
| a :: l0 -> (f a) :: (map f l0)

type node = int

type weight = int

type edge = node * weight

type graph = { nodes : node list; adj : (node -> edge list) }

(** val member : node -> node list -> bool **)

let rec member n = function
| [] -> false
| h :: t -> if (=) n h then true else member n t

(** val bfs_step : graph -> node list -> node list -> int -> node list **)

let rec bfs_step g queue visited gas =
  (fun fO fS n -> if n=0 then fO () else fS (n-1))
    (fun _ -> visited)
    (fun n ->
    match queue with
    | [] -> visited
    | u :: q_rest ->
      if member u visited
      then bfs_step g q_rest visited n
      else let new_visited = u :: visited in
           let neighbors = map fst (g.adj u) in
           let new_queue = app q_rest neighbors in
           bfs_step g new_queue new_visited n)
    gas

(** val bfs : graph -> node -> int -> node list **)

let bfs g start fuel =
  bfs_step g (start :: []) [] fuel
