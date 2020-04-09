(* Representation *)
type lab = string
type var = string

type control =
  | Returns        (* regular local function or one-shot shared function *)
  | Promises       (* shared function producing a future value upon call *)
  | Replies        (* (IR only): responds asynchronously using `reply` *)

type obj_sort = Object | Actor | Module
type shared_sort = Query | Write
type 'a shared = Local | Shared of 'a
type func_sort = shared_sort shared
type eff = Triv | Await

type prim =
  | Null
  | Bool
  | Nat
  | Nat8
  | Nat16
  | Nat32
  | Nat64
  | Int
  | Int8
  | Int16
  | Int32
  | Int64
  | Word8
  | Word16
  | Word32
  | Word64
  | Float
  | Char
  | Text
  | Blob (* IR use: Packed representation, vec u8 IDL type *)
  | Error
  | Principal

type t = typ
and typ =
  | Var of var * int                          (* variable *)
  | Con of con * typ list                     (* constructor *)
  | Prim of prim                              (* primitive *)
  | Obj of obj_sort * field list              (* object *)
  | Variant of field list                     (* variant *)
  | Array of typ                              (* array *)
  | Opt of typ                                (* option *)
  | Tup of typ list                           (* tuple *)
  | Func of func_sort * control * bind list * typ list * typ list  (* function *)
  | Async of scope * typ                      (* future *)
  | Mut of typ                                (* mutable type *)
  | Any                                       (* top *)
  | Non                                       (* bottom *)
  | Typ of con                                (* type (field of module) *)
  | Pre                                       (* pre-type *)

and scope = typ
and bind_sort = Scope | Type

and bind = {var : var; sort: bind_sort; bound : typ}
and field = {lab : lab; typ : typ}

and con = kind Con.t
and kind =
  | Def of bind list * typ
  | Abs of bind list * typ

(* Function sorts *)

let is_shared_sort sort = sort <> Local

(* Constructors *)

let set_kind c k =
  match Con.kind c with
  | Abs (_, Pre) -> Con.unsafe_set_kind c k
  | _ -> raise (Invalid_argument "set_kind")

module ConEnv = Env.Make(struct type t = con let compare = Con.compare end)
module ConSet = ConEnv.Dom


(* Field ordering *)

let compare_field f1 f2 =
  match f1,f2 with
  | {lab = l1; typ = Typ _}, {lab = l2; typ = Typ _ } -> compare l1 l2
  | {lab = l1; typ = Typ _}, {lab = l2; typ = _ } -> -1
  | {lab = l1; typ = _}, {lab = l2; typ = Typ _ } -> 1
  | {lab = l1; typ = _}, {lab = l2; typ = _ } -> compare l1 l2


(* Short-hands *)

let unit = Tup []
let bool = Prim Bool
let nat = Prim Nat
let int = Prim Int
let text = Prim Text
let blob = Prim Blob
let error = Prim Error
let char = Prim Char

let throwErrorCodes = List.sort compare_field [
  { lab = "error"; typ = unit }
]

let catchErrorCodes = List.sort compare_field (
  throwErrorCodes @ [
    { lab = "system"; typ = unit}
      (* TBC *)
  ])

let throw = Prim Error
let catch = Prim Error

(* Shared call context *)

let caller = Prim Principal
let ctxt = Obj (Object,[{ lab = "caller"; typ = caller }])

let prim = function
  | "Null" -> Null
  | "Bool" -> Bool
  | "Nat" -> Nat
  | "Nat8" -> Nat8
  | "Nat16" -> Nat16
  | "Nat32" -> Nat32
  | "Nat64" -> Nat64
  | "Int" -> Int
  | "Int8" -> Int8
  | "Int16" -> Int16
  | "Int32" -> Int32
  | "Int64" -> Int64
  | "Word8" -> Word8
  | "Word16" -> Word16
  | "Word32" -> Word32
  | "Word64" -> Word64
  | "Float" -> Float
  | "Char" -> Char
  | "Text" -> Text
  | "Blob" -> Blob
  | "Error" -> Error
  | "Principal" -> Principal
  | s -> raise (Invalid_argument ("Type.prim: " ^ s))

let seq = function [t] -> t | ts -> Tup ts

let codom c to_scope ts2 =  match c with
  | Promises -> Async (to_scope(), seq ts2)
  | Returns -> seq ts2
  | Replies -> Tup []

(* Coercions *)

let iter_obj t =
  Obj (Object,
    [{lab = "next"; typ = Func (Local, Returns, [], [], [Opt t])}])


(* Shifting *)

let rec shift i n t =
  match t with
  | Prim _ -> t
  | Var (s, j) -> Var (s, if j < i then j else j + n)
  | Con (c, ts) -> Con (c, List.map (shift i n) ts)
  | Array t -> Array (shift i n t)
  | Tup ts -> Tup (List.map (shift i n) ts)
  | Func (s, c, tbs, ts1, ts2) ->
    let i' = i + List.length tbs in
    Func (s, c, List.map (shift_bind i' n) tbs, List.map (shift i' n) ts1, List.map (shift i' n) ts2)
  | Opt t -> Opt (shift i n t)
  | Async (t1, t2) -> Async (shift i n t1, shift i n t2)
  | Obj (s, fs) -> Obj (s, List.map (shift_field n i) fs)
  | Variant fs -> Variant (List.map (shift_field n i) fs)
  | Mut t -> Mut (shift i n t)
  | Any -> Any
  | Non -> Non
  | Pre -> Pre
  | Typ c -> Typ c

and shift_bind i n tb =
  {tb with bound = shift i n tb.bound}

and shift_field i n {lab; typ} =
  {lab; typ = shift i n typ}

(*
and shift_kind i n k =
  match k with
  | Def (tbs, t) ->
    let i' = i + List.length tbs in
    Def (List.map (shift_bind i' n) tbs, shift i' n t)
  | Abs (tbs, t) ->
    let i' = i + List.length tbs in
    Abs (List.map (shift_bind i' n) tbs, shift i' n t)
 *)


(* First-order substitution *)

let rec subst sigma t =
  if sigma = ConEnv.empty then t else
  match t with
  | Prim _
  | Var _ -> t
  | Con (c, ts) ->
    (match ConEnv.find_opt c sigma with
    | Some t -> assert (List.length ts = 0); t
    | None -> Con (c, List.map (subst sigma) ts)
    )
  | Array t -> Array (subst sigma t)
  | Tup ts -> Tup (List.map (subst sigma) ts)
  | Func (s, c, tbs, ts1, ts2) ->
    let sigma' = ConEnv.map (shift 0 (List.length tbs)) sigma in
    Func (s, c, List.map (subst_bind sigma') tbs,
          List.map (subst sigma') ts1, List.map (subst sigma') ts2)
  | Opt t -> Opt (subst sigma t)
  | Async (t1, t2) -> Async (subst sigma t1, subst sigma t2)
  | Obj (s, fs) -> Obj (s, List.map (subst_field sigma) fs)
  | Variant fs -> Variant (List.map (subst_field sigma) fs)
  | Mut t -> Mut (subst sigma t)
  | Any -> Any
  | Non -> Non
  | Pre -> Pre
  | Typ c -> Typ c (* NB: this is incorrect unless we ensure dom(sigma) \cap FV(c.kind) = {}
                      For now, we could do this by ensuring all type definitions are closed,
                      in particular, type components defined within the scope of an enclosing
                      type parameter cannot mention that parameter
                      (but can mention other (closed) type constructors).
                    *)

and subst_bind sigma tb =
  { tb with bound = subst sigma tb.bound}

and subst_field sigma {lab; typ} =
  {lab; typ = subst sigma typ}

(*
and subst_kind sigma k =
  match k with
  | Def (tbs, t) ->
    let sigma' = ConEnv.map (shift 0 (List.length tbs)) sigma in
    Def (List.map (subst_bind sigma') tbs, subst sigma' t)
  | Abs (tbs, t) ->
    let sigma' = ConEnv.map (shift 0 (List.length tbs)) sigma in
    Abs (List.map (subst_bind sigma') tbs, subst sigma' t)
 *)

(* Handling binders *)

let close cs t =
  if cs = [] then t else
  let ts = List.mapi (fun i c -> Var (Con.name c, i)) cs in
  let sigma = List.fold_right2 ConEnv.add cs ts ConEnv.empty in
  subst sigma t

let close_binds cs tbs =
  if cs = [] then tbs else
  List.map (fun tb -> { tb with bound = close cs tb.bound })  tbs


let rec open' i ts t =
  match t with
  | Prim _ -> t
  | Var (_, j) -> if j < i then t else List.nth ts (j - i)
  | Con (c, ts') -> Con (c, List.map (open' i ts) ts')
  | Array t -> Array (open' i ts t)
  | Tup ts' -> Tup (List.map (open' i ts) ts')
  | Func (s, c, tbs, ts1, ts2) ->
    let i' = i + List.length tbs in
    Func (s, c, List.map (open_bind i' ts) tbs, List.map (open' i' ts) ts1, List.map (open' i' ts) ts2)
  | Opt t -> Opt (open' i ts t)
  | Async (t1, t2) -> Async (open' i ts t1, open' i ts t2)
  | Obj (s, fs) -> Obj (s, List.map (open_field i ts) fs)
  | Variant fs -> Variant (List.map (open_field i ts) fs)
  | Mut t -> Mut (open' i ts t)
  | Any -> Any
  | Non -> Non
  | Pre -> Pre
  | Typ c -> Typ c

and open_bind i ts tb  =
  {tb with bound = open' i ts tb.bound}

and open_field i ts {lab; typ} =
  {lab; typ = open' i ts typ}

(*
and open_kind i ts k =
  match k with
  | Def (tbs, t) ->
    let i' = i + List.length tbs in
    Def (List.map (open_bind i' ts) tbs, open' i' ts t)
  | Abs (tbs, t) ->
    let i' = i + List.length tbs in
    Abs (List.map (open_bind i' ts) tbs, open' i' ts t)
*)

let open_ ts t =
  if ts = [] then t else
  open' 0 ts t

let open_binds tbs =
  if tbs = [] then [] else
  let cs = List.map (fun {var; _} -> Con.fresh var (Abs ([], Pre))) tbs in
  let ts = List.map (fun c -> Con (c, [])) cs in
  let ks = List.map (fun {bound; _} -> Abs ([], open_ ts bound)) tbs in
  List.iter2 set_kind cs ks;
  ts


(* Normalization and Classification *)

let reduce tbs t ts =
  assert (List.length ts = List.length tbs);
  open_ ts t

let rec normalize = function
  | Con (con, ts) as t ->
    (match Con.kind con with
    | Def (tbs, t) -> normalize (reduce tbs t ts)
    | _ -> t
    )
  | Mut t -> Mut (normalize t)
  | t -> t

let rec promote = function
  | Con (con, ts) ->
    let Def (tbs, t) | Abs (tbs, t) = Con.kind con
    in promote (reduce tbs t ts)
  | t -> t


(* Projections *)

let is_non = function Non -> true | _ -> false
let is_prim p = function Prim p' -> p = p' | _ -> false
let is_obj = function Obj _ -> true | _ -> false
let is_variant = function Variant _ -> true | _ -> false
let is_array = function Array _ -> true | _ -> false
let is_opt = function Opt _ -> true | _ -> false
let is_tup = function Tup _ -> true | _ -> false
let is_unit = function Tup [] -> true | _ -> false
let is_pair = function Tup [_; _] -> true | _ -> false
let is_func = function Func _ -> true | _ -> false
let is_async = function Async _ -> true | _ -> false
let is_mut = function Mut _ -> true | _ -> false
let is_typ = function Typ _ -> true | _ -> false
let is_con = function Con _ -> true | _ -> false

let invalid s = raise (Invalid_argument ("Type." ^ s))

let as_prim p = function Prim p' when p = p' -> () | _ -> invalid "as_prim"
let as_obj = function Obj (s, tfs) -> s, tfs | _ -> invalid "as_obj"
let as_array = function Array t -> t | _ -> invalid "as_array"
let as_opt = function Opt t -> t | _ -> invalid "as_opt"
let as_variant = function Variant fs -> fs | _ -> invalid "as_variant"
let as_tup = function Tup ts -> ts | _ -> invalid "as_tup"
let as_unit = function Tup [] -> () | _ -> invalid "as_unit"
let as_pair = function Tup [t1; t2] -> t1, t2 | _ -> invalid "as_pair"
let as_func = function Func (s, c, tbs, ts1, ts2) -> s, c, tbs, ts1, ts2 | _ -> invalid "as_func"
let as_async = function Async (t1, t2) -> (t1, t2) | _ -> invalid "as_async"
let as_mut = function Mut t -> t | _ -> invalid "as_mut"
let as_immut = function Mut t -> t | t -> t
let as_typ = function Typ c -> c | _ -> invalid "as_typ"
let as_con = function Con (c, ts) -> c,ts | _ -> invalid "as_con"

let as_seq t =
  match normalize t with
  | Tup ts -> ts
  | t -> [t]

let seq_of_tup t =
  match normalize t with
  | Tup ts -> ts
  | t -> invalid "seq_of_tup"

let arity t =
  match normalize t with
  | Tup ts -> List.length ts
  | t -> 1

let as_prim_sub p t = match promote t with
  | Prim p' when p = p' -> ()
  | Non -> ()
  | _ -> invalid "as_prim_sub"
let as_obj_sub ls t = match promote t with
  | Obj (s, tfs) -> s, tfs
  | Non -> Object, List.map (fun l -> {lab = l; typ = Non}) ls
  | _ -> invalid "as_obj_sub"
let as_variant_sub l t = match promote t with
  | Variant tfs -> tfs
  | Non -> [{lab = l; typ = Non}]
  | _ -> invalid "as_variant_sub"
let as_array_sub t = match promote t with
  | Array t -> t
  | Non -> Non
  | _ -> invalid "as_array_sub"
let as_opt_sub t = match promote t with
  | Opt t -> t
  | Non -> Non
  | _ -> invalid "as_opt_sub"
let as_tup_sub n t = match promote t with
  | Tup ts -> ts
  | Non -> Lib.List.make n Non
  | _ -> invalid "as_tup_sub"
let as_unit_sub t = match promote t with
  | Tup []
  | Non -> ()
  | _ -> invalid "as_unit_sub"
let as_pair_sub t = match promote t with
  | Tup [t1; t2] -> t1, t2
  | Non -> Non, Non
  | _ -> invalid "as_pair_sub"
let as_func_sub default_s default_arity t = match promote t with
  | Func (s, c, tbs, ts1, ts2) ->
    s, tbs, seq ts1, codom c (fun () -> Var((List.hd tbs).var, 0)) ts2
  | Non -> default_s, Lib.List.make default_arity {var = "X"; sort = Type; bound = Any}, Any, Non
  | _ -> invalid "as_func_sub"
let as_mono_func_sub t = match promote t with
  | Func (_, _, [], ts1, ts2) -> seq ts1, seq ts2
  | Non -> Any, Non
  | _ -> invalid "as_func_sub"
let as_async_sub default_scope t = match promote t with
  | Async (t1, t2) -> (t1, t2)
  | Non -> default_scope, Non (* TBR *)
  | _ -> invalid "as_async_sub"

let is_immutable_obj obj_type =
  let _, fields = as_obj_sub [] obj_type in
  List.for_all (fun f -> not (is_mut f.typ)) fields


let lookup_val_field l tfs =
  let is_lab = function {typ = Typ _; _} -> false | {lab; _} -> lab = l in
  match List.find_opt is_lab tfs with
  | Some tf -> tf.typ
  | None -> invalid "lookup_val_field"

let lookup_typ_field l tfs =
  let is_lab = function {typ = Typ _; lab} -> lab = l | _ -> false in
  match List.find_opt is_lab tfs with
  | Some {typ = Typ c; _} -> c
  | _ -> invalid "lookup_typ_field"


(* Span *)

let rec span = function
  | Var _ | Pre -> assert false
  | Con _ as t -> span (promote t)
  | Prim Null -> Some 1
  | Prim Bool -> Some 2
  | Prim (Nat | Int | Float | Text | Blob | Error | Principal) -> None
  | Prim (Nat8 | Int8 | Word8) -> Some 0x100
  | Prim (Nat16 | Int16 | Word16) -> Some 0x10000
  | Prim (Nat32 | Int32 | Word32 | Nat64 | Int64 | Word64 | Char) -> None  (* for all practical purposes *)
  | Obj _ | Tup _ | Async _ -> Some 1
  | Variant fs -> Some (List.length fs)
  | Array _ | Func _ | Any -> None
  | Opt _ -> Some 2
  | Mut t -> span t
  | Non -> Some 0
  | Typ _ -> Some 1

(* Avoiding local constructors *)

exception Unavoidable of con

let rec avoid' cons seen = function
  | (Prim _ | Var _ | Any | Non | Pre) as t -> t
  | Con (c, ts) ->
    if ConSet.mem c seen then raise (Unavoidable c) else
    if ConSet.mem c cons then
      match Con.kind c with
      | Abs _ -> raise (Unavoidable c)
      | Def (tbs, t) -> avoid' cons (ConSet.add c seen) (reduce tbs t ts)
    else
      (try Con (c, List.map (avoid' cons seen) ts) with Unavoidable d ->
        match Con.kind c with
        | Def (tbs, t) -> avoid' cons seen (reduce tbs t ts)
        | Abs _ -> raise (Unavoidable d)
      )
  | Array t -> Array (avoid' cons seen t)
  | Tup ts -> Tup (List.map (avoid' cons seen) ts)
  | Func (s, c, tbs, ts1, ts2) ->
    Func (
      s, c,
      List.map (avoid_bind cons seen) tbs,
      List.map (avoid' cons seen) ts1,
      List.map (avoid' cons seen) ts2
    )
  | Opt t -> Opt (avoid' cons seen t)
  | Async (t1, t2) -> Async (avoid' cons seen t1, avoid' cons seen t2)
  | Obj (s, fs) -> Obj (s, List.map (avoid_field cons seen) fs)
  | Variant fs -> Variant (List.map (avoid_field cons seen) fs)
  | Mut t -> Mut (avoid' cons seen t)
  | Typ c ->
    if ConSet.mem c cons then raise (Unavoidable c) else Typ c (* TBR *)

and avoid_bind cons seen tb=
  { tb with bound = avoid' cons seen tb.bound}

and avoid_field cons seen {lab; typ} =
  {lab; typ = avoid' cons seen typ}

and avoid_kind cons seen k =
  match k with
  | Def (tbs, t) ->
    Def (List.map (avoid_bind cons seen) tbs,
         avoid' cons seen t)
  | Abs (tbs, t) ->
    Abs (List.map (avoid_bind cons seen) tbs,
         avoid' cons seen t)

and avoid_cons cons1 cons2 =
  ConSet.iter (fun c -> Con.unsafe_set_kind c (avoid_kind cons1 ConSet.empty (Con.kind c))) cons2

let avoid cons t =
  if cons = ConSet.empty then t else
   avoid' cons ConSet.empty t


(* Collecting type constructors *)

let rec cons' t cs =
  match t with
  | Var _ ->  cs
  | (Prim _ | Any | Non | Pre ) -> cs
  | Con (c, ts) ->
    List.fold_right cons' ts (ConSet.add c cs)
  | (Opt t | Mut t | Array t) ->
    cons' t cs
  | Async (t1, t2) ->
    cons' t2 (cons' t1 cs)
  | Tup ts -> List.fold_right cons' ts cs
  | Func (s, c, tbs, ts1, ts2) ->
    let cs = List.fold_right cons_bind tbs  cs in
    let cs = List.fold_right cons' ts1 cs in
    List.fold_right cons' ts2 cs
  | (Obj (_, fs) | Variant fs) ->
    List.fold_right cons_field fs cs
  | Typ c -> ConSet.add c cs

and cons_bind tb cs =
  cons' tb.bound cs

and cons_field {lab; typ} cs =
  cons' typ cs

let cons_kind k =
  match k with
  | Def (tbs, t)
  | Abs (tbs, t) ->
    cons' t (List.fold_right cons_bind tbs ConSet.empty)

let cons t = cons' t ConSet.empty

(* Checking for concrete types *)

module S = Set.Make (struct type t = typ let compare = compare end)

(*
This check is a stop-gap measure until we have an IDL strategy that
allows polymorphic types, see #250. It is not what we desire for Motoko.
*)

let concrete t =
  let seen = ref S.empty in
  let rec go t =
    S.mem t !seen ||
    begin
      seen := S.add t !seen;
      match t with
      | Var _ | Pre -> assert false
      | Prim _ | Any | Non -> true
      | Con (c, ts) ->
        (match Con.kind c with
        | Abs _ -> false
        | Def (_, t) -> go (open_ ts t) (* TBR this may fail to terminate *)
        )
      | Array t | Opt t | Mut t -> go t
      | Async (t1, t2) -> go t2 (* t1 is a phantom type *)
      | Tup ts -> List.for_all go ts
      | Obj (_, fs) | Variant fs -> List.for_all (fun f -> go f.typ) fs
      | Func (s, c, tbs, ts1, ts2) ->
        let ts = open_binds tbs in
        List.for_all go (List.map (open_ ts) ts1) &&
        List.for_all go (List.map (open_ ts) ts2)
      | Typ c -> assert false (* TBR *)
    end
  in go t

let shared t =
  let seen = ref S.empty in
  let rec go t =
    S.mem t !seen ||
    begin
      seen := S.add t !seen;
      match t with
      | Var _ | Pre -> assert false
      | Prim Error -> false
      | Any | Non | Prim _ | Typ _ -> true
      | Async _ | Mut _ -> false
      | Con (c, ts) ->
        (match Con.kind c with
        | Abs _ -> false
        | Def (_, t) -> go (open_ ts t) (* TBR this may fail to terminate *)
        )
      | Array t | Opt t -> go t
      | Tup ts -> List.for_all go ts
      | Obj (s, fs) ->
        s = Actor ||
          (not (s = Actor) && List.for_all (fun f -> go f.typ) fs)
      | Variant fs -> List.for_all (fun f -> go f.typ) fs
      | Func (s, c, tbs, ts1, ts2) -> is_shared_sort s
    end
  in go t

(* Find the first unshared subexpression in a type *)
let find_unshared t =
  let seen = ref S.empty in
  let rec go t =
    if S.mem t !seen then None else
    begin
      seen := S.add t !seen;
      match t with
      | Var _ | Pre -> assert false
      | Prim Error -> Some t
      | Any | Non | Prim _ | Typ _ -> None
      | Async _ | Mut _ -> Some t
      | Con (c, ts) ->
        (match Con.kind c with
        | Abs _ -> None
        | Def (_, t) -> go (open_ ts t) (* TBR this may fail to terminate *)
        )
      | Array t | Opt t -> go t
      | Tup ts -> Lib.List.first_opt go ts
      | Obj (s, fs) ->
        if s = Actor
        then None
        else Lib.List.first_opt (fun f -> go f.typ) fs
      | Variant fs -> Lib.List.first_opt (fun f -> go f.typ) fs
      | Func (s, c, tbs, ts1, ts2) ->
        if is_shared_sort s
        then None
        else Some t
    end
  in go t

let is_shared_func t =
  match normalize t with
  | Func (Shared _, _, _, _, _) -> true
  | _ -> false

(* Forward declare
   TODO: haul string_of_typ before the lub/glb business, if possible *)
let str = ref (fun _ -> failwith "")

(* Equivalence & Subtyping *)

module SS = Set.Make (struct type t = typ * typ let compare = compare end)

let rel_list p rel eq xs1 xs2 =
  try List.for_all2 (p rel eq) xs1 xs2 with Invalid_argument _ -> false

let rec rel_typ rel eq t1 t2 =
  t1 == t2 || SS.mem (t1, t2) !rel || begin
  rel := SS.add (t1, t2) !rel;
  (*  Printf.printf "%s %s\n" (!str t1) (!str t2); *)
  match t1, t2 with
  | Pre, _ | _, Pre ->
    assert false
  | Any, Any ->
    true
  | _, Any when rel != eq ->
    true
  | Non, Non ->
    true
  | Non, _ when rel != eq ->
    true
  | Con (con1, ts1), Con (con2, ts2) ->
    (match Con.kind con1, Con.kind con2 with
    | Def (tbs, t), _ -> (* TBR this may fail to terminate *)
      rel_typ rel eq (open_ ts1 t) t2
    | _, Def (tbs, t) -> (* TBR this may fail to terminate *)
      rel_typ rel eq t1 (open_ ts2 t)
    | _ when Con.eq con1 con2 ->
      rel_list eq_typ rel eq ts1 ts2
    | Abs (tbs, t), _ when rel != eq ->
      rel_typ rel eq (open_ ts1 t) t2
    | _ ->
      false
    )
  | Con (con1, ts1), t2 ->
    (match Con.kind con1, t2 with
    | Def (tbs, t), _ -> (* TBR this may fail to terminate *)
      rel_typ rel eq (open_ ts1 t) t2
    | Abs (tbs, t), _ when rel != eq ->
      rel_typ rel eq (open_ ts1 t) t2
    | _ -> false
    )
  | t1, Con (con2, ts2) ->
    (match Con.kind con2 with
    | Def (tbs, t) -> (* TBR this may fail to terminate *)
      rel_typ rel eq t1 (open_ ts2 t)
    | _ -> false
    )
  | Prim p1, Prim p2 when p1 = p2 ->
    true
  | Prim p1, Prim p2 when rel != eq ->
    p1 = Nat && p2 = Int
  | Obj (s1, tfs1), Obj (s2, tfs2) ->
    s1 = s2 &&
    rel_fields rel eq tfs1 tfs2
  | Array t1', Array t2' ->
    rel_typ rel eq t1' t2'
  | Opt t1', Opt t2' ->
    rel_typ rel eq t1' t2'
  | Prim Null, Opt t2' when rel != eq ->
    true
  | Variant fs1, Variant fs2 ->
    rel_tags rel eq fs1 fs2
  | Tup ts1, Tup ts2 ->
    rel_list rel_typ rel eq ts1 ts2
  | Func (s1, c1, tbs1, t11, t12), Func (s2, c2, tbs2, t21, t22) ->
    s1 = s2 && c1 = c2 &&
    (match rel_binds rel eq tbs1 tbs2 with
    | Some ts ->
      rel_list rel_typ rel eq (List.map (open_ ts) t21) (List.map (open_ ts) t11) &&
      rel_list rel_typ rel eq (List.map (open_ ts) t12) (List.map (open_ ts) t22)
    | None -> false
    )
  | Async (t11, t12), Async (t21, t22) ->
    eq_typ rel eq t11 t21 &&
    rel_typ rel eq t12 t22
  | Mut t1', Mut t2' ->
    eq_typ rel eq t1' t2'
  | Typ c1, Typ c2 ->
    eq_con eq c1 c2
  | _, _ -> false
  end

and rel_fields rel eq tfs1 tfs2 =
  (* Assume that tfs1 and tfs2 are sorted. *)
  match tfs1, tfs2 with
  | [], [] ->
    true
  | _, [] when rel != eq ->
    true
  | tf1::tfs1', tf2::tfs2' ->
    (match compare_field tf1 tf2 with
    | 0 ->
      rel_typ rel eq tf1.typ tf2.typ &&
      rel_fields rel eq tfs1' tfs2'
    | -1 when rel != eq ->
      rel_fields rel eq tfs1' tfs2
    | _ -> false
    )
  | _, _ -> false

and rel_tags rel eq tfs1 tfs2 =
  (* Assume that tfs1 and tfs2 are sorted. *)
  match tfs1, tfs2 with
  | [], [] ->
    true
  | [], _ when rel != eq ->
    true
  | tf1::tfs1', tf2::tfs2' ->
    (match compare_field tf1 tf2 with
    | 0 ->
      rel_typ rel eq tf1.typ tf2.typ &&
      rel_tags rel eq tfs1' tfs2'
    | +1 when rel != eq ->
      rel_tags rel eq tfs1 tfs2'
    | _ -> false
    )
  | _, _ -> false

and rel_binds rel eq tbs1 tbs2 =
  let ts = open_binds tbs2 in
  if rel_list (rel_bind ts) rel eq tbs2 tbs1
  then Some ts
  else None

and rel_bind ts rel eq tb1 tb2 =
  rel_typ rel eq (open_ ts tb1.bound) (open_ ts tb2.bound)

and eq_typ rel eq t1 t2 = rel_typ eq eq t1 t2

and eq t1 t2 : bool =
  let eq = ref SS.empty in eq_typ eq eq t1 t2

and sub t1 t2 : bool =
  rel_typ (ref SS.empty) (ref SS.empty) t1 t2

and eq_kind' eq k1 k2 : bool =
  match k1, k2 with
  | Def (tbs1, t1), Def (tbs2, t2)
  | Abs (tbs1, t1), Abs (tbs2, t2) ->
    (match rel_binds eq eq tbs1 tbs2 with
    | Some ts -> eq_typ eq eq (open_ ts t1) (open_ ts t2)
    | None -> false
    )
  | _ -> false

and eq_con eq c1 c2 =
  match Con.kind c1, Con.kind c2 with
  | (Def (tbs1, t1)) as k1, (Def (tbs2, t2) as k2) ->
    eq_kind' eq k1 k2
  | Abs _, Abs _ ->
    Con.eq c1 c2
  | Def (tbs1, t1), Abs (tbs2, t2)
  | Abs (tbs2, t2), Def (tbs1, t1) ->
    (match rel_binds eq eq tbs1 tbs2 with
    | Some ts -> eq_typ eq eq (open_ ts t1) (Con (c2, ts))
    | None -> false
    )

let eq_kind k1 k2 : bool = eq_kind' (ref SS.empty) k1 k2

(* Compatibility *)

let compatible_list p co xs1 xs2 =
  try List.for_all2 (p co) xs1 xs2 with Invalid_argument _ -> false

let rec compatible_typ co t1 t2 =
  t1 == t2 || SS.mem (t1, t2) !co || begin
  co := SS.add (t1, t2) !co;
  match promote t1, promote t2 with
  | Pre, _ | _, Pre ->
    assert false
  | Any, Any ->
    true
  | Any, _ | _, Any ->
    false
  | Non, _ | _, Non ->
    true
  | Prim p1, Prim p2 when p1 = p2 ->
    true
  | Prim (Nat | Int), Prim (Nat | Int) ->
    true
  | Array t1', Array t2' ->
    compatible_typ co t1' t2'
  | Tup ts1, Tup ts2 ->
    compatible_list compatible_typ co ts1 ts2
  | Obj (s1, tfs1), Obj (s2, tfs2) ->
    s1 = s2 &&
    compatible_fields co tfs1 tfs2
  | Opt t1', Opt t2' ->
    compatible_typ co t1' t2'
  | Prim Null, Opt _ | Opt _, Prim Null  ->
    true
  | Variant tfs1, Variant tfs2 ->
    compatible_tags co tfs1 tfs2
  | Async (t11, t12), Async (t21, t22) ->
    compatible_typ co t11 t21 && (* TBR *)
    compatible_typ co t12 t22
  | Func _, Func _ ->
    true
  | Typ _, Typ _ ->
    true
  | Mut t1', Mut t2' ->
    compatible_typ co t1' t2'
  | _, _ ->
    false
  end

and compatible_fields co tfs1 tfs2 =
  (* Assume that tfs1 and tfs2 are sorted. *)
  match tfs1, tfs2 with
  | [], [] -> true
  | tf1::tfs1', tf2::tfs2' ->
    tf1.lab = tf2.lab && compatible_typ co tf1.typ tf2.typ &&
    compatible_fields co tfs1' tfs2'
  | _, _ -> false

and compatible_tags co tfs1 tfs2 =
  (* Assume that tfs1 and tfs2 are sorted. *)
  match tfs1, tfs2 with
  | [], _ | _, [] -> true
  | tf1::tfs1', tf2::tfs2' ->
    match compare_field tf1 tf2 with
    | -1 -> compatible_tags co tfs1' tfs2
    | +1 -> compatible_tags co tfs1 tfs2'
    | _ -> compatible_typ co tf1.typ tf2.typ && compatible_tags co tfs1' tfs2'

and compatible t1 t2 : bool =
  compatible_typ (ref SS.empty) t1 t2


let opaque t = compatible t Any


(* Inhabitance *)

let rec inhabited_typ co t =
  S.mem t !co || begin
  co := S.add t !co;
  match promote t with
  | Pre -> assert false
  | Non -> false
  | Any | Prim _ | Array _ | Opt _ | Async _ | Func _ | Typ _ -> true
  | Mut t' -> inhabited_typ co t'
  | Tup ts -> List.for_all (inhabited_typ co) ts
  | Obj (_, tfs) -> List.for_all (inhabited_field co) tfs
  | Variant tfs -> List.exists (inhabited_field co) tfs
  | Var _ -> true  (* TODO(rossberg): consider bound *)
  | Con (c, ts) ->
    match Con.kind c with
    | Def (tbs, t') -> (* TBR this may fail to terminate *)
      inhabited_typ co (open_ ts t')
    | Abs (tbs, t') ->
      inhabited_typ co t'
  end

and inhabited_field co tf = inhabited_typ co tf.typ

and inhabited t : bool = inhabited_typ (ref S.empty) t


(* Least upper bound and greatest lower bound *)

module M = Map.Make (struct type t = typ * typ let compare = compare end)

let rec lub' lubs glbs t1 t2 =
  if t1 == t2 then t1 else
  match M.find_opt (t1, t2) !lubs with
  | Some t -> t
  | _ ->
    match t1, t2 with
    | _, Pre
    | Pre, _ -> assert false
    | _, Any
    | Any, _ -> Any
    | _, Non -> t1
    | Non, _ -> t2
    | Prim Nat, (Prim Int as t)
    | (Prim Int as t), Prim Nat -> t
    | Opt t1', Opt t2' ->
      Opt (lub' lubs glbs t1' t2')
    | Prim Null, Opt t' -> t2
    | Opt t', Prim Null -> t1
    | Variant t1', Variant t2' ->
      Variant (lub_tags lubs glbs t1' t2')
    | Array t1', Array t2' ->
      Array (lub' lubs glbs t1' t2')
    | Tup ts1, Tup ts2 when List.(length ts1 = length ts2) ->
      Tup (List.map2 (lub' lubs glbs) ts1 ts2)
    | Obj (s1, tf1), Obj (s2, tf2) when s1 = s2 ->
      Obj (s1, lub_fields lubs glbs tf1 tf2)
    | Func (s1, c1, bs1, args1, res1), Func (s2, c2, bs2, args2, res2) when
        s1 = s2 && c1 = c2 && List.(length bs1 = length bs2) &&
        List.for_all2 (fun b1 b2 -> b1.sort = b2.sort) bs1 bs2 &&
        List.(length args1 = length args2 && length res1 = length res2) ->
      combine_func_parts s1 c1 bs1 args1 res1 bs2 args2 res2 lubs glbs glb' lub'
    | Async (t11, t12), Async (t21, t22) when eq t11 t21 ->
      Async (t11, lub' lubs glbs t12 t22)
    | Async _, Async _ -> Any
    | Con _, _
    | _, Con _ ->
      (* TODO(rossberg): fix handling of bounds *)
      combine_con_parts t1 t2 "lub" lubs (lub' lubs glbs)
    | Typ _, _
    | _, Typ _ -> assert false
    | _ when eq t1 t2 -> t1
    | _ -> Any

and lub_fields lubs glbs fs1 fs2 = match fs1, fs2 with
  | _, [] -> []
  | [], _ -> []
  | f1::fs1', f2::fs2' ->
    match compare_field f1 f2 with
    | -1 -> lub_fields lubs glbs fs1' fs2
    | +1 -> lub_fields lubs glbs fs1 fs2'
    | _ ->
      match f1.typ, f2.typ with
      | Typ _, Typ _ ->
        if eq f1.typ f2.typ then
          f1::lub_fields lubs glbs fs1' fs2'
        else
          lub_fields lubs glbs fs1' fs2'
      | Typ _, _
      | _, Typ _ -> assert false
      | _, _ ->
        {f1 with typ = lub' lubs glbs f1.typ f2.typ}::lub_fields lubs glbs fs1' fs2'

and lub_tags lubs glbs fs1 fs2 = match fs1, fs2 with
  | fs1, [] -> fs1
  | [], fs2 -> fs2
  | f1::fs1', f2::fs2' ->
    match compare_field f1 f2 with
    | -1 -> f1 :: lub_tags lubs glbs fs1' fs2
    | +1 -> f2 :: lub_tags lubs glbs fs1 fs2'
    | _ -> {f1 with typ = lub' lubs glbs f1.typ f2.typ} :: lub_tags lubs glbs fs1' fs2'

and glb' lubs glbs t1 t2 =
  if t1 == t2 then t1 else
  match M.find_opt (t1, t2) !glbs with
  | Some t -> t
  | _ ->
    match t1, t2 with
    | _, Pre
    | Pre, _ -> assert false
    | _, Any -> t1
    | Any, _ -> t2
    | _, Non
    | Non, _ -> Non
    | (Prim Nat as t), Prim Int
    | Prim Int, (Prim Nat as t) -> t
    | Opt t1', Opt t2' ->
      Opt (glb' lubs glbs t1' t2')
    | Variant t1', Variant t2' ->
      Variant (glb_tags lubs glbs t1' t2')
    | Prim Null, Opt _
    | Opt _, Prim Null -> Prim Null
    | Tup ts1, Tup ts2 when List.(length ts1 = length ts2) ->
      Tup (List.map2 (glb' lubs glbs) ts1 ts2)
    | Array t1', Array t2' ->
      Array (glb' lubs glbs t1' t2')
    | Obj (s1, tf1), Obj (s2, tf2) when s1 = s2 ->
      (match glb_fields lubs glbs tf1 tf2 with
      | None -> Non
      | Some fs -> Obj (s1, fs)
      )
    | Func (s1, c1, bs1, args1, res1), Func (s2, c2, bs2, args2, res2) when
        s1 = s2 && c1 = c2 && List.(length bs1 = length bs2) &&
        List.for_all2 (fun b1 b2 -> b1.sort = b2.sort) bs1 bs2 &&
        List.(length args1 = length args2 && length res1 = length res2) ->
      combine_func_parts s1 c1 bs1 args1 res1 bs2 args2 res2 lubs glbs lub' glb'
    | Async (t11, t12), Async (t21, t22) when eq t11 t21 ->
      Async (t11, glb' lubs glbs t12 t22)
    | Async _, Async _ -> Non
    | Con _, _
    | _, Con _ ->
      (* TODO(rossberg): fix handling of bounds *)
      combine_con_parts t1 t2 "glb" glbs (glb' lubs glbs)
    | Typ _, _
    | _, Typ _ -> assert false
    | _ when eq t1 t2 -> t1
    | _ -> Non

and glb_fields lubs glbs fs1 fs2 : field list option =
  let (+?) h t_opt = match t_opt with
    | None -> None
    | Some t -> Some (h::t)
  in
  match fs1, fs2 with
  | fs1, [] -> Some fs1
  | [], fs2 -> Some fs2
  | f1::fs1', f2::fs2' ->
    match compare_field f1 f2 with
    | -1 -> f1 +? glb_fields lubs glbs fs1' fs2
    | +1 -> f2 +? glb_fields lubs glbs fs1 fs2'
    | _ ->
      match f1.typ, f2.typ with
      | Typ _, Typ _ ->
        if eq f1.typ f2.typ
        then f1 +? glb_fields lubs glbs fs1' fs2'
        else None
      | Typ _, _
      | _, Typ _ -> assert false
      | _, _ ->
        {f1 with typ = glb' lubs glbs f1.typ f2.typ} +?
          glb_fields lubs glbs fs1' fs2'

and glb_tags lubs glbs fs1 fs2 = match fs1, fs2 with
  | fs1, [] -> []
  | [], fs2 -> []
  | f1::fs1', f2::fs2' ->
    match compare_field f1 f2 with
    | -1 -> glb_tags lubs glbs fs1' fs2
    | +1 -> glb_tags lubs glbs fs1 fs2'
    | _ ->
      {f1 with typ = glb' lubs glbs f1.typ f2.typ} ::
        glb_tags lubs glbs fs1' fs2'

and combine_func_parts s c bs1 args1 res1 bs2 args2 res2 lubs glbs contra co =
  let open List in
  let ts1 = open_binds bs1 in
  let op = map (open_ ts1) in
  let get_con = function | Con (c, []) -> c | _ -> assert false in
  let cs = map get_con ts1 in
  let cl = map (close cs) in
  let combine_binds =
    map2 (fun b1 b2 -> {b1 with bound = contra lubs glbs b1.bound b2.bound}) in
  Func (
    s, c, combine_binds bs1 bs2,
    cl (map2 (contra lubs glbs) (op args1) (op args2)),
    cl (map2 (co lubs glbs) (op res1) (op res2))
  )

and combine_con_parts t1 t2 naming re how =
  let s1, s2 = !str t1, !str t2 in
  if s1 = s2 then t1 else
  let c = Con.fresh (Printf.sprintf "@%s(%s, %s)" naming s1 s2) (Abs ([], Pre)) in
  let t = Con (c, []) in
  re := M.add (t2, t1) t (M.add (t1, t2) t !re);
  let inner = how (normalize t1) (normalize t2) in
  set_kind c (Def ([], inner));
  (* check for short-circuiting opportunities *)
  if eq inner t1
  then (re := M.add (t2, t1) t1 (M.add (t1, t2) t1 !re); t1)
  else if eq inner t2
  then (re := M.add (t2, t1) t2 (M.add (t1, t2) t2 !re); t2)
  else inner

let lub t1 t2 = lub' (ref M.empty) (ref M.empty) t1 t2
let glb t1 t2 = glb' (ref M.empty) (ref M.empty) t1 t2


(* Environments *)

module Env = Env.Make(String)


(* Scopes *)

let scope_var var = "$" ^ var
let default_scope_var = scope_var ""
let scope_bound = Any
let scope_bind = { var = default_scope_var; sort = Scope; bound = scope_bound }

(* Pretty printing *)

open Printf

let string_of_prim = function
  | Null -> "Null"
  | Bool -> "Bool"
  | Nat -> "Nat"
  | Nat8 -> "Nat8"
  | Nat16 -> "Nat16"
  | Nat32 -> "Nat32"
  | Nat64 -> "Nat64"
  | Int -> "Int"
  | Int8 -> "Int8"
  | Int16 -> "Int16"
  | Int32 -> "Int32"
  | Int64 -> "Int64"
  | Float -> "Float"
  | Word8 -> "Word8"
  | Word16 -> "Word16"
  | Word32 -> "Word32"
  | Word64 -> "Word64"
  | Char -> "Char"
  | Text -> "Text"
  | Blob -> "Blob"
  | Error -> "Error"
  | Principal -> "Principal"

let string_of_var (x, i) =
  if i = 0 then sprintf "%s" x else sprintf "%s.%d" x i

let string_of_obj_sort = function
  | Object -> ""
  | Module -> "module "
  | Actor -> "actor "

let string_of_func_sort = function
  | Local -> ""
  | Shared Write -> "shared "
  | Shared Query -> "shared query "

module MakePretty(Cfg : sig val show_stamps : bool end) =
  struct

let string_of_con' vs c =
  let s = Con.to_string' Cfg.show_stamps c in
  if List.mem (s, 0) vs then s ^ "/0" else s  (* TBR *)

let rec string_of_typ_nullary vs = function
  | Pre -> "???"
  | Any -> "Any"
  | Non -> "None"
  | Prim p -> string_of_prim p
  | Var (s, i) -> (try string_of_var (List.nth vs i) with _ -> sprintf "??? %s %i" s i)
  | Con (c, []) -> string_of_con' vs c
  | Con (c, ts) ->
    sprintf "%s<%s>" (string_of_con' vs c)
      (String.concat ", " (List.map (string_of_typ' vs) ts))
  | Tup ts ->
    sprintf "(%s%s)"
      (String.concat ", " (List.map (string_of_typ' vs) ts))
      (if List.length ts = 1 then "," else "")
  | Array (Mut t) ->
    sprintf "[var %s]" (string_of_typ_nullary vs t)
  | Array t ->
    sprintf "[%s]" (string_of_typ_nullary vs t)
  | Obj (Object, fs) ->
    sprintf "{%s}" (String.concat "; " (List.map (string_of_field vs) fs))
  | Variant [] -> "{#}"
  | Variant fs ->
    sprintf "{%s}" (String.concat "; " (List.map (string_of_tag vs) fs))
  | Typ c ->
    sprintf "= (type %s)" (string_of_kind (Con.kind c))
  | t -> sprintf "(%s)" (string_of_typ' vs t)

and string_of_dom vs ts =
  let dom = string_of_typ_nullary vs (seq ts) in
  match ts with
  | [Tup _] ->
     sprintf "(%s)" dom
  | _ -> dom

and string_of_cod vs ts =
  let cod = string_of_typ' vs (seq ts) in
  match ts with
  | [Tup _] -> sprintf "(%s)" cod
  | _ -> cod

and string_of_control_cod sugar c vs ts =
  match c, ts with
  (* sugar *)
  | Returns, [Async (_,t)] when sugar ->
    sprintf "async %s" (string_of_typ' vs t)
  | Promises, ts when sugar ->
    sprintf "async %s" (string_of_cod vs ts)
  (* explicit *)
  | (Returns | Promises), _ -> string_of_cod vs ts
  | Replies, _ -> sprintf "replies %s"  (string_of_cod vs ts)

and can_sugar t = match t with
  | Func(s, Promises, tbs, ts1, ts2)
  | Func((Shared _ as s), Returns, tbs, ts1, ([] as ts2))
  | Func(s, Returns, tbs, ts1, ([Async (Var(_, 0),_)] as ts2)) ->
    List.for_all (fun tb -> can_omit 0 tb.bound) tbs &&
    List.for_all (can_omit 0) ts1 &&
    List.for_all (can_omit 0) ts2
  | _ -> false

and can_omit n t =
  let rec go i t  =
    begin
      match t with
      | Var (_, j) -> i <> j
      | Pre -> assert false
      | Prim _ | Any | Non -> true
      | Con (c, ts) -> List.for_all (go i ) ts
      | Array t | Opt t | Mut t -> go i t
      | Async (Var (_, j), t2) when j = i && i <= n -> go i t2 (* t1 is a phantom type *)
      | Async (t1, t2) -> go i t1 && go i t2
      | Tup ts -> List.for_all (go i ) ts
      | Obj (_, fs) | Variant fs -> List.for_all (fun f -> go i f.typ) fs
      | Func (s, c, tbs, ts1, ts2) ->
        let i' = i+List.length tbs in
        List.for_all (fun tb -> (go i' tb.bound)) tbs &&
        List.for_all (go i') ts1  &&
        List.for_all (go i') ts2
      | Typ c -> true (* assuming type defs are closed *)
    end
  in go n t

and string_of_typ' vs t =
  match t with
  | Func (s, c, tbs, ts1, ts2) when can_sugar t ->
    let vs' = vars_of_binds vs tbs in
    let vs'', tbs' = List.tl vs', List.tl tbs in
    let vs'vs = vs' @ vs in
    begin
      match tbs with
      | [tb] ->
         sprintf "%s%s -> %s" (string_of_func_sort s)
          (string_of_dom (vs'vs) ts1)
          (string_of_control_cod true c (vs'vs) ts2)
      | _ ->
        sprintf "%s%s%s -> %s"
          (string_of_func_sort s) (string_of_binds (vs'vs) vs'' tbs')
          (string_of_dom (vs'vs) ts1) (string_of_control_cod true c (vs'vs) ts2)
    end
  | Func (s, c, [], ts1, ts2) ->
    sprintf "%s%s -> %s" (string_of_func_sort s)
      (string_of_dom vs ts1)
      (string_of_control_cod false c vs ts2)
  | Func (s, c, tbs, ts1, ts2) ->
    let vs' = vars_of_binds vs tbs in
    let vs'vs = vs' @ vs in
    sprintf "%s%s%s -> %s"
      (string_of_func_sort s) (string_of_binds (vs'vs) vs' tbs)
      (string_of_dom (vs'vs) ts1) (string_of_control_cod false c (vs'vs) ts2)
  | Opt t ->
    sprintf "?%s"  (string_of_typ_nullary vs t)
  | Async (t1, t2) ->
    (match t1 with
     | Var(_, n) when fst (List.nth vs n) = "" -> sprintf "async %s" (string_of_typ_nullary vs t2)
     | _ -> sprintf "async<%s> %s" (string_of_typ' vs t1) (string_of_typ_nullary vs t2))
  | Obj (s, fs) ->
    sprintf "%s%s" (string_of_obj_sort s) (string_of_typ_nullary vs (Obj (Object, fs)))
  | Typ c ->
    sprintf "= (%s,%s)" (Con.to_string c) (string_of_kind (Con.kind c))
  | Mut t ->
    sprintf "var %s" (string_of_typ' vs t)
  | t -> string_of_typ_nullary vs t

and string_of_field vs {lab; typ} =
  match typ with
  | Typ c ->
    let op, sbs, st = strings_of_kind (Con.kind c) in
    sprintf "type %s%s %s %s" lab sbs op st
  | Mut t' ->
    sprintf "var %s : %s" lab (string_of_typ' vs t')
  | _ ->
    sprintf "%s : %s" lab (string_of_typ' vs typ)

and string_of_tag vs {lab; typ} =
  match typ with
  | Tup [] -> sprintf "#%s" lab
  | _ -> sprintf "#%s : %s" lab (string_of_typ' vs typ)

and vars_of_binds vs bs =
  List.map (fun b -> name_of_var vs (b.var, 0)) bs

and name_of_var vs v =
  match vs with
  | [] -> v
  | v'::vs' -> name_of_var vs' (if v = v' then (fst v, snd v + 1) else v)

and string_of_bind vs v {bound; _} =
  string_of_var v ^
  (if bound = Any then "" else " <: " ^ string_of_typ' vs bound)

and string_of_binds vs vs' = function
  | [] -> ""
  | tbs -> "<" ^ String.concat ", " (List.map2 (string_of_bind vs) vs' tbs) ^ ">"


and strings_of_kind k =
  let op, tbs, t =
    match k with
    | Def (tbs, t) -> "=", tbs, t
    | Abs (tbs, t) -> "<:", tbs, t
  in
  let vs = vars_of_binds [] tbs in
  op, string_of_binds vs vs tbs, string_of_typ' vs t

and string_of_kind k =
  let op, sbs, st = strings_of_kind k in
  sprintf "%s %s%s" op sbs st

let string_of_con : con -> string = string_of_con' []
let string_of_typ : typ -> string = string_of_typ' []
let _ = str := string_of_typ

let rec string_of_typ_expand t =
  let s = string_of_typ t in
  match t with
  | Con (c, ts) ->
    (match Con.kind c with
    | Abs _ -> s
    | Def _ ->
      match normalize t with
      | Prim _ | Any | Non -> s
      | t' -> s ^ " = " ^ string_of_typ_expand t'
    )
  | _ -> s
end

module type Pretty = sig
  val string_of_con : con -> string
  val string_of_typ : typ -> string
  val string_of_kind : kind -> string
  val strings_of_kind : kind -> string * string * string
  val string_of_typ_expand : typ -> string
end


include MakePretty(struct let show_stamps = true end)
