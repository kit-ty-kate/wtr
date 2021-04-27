open! Core

module Path = struct
  type ('a, 'b) t =
    | End : ('b, 'b) t
    | Literal : string * ('a, 'b) t -> ('a, 'b) t
        (** Literal path component eg. 'home' in '/home' *)
    | Param : 'c param * ('a, 'b) t -> ('c -> 'a, 'b) t
        (** Parameter path component eg. ':int' in '/home/:int' *)

  (* Parameter detail. *)
  and 'c param =
    { encode : string -> 'c option
    ; decode : 'c -> string
    ; name : string (* name e.g. :int, :float, :bool, :string etc *)
    }

  (** [kind] encodes path kind/type. *)
  type kind =
    | KLiteral : string -> kind
    | KParam : 'c param -> kind

  (* [of_path path] converts [path] to [Path_pattern.t list]. This is done to
     get around some typing issue with using Path.t in the [add] function below. *)
  let rec kind : type a b. (a, b) t -> kind list = function
    | End -> []
    | Literal (lit, path) -> KLiteral lit :: kind path
    | Param (conv, path) -> KParam conv :: kind path

  let param path par = Param (par, path)

  let create encode decode name = { encode; decode; name }

  let string : ('a, 'b) t -> (string -> 'a, 'b) t =
   fun path -> create (fun s -> Some s) Fun.id ":string" |> param path

  let int : ('a, 'b) t -> (int -> 'a, 'b) t =
   fun path -> create int_of_string_opt string_of_int ":int" |> param path

  let float : ('a, 'b) t -> (float -> 'a, 'b) t =
   fun path -> create float_of_string_opt string_of_float ":float" |> param path

  let bool : ('a, 'b) t -> (bool -> 'a, 'b) t =
   fun path -> create bool_of_string_opt string_of_bool ":bool" |> param path
end

(** ['c route] is a path with its handler. ['c] represents the value returned by
    the route handler. *)
type 'c route = Route : ('a, 'c) Path.t * 'a -> 'c route

(** [p @-> route_handler] creates a route from path [p] and [route_handler]. *)
let ( @-> ) : ('a, 'b) Path.t -> 'a -> 'b route = fun path f -> Route (path, f)

(** ['a t] is a trie based router where ['a] is the route value. *)
type 'a t =
  | Node of
      { route : 'a route option
      ; literals : 'a t String.Map.t
      ; params : 'a t String.Map.t
      }

let empty_with route =
  Node { route; literals = String.Map.empty; params = String.Map.empty }

let empty = empty_with None

module Path_pattern = struct end

let add : 'b route -> 'b t -> 'b t =
 fun route t ->
  let (Route (path, _)) = route in
  let rec loop : 'b t -> Path.kind list -> 'b t =
   fun (Node t) -> function
    | [] -> Node { t with route = Some route }
    | KLiteral lit :: path_patterns ->
      let literals =
        match String.Map.find t.literals lit with
        | Some t' ->
          String.Map.change t.literals lit ~f:(function
              | Some _
              | None
              -> Some (loop t' path_patterns))
        | None ->
          String.Map.add_exn t.literals ~key:lit
            ~data:(loop empty path_patterns)
      in
      Node { t with literals }
    (* | PInt :: path_patterns -> *)
    (*   let int_param = *)
    (*     let t' = Option.value t.int_param ~default:empty in *)
    (*     Some (loop t' path_patterns) *)
    (*   in *)
    (*   Node { t with int_param } *)
    | _ -> assert false
  in
  loop t (Path.kind path)

(* let match' : 'b route t -> string -> 'b option = fun router uri -> *)

(* None *)

let r1 =
  Path.(string (int End)) @-> fun (s : string) (i : int) -> s ^ string_of_int i

let r2 : string route = Path.(Literal ("home", Literal ("about", End))) @-> ""

let r3 : string route =
  Path.(Literal ("home", int End)) @-> fun (i : int) -> string_of_int i

let r4 : string route =
  Path.(Literal ("home", float End)) @-> fun (f : float) -> string_of_float f

(** This should give error (we added an extra () param in handler) but it
    doesn't. It only errors when adding to the router.*)
let r5 =
  Path.(string (int End))
  @-> fun (s : string) (i : int) () -> s ^ string_of_int i

let router = empty |> add r1 |> add r2 |> add r3 |> add r4

(* |> add r5  *)
(* This errors *)
