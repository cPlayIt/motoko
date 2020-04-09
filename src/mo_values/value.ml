open Printf


(* Environments *)

module Env = Env.Make(String)


(* Numeric Representations *)

let rec add_digits buf s i j k =
  if i < j then begin
    if k = 0 then Buffer.add_char buf '_';
    Buffer.add_char buf s.[i];
    add_digits buf s (i + 1) j ((k + 2) mod 3)
  end

let is_digit c = '0' <= c && c <= '9'
let isnt_digit c = not (is_digit c)

let group_num s =
  let len = String.length s in
  let mant = Lib.Option.get (Lib.String.find_from_opt is_digit s 0) len in
  let point = Lib.Option.get (Lib.String.find_from_opt isnt_digit s mant) len in
  let frac = Lib.Option.get (Lib.String.find_from_opt is_digit s point) len in
  let exp = Lib.Option.get (Lib.String.find_from_opt isnt_digit s frac) len in
  let buf = Buffer.create (len*4/3) in
  Buffer.add_substring buf s 0 mant;
  add_digits buf s mant point ((point - mant) mod 3 + 3);
  Buffer.add_substring buf s point (frac - point);
  add_digits buf s frac exp 3;
  Buffer.add_substring buf s exp (len - exp);
  Buffer.contents buf

(* Represent n-bit integers using k-bit (n<=k) integers by shifting left/right by k-n bits *)
module SubRep (Rep : Wasm.Int.RepType) (Width : sig val bitwidth : int end) :
  Wasm.Int.RepType with type t = Rep.t =
struct
  let _ = assert (Width.bitwidth < Rep.bitwidth)

  type t = Rep.t

  let bitwidth = Width.bitwidth
  let bitdiff = Rep.bitwidth - Width.bitwidth
  let inj r  = Rep.shift_left r bitdiff
  let proj i = Rep.shift_right i bitdiff

  let zero = inj Rep.zero
  let one = inj Rep.one
  let minus_one = inj Rep.minus_one
  let max_int = inj (Rep.shift_right_logical Rep.max_int bitdiff)
  let min_int = inj (Rep.shift_right_logical Rep.min_int bitdiff)
  let neg i = inj (Rep.neg (proj i))
  let add i j = inj (Rep.add (proj i) (proj j))
  let sub i j = inj (Rep.sub (proj i) (proj j))
  let mul i j = inj (Rep.mul (proj i) (proj j))
  let div i j = inj (Rep.div (proj i) (proj j))
  let rem i j = inj (Rep.rem (proj i) (proj j))
  let logand = Rep.logand
  let logor = Rep.logor
  let lognot i = inj (Rep.lognot (proj i))
  let logxor i j = inj (Rep.logxor (proj i) (proj j))
  let shift_left i j = Rep.shift_left i j
  let shift_right i j = let res = Rep.shift_right i j in inj (proj res)
  let shift_right_logical i j = let res = Rep.shift_right_logical i j in inj (proj res)
  let of_int i = inj (Rep.of_int i)
  let to_int i = Rep.to_int (proj i)
  let to_string i = group_num (Rep.to_string (proj i))
end

module type WordType =
sig
  include Wasm.Int.S
  val neg : t -> t
  val not : t -> t
  val pow : t -> t -> t
  val to_string : t -> string
  val to_pretty_string : t -> string
end

module MakeWord
  (WasmInt : Wasm.Int.S) (ToInt : sig val to_int : WasmInt.t -> int end) =
struct
  include WasmInt
  let neg w = sub zero w
  let not w = xor w (of_int_s (-1))
  let one = of_int_u 1
  let rec pow x y =
    if y = zero then
      one
    else if and_ y one = zero then
      pow (mul x x) (shr_u y one)
    else
      mul x (pow x (sub y one))

  let base = of_int_u 16
  let digs =
    [|"0"; "1"; "2"; "3"; "4"; "5"; "6"; "7";
      "8"; "9"; "A"; "B"; "C"; "D"; "E"; "F"|]
  let rec to_pretty_string w = if w = zero then "0" else to_pretty_string' w 0 ""
  and to_pretty_string' w i s =
    if w = zero then s else
    let dig = digs.(ToInt.to_int (WasmInt.rem_u w base)) in
    let s' = dig ^ (if i = 4 then "_" else "") ^ s in
    to_pretty_string' (WasmInt.div_u w base) (i mod 4 + 1) s'
  let to_string = to_pretty_string
end

module Int32Rep = struct include Int32 let bitwidth = 32 end
module Int16Rep = SubRep (Int32Rep) (struct let bitwidth = 16 end)
module Int8Rep = SubRep (Int32Rep) (struct let bitwidth = 8 end)

module Word8 = MakeWord (Wasm.Int.Make (Int8Rep)) (Int8Rep)
module Word16 = MakeWord (Wasm.Int.Make (Int16Rep)) (Int16Rep)
module Word32 = MakeWord (Wasm.I32) (Int32)
module Word64 = MakeWord (Wasm.I64) (Int64)

module type FloatType =
sig
  include Wasm.Float.S
  val pow : t -> t -> t
  val to_pretty_string : t -> string
end

module MakeFloat(WasmFloat : Wasm.Float.S) =
struct
  include WasmFloat
  let pow x y = of_float (to_float x ** to_float y)
  let to_pretty_string w = group_num (WasmFloat.to_string w)
  let to_string = to_pretty_string
end

module Float = MakeFloat(Wasm.F64)


module type NumType =
sig
  type t
  val zero : t
  val abs : t -> t
  val neg : t -> t
  val add : t -> t -> t
  val sub : t -> t -> t
  val mul : t -> t -> t
  val div : t -> t -> t
  val rem : t -> t -> t
  val pow : t -> t -> t
  val eq : t -> t -> bool
  val ne : t -> t -> bool
  val lt : t -> t -> bool
  val gt : t -> t -> bool
  val le : t -> t -> bool
  val ge : t -> t -> bool
  val compare : t -> t -> int
  val to_int : t -> int
  val of_int : int -> t
  val to_big_int : t -> Big_int.big_int
  val of_big_int : Big_int.big_int -> t
  val of_string : string -> t
  val to_string : t -> string
  val to_pretty_string : t -> string
end

module Int : NumType with type t = Big_int.big_int =
struct
  open Big_int
  type t = big_int
  let zero = zero_big_int
  let sub = sub_big_int
  let abs = abs_big_int
  let neg = minus_big_int
  let add = add_big_int
  let mul = mult_big_int
  let div a b =
    let q, m = quomod_big_int a b in
    if sign_big_int m * sign_big_int a >= 0 then q
    else if sign_big_int q = 1 then pred_big_int q else succ_big_int q
  let rem a b =
    let q, m = quomod_big_int a b in
    let sign_m = sign_big_int m in
    if sign_m * sign_big_int a >= 0 then m
    else
    let abs_b = abs_big_int b in
    if sign_m = 1 then sub_big_int m abs_b else add_big_int m abs_b
  let eq = eq_big_int
  let ne x y = not (eq x y)
  let lt = lt_big_int
  let gt = gt_big_int
  let le = le_big_int
  let ge = ge_big_int
  let compare = compare_big_int
  let to_int = int_of_big_int
  let of_int = big_int_of_int
  let of_big_int i = i
  let to_big_int i = i
  let to_pretty_string i = group_num (string_of_big_int i)
  let to_string = to_pretty_string
  let of_string s =
    big_int_of_string (String.concat "" (String.split_on_char '_' s))

  let max_int = big_int_of_int max_int

  let pow x y =
    if gt y max_int
    then raise (Invalid_argument "Int.pow")
    else power_big_int_positive_int x (int_of_big_int y)
end

module Nat : NumType with type t = Big_int.big_int =
struct
  include Int
  let sub x y =
    let z = Int.sub x y in
    if ge z zero then z else raise (Invalid_argument "Nat.sub")
end

module Ranged (Rep : NumType) (Range : sig val is_range : Rep.t -> bool end) : NumType =
struct
  let check i =
    if Range.is_range i then i
    else raise (Invalid_argument "value out of bounds")

  include Rep
  let neg a = let res = Rep.neg a in check res
  let abs a = let res = Rep.abs a in check res
  let add a b = let res = Rep.add a b in check res
  let sub a b = let res = Rep.sub a b in check res
  let mul a b = let res = Rep.mul a b in check res
  let div a b = let res = Rep.div a b in check res
  let pow a b = let res = Rep.pow a b in check res
  let of_int i = let res = Rep.of_int i in check res
  let of_big_int i = let res = Rep.of_big_int i in check res
  let of_string s = let res = Rep.of_string s in check res
end

module NatRange (Limit : sig val upper : Big_int.big_int end) =
struct
  open Big_int
  let is_range n = ge_big_int n zero_big_int && lt_big_int n Limit.upper
end

module Nat8 = Ranged (Nat) (NatRange (struct let upper = Big_int.big_int_of_int 0x100 end))
module Nat16 = Ranged (Nat) (NatRange (struct let upper = Big_int.big_int_of_int 0x1_0000 end))
module Nat32 = Ranged (Nat) (NatRange (struct let upper = Big_int.big_int_of_int 0x1_0000_0000 end))
module Nat64 = Ranged (Nat) (NatRange (struct let upper = Big_int.power_int_positive_int 2 64 end))

module IntRange (Limit : sig val upper : Big_int.big_int end) =
struct
  open Big_int
  let is_range n = ge_big_int n (minus_big_int Limit.upper) && lt_big_int n Limit.upper
end

module Int_8 = Ranged (Int) (IntRange (struct let upper = Big_int.big_int_of_int 0x80 end))
module Int_16 = Ranged (Int) (IntRange (struct let upper = Big_int.big_int_of_int 0x8000 end))
module Int_32 = Ranged (Int) (IntRange (struct let upper = Big_int.big_int_of_int 0x8000_0000 end))
module Int_64 = Ranged (Int) (IntRange (struct let upper = Big_int.power_int_positive_int 2 63 end))

(* Types *)

type unicode = int

type actor_id = string

type context = value

and func =
  context -> value -> value cont -> unit

and value =
  | Null
  | Bool of bool
  | Int of Int.t
  | Int8 of Int_8.t
  | Int16 of Int_16.t
  | Int32 of Int_32.t
  | Int64 of Int_64.t
  | Nat8 of Nat8.t
  | Nat16 of Nat16.t
  | Nat32 of Nat32.t
  | Nat64 of Nat64.t
  | Word8 of Word8.t
  | Word16 of Word16.t
  | Word32 of Word32.t
  | Word64 of Word64.t
  | Float of Float.t
  | Char of unicode
  | Text of string
  | Tup of value list
  | Opt of value
  | Variant of string * value
  | Array of value array
  | Obj of value Env.t
  | Func of Call_conv.t * func
  | Async of async
  | Mut of value ref
  | Iter of value Seq.t ref (* internal to {b.bytes(), t.chars()} iterator *)

and res = Ok of value | Error of value
and async = {result : res Lib.Promise.t ; mutable waiters : (value cont * value cont) list}

and def = value Lib.Promise.t
and 'a cont = 'a -> unit


(* Shorthands *)

let unit = Tup []

let local_func n m f = Func (Call_conv.local_cc n m, f)
let message_func s n f = Func (Call_conv.message_cc s n, f)
let async_func s n m f = Func (Call_conv.async_cc s n m, f)
let replies_func s n m f = Func (Call_conv.replies_cc s n m, f)


(* Projections *)

let invalid s = raise (Invalid_argument ("Value." ^ s))

let as_null = function Null -> () | _ -> invalid "as_null"
let as_bool = function Bool b -> b | _ -> invalid "as_bool"
let as_int = function Int n -> n | _ -> invalid "as_int"
let as_int8 = function Int8 w -> w | _ -> invalid "as_int8"
let as_int16 = function Int16 w -> w | _ -> invalid "as_int16"
let as_int32 = function Int32 w -> w | _ -> invalid "as_int32"
let as_int64 = function Int64 w -> w | _ -> invalid "as_int64"
let as_nat8 = function Nat8 w -> w | _ -> invalid "as_nat8"
let as_nat16 = function Nat16 w -> w | _ -> invalid "as_nat16"
let as_nat32 = function Nat32 w -> w | _ -> invalid "as_nat32"
let as_nat64 = function Nat64 w -> w | _ -> invalid "as_nat64"
let as_word8 = function Word8 w -> w | _ -> invalid "as_word8"
let as_word16 = function Word16 w -> w | _ -> invalid "as_word16"
let as_word32 = function Word32 w -> w | _ -> invalid "as_word32"
let as_word64 = function Word64 w -> w | _ -> invalid "as_word64"
let as_float = function Float f -> f | _ -> invalid "as_float"
let as_char = function Char c -> c | _ -> invalid "as_char"
let as_text = function Text s -> s | _ -> invalid "as_text"
let as_iter = function Iter i -> i | _ -> invalid "as_iter"
let as_array = function Array a -> a | _ -> invalid "as_array"
let as_opt = function Opt v -> v | _ -> invalid "as_opt"
let as_variant = function Variant (i, v) -> i, v | _ -> invalid "as_variant"
let as_tup = function Tup vs -> vs | _ -> invalid "as_tup"
let as_unit = function Tup [] -> () | _ -> invalid "as_unit"
let as_pair = function Tup [v1; v2] -> v1, v2 | _ -> invalid "as_pair"
let as_obj = function Obj ve -> ve | _ -> invalid "as_obj"
let as_func = function Func (cc, f) -> cc, f | _ -> invalid "as_func"
let as_async = function Async a -> a | _ -> invalid "as_async"
let as_mut = function Mut r -> r | _ -> invalid "as_mut"


(* Ordering *)

let generic_compare = compare

let rec compare x1 x2 =
  if x1 == x2 then 0 else
  match x1, x2 with
  | Int n1, Int n2 -> Int.compare n1 n2
  | Int8 n1, Int8 n2 -> Int_8.compare n1 n2
  | Int16 n1, Int16 n2 -> Int_16.compare n1 n2
  | Int32 n1, Int32 n2 -> Int_32.compare n1 n2
  | Int64 n1, Int64 n2 -> Int_64.compare n1 n2
  | Nat8 n1, Nat8 n2 -> Nat8.compare n1 n2
  | Nat16 n1, Nat16 n2 -> Nat16.compare n1 n2
  | Nat32 n1, Nat32 n2 -> Nat32.compare n1 n2
  | Nat64 n1, Nat64 n2 -> Nat64.compare n1 n2
  | Opt v1, Opt v2 -> compare v1 v2
  | Tup vs1, Tup vs2 -> Lib.List.compare compare vs1 vs2
  | Array a1, Array a2 -> Lib.Array.compare compare a1 a2
  | Obj fs1, Obj fs2 -> Env.compare compare fs1 fs2
  | Variant (l1, v1), Variant (l2, v2) ->
    (match String.compare l1 l2 with
    | 0 -> compare v1 v2
    | i -> i
    )
  | Mut r1, Mut r2 -> compare !r1 !r2
  | Async _, Async _ -> raise (Invalid_argument "Value.compare")
  | _ -> generic_compare x1 x2

let equal x1 x2 = compare x1 x2 = 0


(* (Pseudo)-Identities (for caller and self) *)

let next_id = ref 0

let fresh_id() =
  let id = Printf.sprintf "ID:%i" (!next_id) in
  next_id := !next_id + 1;
  id

let top_id = fresh_id ()

(* Pretty Printing *)

let add_unicode buf = function
  | 0x09 -> Buffer.add_string buf "\\t"
  | 0x0a -> Buffer.add_string buf "\\n"
  | 0x22 -> Buffer.add_string buf "\\\""
  | 0x27 -> Buffer.add_string buf "\\\'"
  | 0x5c -> Buffer.add_string buf "\\\\"
  | c when 0x20 <= c && c < 0x7f -> Buffer.add_char buf (Char.chr c)
  | c -> Printf.bprintf buf "\\u{%02x}" c

let string_of_string lsep s rsep =
  let buf = Buffer.create 256 in
  Buffer.add_char buf lsep;
  List.iter (add_unicode buf) s;
  Buffer.add_char buf rsep;
  Buffer.contents buf

let pos_sign b = if b then "+" else ""

let rec string_of_val_nullary d = function
  | Null -> "null"
  | Bool b -> if b then "true" else "false"
  | Int n when Int.(ge n zero) -> Int.to_pretty_string n
  | Int8 n when Int_8.(n = zero) -> Int_8.to_pretty_string n
  | Int16 n when Int_16.(n = zero) -> Int_16.to_pretty_string n
  | Int32 n when Int_32.(n = zero) -> Int_32.to_pretty_string n
  | Int64 n when Int_64.(n = zero) -> Int_64.to_pretty_string n
  | Nat8 n -> Nat8.to_pretty_string n
  | Nat16 n -> Nat16.to_pretty_string n
  | Nat32 n -> Nat32.to_pretty_string n
  | Nat64 n -> Nat64.to_pretty_string n
  | Word8 w -> "0x" ^ Word8.to_pretty_string w
  | Word16 w -> "0x" ^ Word16.to_pretty_string w
  | Word32 w -> "0x" ^ Word32.to_pretty_string w
  | Word64 w -> "0x" ^ Word64.to_pretty_string w
  | Float f -> Float.to_pretty_string f
  | Char c -> string_of_string '\'' [c] '\''
  | Text t -> string_of_string '\"' (Wasm.Utf8.decode t) '\"'
  | Tup vs ->
    sprintf "(%s%s)"
      (String.concat ", " (List.map (string_of_val d) vs))
      (if List.length vs = 1 then "," else "")
  | Obj ve ->
    if d = 0 then "{...}" else
    sprintf "{%s}" (String.concat "; " (List.map (fun (x, v) ->
      sprintf "%s = %s" x (string_of_val (d - 1) v)) (Env.bindings ve)))
  | Array a ->
    sprintf "[%s]" (String.concat ", "
      (List.map (string_of_val d) (Array.to_list a)))
  | Func (_, _) -> "func"
  | v -> "(" ^ string_of_val d v ^ ")"

and string_of_val d = function
  | Int i -> Int.to_pretty_string i
  | Int8 i -> Int_8.(pos_sign (gt i zero) ^ to_pretty_string i)
  | Int16 i -> Int_16.(pos_sign (gt i zero) ^ to_pretty_string i)
  | Int32 i -> Int_32.(pos_sign (gt i zero) ^ to_pretty_string i)
  | Int64 i -> Int_64.(pos_sign (gt i zero) ^ to_pretty_string i)
  | Opt v -> sprintf "?%s" (string_of_val_nullary d v)
  | Variant (l, Tup []) -> sprintf "#%s" l
  | Variant (l, Tup vs) -> sprintf "#%s%s" l (string_of_val d (Tup vs))
  | Variant (l, v) -> sprintf "#%s(%s)" l (string_of_val d v)
  | Async {result; waiters = []} ->
    sprintf "async %s" (string_of_res d result)
  | Async {result; waiters} ->
    sprintf "async[%d] %s"
      (List.length waiters) (string_of_res d result)
  | Mut r -> sprintf "%s" (string_of_val d !r)
  | v -> string_of_val_nullary d v

and string_of_res d result =
  match Lib.Promise.value_opt result with
  | Some (Error v)-> sprintf "Error %s" (string_of_val_nullary d v)
  | Some (Ok v) -> string_of_val_nullary d v
  | None -> "_"

and string_of_def d def =
  match Lib.Promise.value_opt def with
  | Some v -> string_of_val d v
  | None -> "_"
