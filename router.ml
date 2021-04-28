open! Core

(** [('a, 'b) uri] represents a uniform resource identifier *)
type ('a, 'b) uri =
  | End : ('b, 'b) uri
  | Literal : string * ('a, 'b) uri -> ('a, 'b) uri
      (** Uri literal string component eg. 'home' in '/home' *)
  | Var : 'c var * ('a, 'b) uri -> ('c -> 'a, 'b) uri
      (** Uri variable component, i.e. the value is determined during runtime,
          eg. ':int' in '/home/:int' *)

and 'c var =
  { decode : string -> 'c option
  ; encode : 'c -> string
  ; name : string (* name e.g. :int, :float, :bool, :string etc *)
  }

let end_ : ('b, 'b) uri = End

let lit : string -> ('a, 'b) uri -> ('a, 'b) uri = fun s uri -> Literal (s, uri)

let var decode encode name uri = Var ({ encode; decode; name }, uri)

let string : ('a, 'b) uri -> (string -> 'a, 'b) uri =
 fun uri -> var (fun s -> Some s) Fun.id ":string" uri

let int : ('a, 'b) uri -> (int -> 'a, 'b) uri =
 fun uri -> var int_of_string_opt string_of_int ":int" uri

let float : ('a, 'b) uri -> (float -> 'a, 'b) uri =
 fun uri -> var float_of_string_opt string_of_float ":float" uri

let bool : ('a, 'b) uri -> (bool -> 'a, 'b) uri =
 fun uri -> var bool_of_string_opt string_of_bool ":bool" uri

(** [kind] encodes uri kind/type. *)
type kind =
  | KLiteral : string -> kind
  | KParam : 'c var -> kind

(* [kind uri] converts [uri] to [kind list]. This is done to get around OCaml
   type inference issue when using [uri] type in the [add] function below. *)
let rec kind : type a b. (a, b) uri -> kind list = function
  | End -> []
  | Literal (lit, uri) -> KLiteral lit :: kind uri
  | Var (conv, uri) -> KParam conv :: kind uri

(** ['c route] is a uri and its handler. ['c] represents the value returned by
    the handler. *)
type 'c route = Route : ('a, 'c) uri * 'a -> 'c route

(** [p @-> route_handler] creates a route from uri [p] and [route_handler]. *)
let ( @-> ) : ('a, 'b) uri -> 'a -> 'b route = fun uri f -> Route (uri, f)

(** ['a t] is a trie based router where ['a] is the route value. *)
type 'a t =
  | Node of
      { route : 'a route option
      ; literals : 'a t String.Map.t
      ; vars : 'a t String.Map.t
      }

let empty_with route =
  Node { route; literals = String.Map.empty; vars = String.Map.empty }

let empty = empty_with None

let add : 'b route -> 'b t -> 'b t =
 fun route t ->
  let (Route (uri, _)) = route in
  let rec loop : 'b t -> kind list -> 'b t =
   fun (Node t) kinds ->
    let add_update m key kinds =
      match String.Map.find m key with
      | Some t' ->
        String.Map.change m key ~f:(function
            | Some _
            | None
            -> Some (loop t' kinds))
      | None -> String.Map.add_exn m ~key ~data:(loop empty kinds)
    in
    match kinds with
    | [] -> Node { t with route = Some route }
    | KLiteral lit :: kinds ->
      let literals = add_update t.literals lit kinds in
      Node { t with literals }
    | KParam p :: kinds ->
      let vars = add_update t.vars p.name kinds in
      Node { t with vars }
  in
  loop t (kind uri)

let rec match' : 'b t -> string -> 'b option =
 fun t uri ->
  let tokens =
    String.rstrip uri ~drop:(function
      | '/' -> true
      | _ -> false)
    |> String.split ~on:'/'
  in
  let loop (Node t) vars tokens =
    match tokens with
    | [] -> Option.map t.route ~f:(fun (Route (path, f)) -> apply path f vars)
    | _ -> assert false
  in
  loop t [] tokens

and apply : type a b. (a, b) uri -> a -> string list -> b =
 fun uri f vars ->
  match (uri, vars) with
  | End, [] -> f
  | Literal (_, uri), vars -> apply uri f vars
  | Var (conv, uri), p :: vars -> (
    match conv.decode p with
    | Some p' -> apply uri (f p') vars
    | None -> failwith "Route not matched")
  | _, _ -> failwith "Route not matched"

(* None *)

let r1 = string (int end_) @-> fun (s : string) (i : int) -> s ^ string_of_int i

let r2 : string route = lit "home" (lit "about" end_) @-> ""

let r3 : string route =
  lit "home" (int end_) @-> fun (i : int) -> string_of_int i

let r4 : string route =
  lit "home" (float end_) @-> fun (f : float) -> string_of_float f

(** This should give error (we added an extra () var in handler) but it doesn't.
    It only errors when adding to the router.*)
let r5 =
  string (int end_) @-> fun (s : string) (i : int) () -> s ^ string_of_int i

let router = empty |> add r1 |> add r2 |> add r3 |> add r4

(* |> add r5  *)
(* This errors *)
