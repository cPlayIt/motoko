open Mo_types
open Mo_values

type id = string

(* Literals *)

type lit =
  | NullLit
  | BoolLit of bool
  | NatLit of Value.Nat.t
  | Nat8Lit of Value.Nat8.t
  | Nat16Lit of Value.Nat16.t
  | Nat32Lit of Value.Nat32.t
  | Nat64Lit of Value.Nat64.t
  | IntLit of Value.Int.t
  | Int8Lit of Value.Int_8.t
  | Int16Lit of Value.Int_16.t
  | Int32Lit of Value.Int_32.t
  | Int64Lit of Value.Int_64.t
  | Word8Lit of Value.Word8.t
  | Word16Lit of Value.Word16.t
  | Word32Lit of Value.Word32.t
  | Word64Lit of Value.Word64.t
  | FloatLit of Value.Float.t
  | CharLit of Value.unicode
  | TextLit of string
  | BlobLit of string

(* Patterns *)

type 'a phrase = ('a, Note.t) Source.annotated_phrase

type typ_bind' = {con : Type.con; sort: Type.bind_sort; bound : Type.typ}
type typ_bind = typ_bind' Source.phrase

type unop = Operator.unop
type binop = Operator.binop
type relop = Operator.relop

type mut = Const | Var

type pat = (pat', Type.typ) Source.annotated_phrase
and pat' =
  | WildP                                      (* wildcard *)
  | VarP of id                                 (* variable *)
  | LitP of lit                                (* literal *)
  | TupP of pat list                           (* tuple *)
  | ObjP of pat_field list                     (* object *)
  | OptP of pat                                (* option *)
  | TagP of id * pat                           (* variant *)
  | AltP of pat * pat                          (* disjunctive *)

and pat_field = pat_field' Source.phrase
and pat_field' = {name : Type.lab; pat : pat}

(* Like id, but with a type attached *)
type arg = (string, Type.typ) Source.annotated_phrase

(* Expressions *)

type exp = exp' phrase
and exp' =
  | PrimE of (prim * exp list)                 (* primitive *)
  | VarE of id                                 (* variable *)
  | LitE of lit                                (* literal *)
  | AssignE of lexp * exp                      (* assignment *)
  | BlockE of (dec list * exp)                 (* block *)
  | IfE of exp * exp * exp                     (* conditional *)
  | SwitchE of exp * case list                 (* switch *)
  | LoopE of exp                               (* do-while loop *)
  | LabelE of id * Type.typ * exp              (* label *)
  | AsyncE of typ_bind * exp * Type.typ        (* async *)
  | DeclareE of id * Type.typ * exp            (* local promise *)
  | DefineE of id * mut * exp                  (* promise fulfillment *)
  | FuncE of                                   (* function *)
      string * Type.func_sort * Type.control * typ_bind list * arg list * Type.typ list * exp
  | SelfCallE of Type.typ list * exp * exp * exp (* essentially ICCallPrim (FuncE shared…) *)
  | ActorE of dec list * field list * Type.typ (* actor *)
  | NewObjE of Type.obj_sort * field list * Type.typ  (* make an object *)
  | TryE of exp * case list                    (* try/catch *)

and field = (field', Type.typ) Source.annotated_phrase
and field' = {name : Type.lab; var : id} (* the var is by reference, not by value *)

and case = case' Source.phrase
and case' = {pat : pat; exp : exp}

and lexp = (lexp', Type.typ) Source.annotated_phrase
and lexp' =
  | VarLE of id                                (* variable *)
  | IdxLE of exp * exp                         (* array indexing *)
  | DotLE of exp * Type.lab                    (* object projection *)


(* In the IR, a prim is any AST node that has expr subexpressions, but they are
all call-by-value. Many passes can treat them uniformly, so they are unified
using the PrimE node. *)
and prim =
  | CallPrim of Type.typ list         (* function call *)
  | UnPrim of Type.typ * unop         (* unary operator *)
  | BinPrim of Type.typ * binop       (* binary operator *)
  | RelPrim of Type.typ * relop       (* relational operator *)
  | TupPrim                           (* the tuple constructor *)
  | ProjPrim of int                   (* tuple projection *)
  | OptPrim                           (* option injection *)
  | TagPrim of id                     (* variant injection *)
  | DotPrim of Type.lab               (* object projection *)
  | ActorDotPrim of Type.lab          (* actor field access *)
  | ArrayPrim of mut * Type.typ       (* array constructor *)
  | IdxPrim                           (* array indexing *)
  | BreakPrim of id                   (* break *)
  | RetPrim                           (* return *)
  | AwaitPrim                         (* await *)
  | AssertPrim                        (* assertion *)
  | ThrowPrim                         (* throw *)
  | ShowPrim of Type.typ              (* debug show *)
  | NumConvPrim of Type.prim * Type.prim
  | CastPrim of Type.typ * Type.typ   (* representationally a noop *)
  | ActorOfIdBlob of Type.typ
  | BlobOfIcUrl                       (* traps on syntax or checksum failure *)
  | SelfRef of Type.typ               (* returns the self actor ref *)
  | OtherPrim of string               (* Other primitive operation, no custom typing rule *)
  (* backend stuff *)
  | CPSAwait
  | CPSAsync of Type.typ
  | ICReplyPrim of Type.typ list
  | ICRejectPrim
  | ICCallerPrim
  | ICCallPrim


(* Declarations *)

and dec = dec' Source.phrase
and dec' =
  | LetD of pat * exp                          (* immutable *)
  | VarD of id * Type.typ * exp                           (* mutable *)

(* Literals *)

let string_of_lit = function
  | BoolLit false -> "false"
  | BoolLit true  ->  "true"
  | IntLit n
  | NatLit n      -> Value.Int.to_pretty_string n
  | Int8Lit n     -> Value.Int_8.to_pretty_string n
  | Int16Lit n    -> Value.Int_16.to_pretty_string n
  | Int32Lit n    -> Value.Int_32.to_pretty_string n
  | Int64Lit n    -> Value.Int_64.to_pretty_string n
  | Nat8Lit n     -> Value.Nat8.to_pretty_string n
  | Nat16Lit n    -> Value.Nat16.to_pretty_string n
  | Nat32Lit n    -> Value.Nat32.to_pretty_string n
  | Nat64Lit n    -> Value.Nat64.to_pretty_string n
  | Word8Lit n    -> Value.Word8.to_pretty_string n
  | Word16Lit n   -> Value.Word16.to_pretty_string n
  | Word32Lit n   -> Value.Word32.to_pretty_string n
  | Word64Lit n   -> Value.Word64.to_pretty_string n
  | CharLit c     -> string_of_int c
  | NullLit       -> "null"
  | TextLit t     -> t
  | BlobLit b     -> Printf.sprintf "%s" b
  | FloatLit f    -> Value.Float.to_pretty_string f

(* Flavor *)

(*
We have a bunch of flavors of the IR, where some constructors are not
allowed in some flavors. In an ideal world, we would have different IRs for
that (or maybe GADTs). But for now we simply track that on the value level. The
main purpose of tracking that is to inform `Check_ir` about the invariants that
should hold.
*)

type flavor = {
  has_async_typ : bool; (* AsyncT *)
  has_await : bool; (* AwaitE and AsyncE *)
  has_show : bool; (* ShowE *)
  serialized : bool; (* Shared function arguments are serialized *)
}

let full_flavor : flavor = {
  has_await = true;
  has_async_typ = true;
  has_show = true;
  serialized = false;
}



(* Program *)

type prog = (dec list * exp) * flavor


(* object pattern helpers *)

let pats_of_obj_pat pfs = List.map (fun {Source.it={name; pat}; _} -> pat) pfs

let map_obj_pat f pfs =
  List.map (fun ({Source.it={name; pat}; _} as pf) -> {pf with Source.it={name; pat=f pat}}) pfs

let replace_obj_pat pfs pats =
  List.map2 (fun ({Source.it={name; pat=_}; _} as pf) pat -> {pf with Source.it={name; pat}}) pfs pats
