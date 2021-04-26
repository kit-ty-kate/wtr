open! Core

module Path = struct
  type ('ty, 'v) t =
    | End : ('v, 'v) t
    | Literal : string * ('ty, 'v) t -> ('ty, 'v) t
    | String : ('ty, 'v) t -> (string -> 'ty, 'v) t
    | Int : ('ty, 'v) t -> (int -> 'ty, 'v) t
    | Float : ('ty, 'v) t -> (int -> 'ty, 'v) t
    | Bool : ('ty, 'v) t -> (bool -> 'ty, 'v) t
end

module Route = struct
  type (_, _) t =
    | End : ('a, 'b) t
    | Combine : ('a, 'b) Path.t * ('b, 'c) t -> ('a, 'c) t
end

type route_handler = Handler : ('ty, 'v) Route.t * 'ty -> route_handler

(** Router *)
type t =
  | Node of
      { route_handler : route_handler option
      ; literal : t String.Map.t
      ; int_param : t option
      }

let empty_with route_handler =
  Node { route_handler; literal = String.Map.empty; int_param = None }

let empty = empty_with None

module R = Route
module P = Path

let add : type ty v. (ty, v) Route.t -> ty -> t -> t =
 fun route f t ->
  let loop (Node _node) = function
    | R.End -> empty_with (Some (Handler (route, f)))
    | R.Combine (_, _) -> empty_with (Some (Handler (route, f)))
  in
  loop t route

let match_uri : t -> string -> 'a option = fun _router uri -> Some uri

(* /home/:string/:int*)
let r1 : (string -> int -> 'a, 'a) Route.t =
  Combine (P.Literal ("home", P.String (P.Int P.End)), R.End)

(* /home/:string/:string *)
let r2 : (string -> string -> 'a, 'a) Route.t =
  Combine (P.Literal ("home", P.String (P.String P.End)), R.End)

let router =
  empty
  |> add r1 (fun (s1 : string) (i : int) -> s1 ^ " || " ^ string_of_int i)
  |> add r2 (fun (s1 : string) (s2 : string) -> s1 ^ " || " ^ s2)
