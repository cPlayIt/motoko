
(* Identifiers *)

type id = string Source.phrase

(* Types *)

type prim =
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
  | Float32
  | Float64
  | Bool
  | Text
  | Null
  | Reserved
  | Empty
        
type func_mode = func_mode' Source.phrase
and func_mode' = Oneway | Query

type field_label = field_label' Source.phrase
and field_label' = Id of Lib.Uint32.t | Named of string | Unnamed of Lib.Uint32.t

type typ = typ' Source.phrase
and typ' =
  | PrimT of prim                                (* primitive *)
  | VarT of id                                    (* type name *)
  | FuncT of func_mode list * typ list * typ list   (* function *)
  | OptT of typ   (* option *)
  | VecT of typ   (* vector *)
  | RecordT of typ_field list  (* record *)
  | VariantT of typ_field list (* variant *)
  | ServT of typ_meth list (* service reference *)
  | PrincipalT
  | PreT   (* pre-type *)

and typ_field = typ_field' Source.phrase
and typ_field' = { label: field_label; typ : typ }

and typ_meth = typ_meth' Source.phrase
and typ_meth' = {var : id; meth : typ}

(* Declarations *)

and dec = dec' Source.phrase
and dec' =
  | TypD of id * typ             (* type *)
  | ImportD of string * string ref  (* import *)

(* Program *)

type prog = (prog', string) Source.annotated_phrase
and prog' = { decs : dec list; actor : typ option }

