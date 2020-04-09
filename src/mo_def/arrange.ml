open Mo_types
open Mo_values

open Source
open Syntax
open Wasm.Sexpr

let ($$) head inner = Node (head, inner)

and id i = Atom i.it
and tag i = Atom ("#" ^ i.it)

let rec exp e = match e.it with
  | VarE x              -> "VarE"      $$ [id x]
  | LitE l              -> "LitE"      $$ [lit !l]
  | ActorUrlE e         -> "ActorUrlE" $$ [exp e]
  | UnE (ot, uo, e)     -> "UnE"       $$ [operator_type !ot; Arrange_ops.unop uo; exp e]
  | BinE (ot, e1, bo, e2) -> "BinE"    $$ [operator_type !ot; exp e1; Arrange_ops.binop bo; exp e2]
  | RelE (ot, e1, ro, e2) -> "RelE"    $$ [operator_type !ot; exp e1; Arrange_ops.relop ro; exp e2]
  | ShowE (ot, e)       -> "ShowE"     $$ [operator_type !ot; exp e]
  | TupE es             -> "TupE"      $$ List.map exp es
  | ProjE (e, i)        -> "ProjE"     $$ [exp e; Atom (string_of_int i)]
  | ObjE (s, efs)       -> "ObjE"      $$ [obj_sort s] @ List.map exp_field efs
  | DotE (e, x)         -> "DotE"      $$ [exp e; id x]
  | AssignE (e1, e2)    -> "AssignE"   $$ [exp e1; exp e2]
  | ArrayE (m, es)      -> "ArrayE"    $$ [mut m] @ List.map exp es
  | IdxE (e1, e2)       -> "IdxE"      $$ [exp e1; exp e2]
  | FuncE (x, sp, tp, p, t, sugar, e') ->
    "FuncE" $$ [
      Atom (Type.string_of_typ e.note.note_typ);
      sort_pat sp;
      Atom x] @
      List.map typ_bind tp @ [
      pat p;
      (match t with None -> Atom "_" | Some t -> typ t);
      Atom (if sugar then "" else "=");
      exp e'
    ]
  | CallE (e1, ts, e2)  -> "CallE"   $$ [exp e1] @ inst ts @ [exp e2]
  | BlockE ds           -> "BlockE"  $$ List.map dec ds
  | NotE e              -> "NotE"    $$ [exp e]
  | AndE (e1, e2)       -> "AndE"    $$ [exp e1; exp e2]
  | OrE (e1, e2)        -> "OrE"     $$ [exp e1; exp e2]
  | IfE (e1, e2, e3)    -> "IfE"     $$ [exp e1; exp e2; exp e3]
  | SwitchE (e, cs)     -> "SwitchE" $$ [exp e] @ List.map case cs
  | WhileE (e1, e2)     -> "WhileE"  $$ [exp e1; exp e2]
  | LoopE (e1, None)    -> "LoopE"   $$ [exp e1]
  | LoopE (e1, Some e2) -> "LoopE"   $$ [exp e1; exp e2]
  | ForE (p, e1, e2)    -> "ForE"    $$ [pat p; exp e1; exp e2]
  | LabelE (i, t, e)    -> "LabelE"  $$ [id i; typ t; exp e]
  | DebugE e            -> "DebugE"  $$ [exp e]
  | BreakE (i, e)       -> "BreakE"  $$ [id i; exp e]
  | RetE e              -> "RetE"    $$ [exp e]
  | AsyncE (tb, e)      -> "AsyncE"  $$ [typ_bind tb; exp e]
  | AwaitE e            -> "AwaitE"  $$ [exp e]
  | AssertE e           -> "AssertE" $$ [exp e]
  | AnnotE (e, t)       -> "AnnotE"  $$ [exp e; typ t]
  | OptE e              -> "OptE"    $$ [exp e]
  | TagE (i, e)         -> "TagE"    $$ [id i; exp e]
  | PrimE p             -> "PrimE"   $$ [Atom p]
  | ImportE (f, _fp)    -> "ImportE" $$ [Atom f]
  | ThrowE e            -> "ThrowE"  $$ [exp e]
  | TryE (e, cs)        -> "TryE"    $$ [exp e] @ List.map catch cs

and inst inst = match inst.it with
  | None -> []
  | Some ts -> List.map typ ts

and pat p = match p.it with
  | WildP           -> Atom "WildP"
  | VarP x          -> "VarP"       $$ [id x]
  | TupP ps         -> "TupP"       $$ List.map pat ps
  | ObjP ps         -> "ObjP"       $$ List.map pat_field ps
  | AnnotP (p, t)   -> "AnnotP"     $$ [pat p; typ t]
  | LitP l          -> "LitP"       $$ [lit !l]
  | SignP (uo, l)   -> "SignP"      $$ [Arrange_ops.unop uo ; lit !l]
  | OptP p          -> "OptP"       $$ [pat p]
  | TagP (i, p)     -> "TagP"       $$ [tag i; pat p]
  | AltP (p1,p2)    -> "AltP"       $$ [pat p1; pat p2]
  | ParP p          -> "ParP"       $$ [pat p]

and lit (l:lit) = match l with
  | NullLit       -> Atom "NullLit"
  | BoolLit true  -> "BoolLit"   $$ [ Atom "true" ]
  | BoolLit false -> "BoolLit"   $$ [ Atom "false" ]
  | NatLit n      -> "NatLit"    $$ [ Atom (Value.Nat.to_pretty_string n) ]
  | Nat8Lit n     -> "Nat8Lit"   $$ [ Atom (Value.Nat8.to_pretty_string n) ]
  | Nat16Lit n    -> "Nat16Lit"  $$ [ Atom (Value.Nat16.to_pretty_string n) ]
  | Nat32Lit n    -> "Nat32Lit"  $$ [ Atom (Value.Nat32.to_pretty_string n) ]
  | Nat64Lit n    -> "Nat64Lit"  $$ [ Atom (Value.Nat64.to_pretty_string n) ]
  | IntLit i      -> "IntLit"    $$ [ Atom (Value.Int.to_pretty_string i) ]
  | Int8Lit i     -> "Int8Lit"   $$ [ Atom (Value.Int_8.to_pretty_string i) ]
  | Int16Lit i    -> "Int16Lit"  $$ [ Atom (Value.Int_16.to_pretty_string i) ]
  | Int32Lit i    -> "Int32Lit"  $$ [ Atom (Value.Int_32.to_pretty_string i) ]
  | Int64Lit i    -> "Int64Lit"  $$ [ Atom (Value.Int_64.to_pretty_string i) ]
  | Word8Lit w    -> "Word8Lit"  $$ [ Atom (Value.Word8.to_pretty_string w) ]
  | Word16Lit w   -> "Word16Lit" $$ [ Atom (Value.Word16.to_pretty_string w) ]
  | Word32Lit w   -> "Word32Lit" $$ [ Atom (Value.Word32.to_pretty_string w) ]
  | Word64Lit w   -> "Word64Lit" $$ [ Atom (Value.Word64.to_pretty_string w) ]
  | FloatLit f    -> "FloatLit"  $$ [ Atom (Value.Float.to_pretty_string f) ]
  | CharLit c     -> "CharLit"   $$ [ Atom (string_of_int c) ]
  | TextLit t     -> "TextLit"   $$ [ Atom t ]
  | PreLit (s,p)  -> "PreLit"    $$ [ Atom s; Arrange_type.prim p ]

and case c = "case" $$ [pat c.it.pat; exp c.it.exp]

and catch c = "catch" $$ [pat c.it.pat; exp c.it.exp]

and pat_field pf = pf.it.id.it $$ [pat pf.it.pat]

and obj_sort s = match s.it with
  | Type.Object -> Atom "Object"
  | Type.Actor -> Atom "Actor"
  | Type.Module -> Atom "Module"


and sort_pat sp = match sp.it with
  | Type.Local -> Atom "Local"
  | Type.Shared (Type.Write, p) -> "Shared" $$ [pat p]
  | Type.Shared (Type.Query, p) -> "Query" $$ [pat p]

and func_sort s = match s.it with
  | Type.Local -> Atom "Local"
  | Type.Shared Type.Write -> Atom "Shared"
  | Type.Shared Type.Query -> Atom "Query"

and mut m = match m.it with
  | Const -> Atom "Const"
  | Var   -> Atom "Var"

and vis v = match v.it with
  | Public  -> Atom "Public"
  | Private -> Atom "Private"

and typ_field (tf : typ_field)
  = tf.it.id.it $$ [typ tf.it.typ; mut tf.it.mut]

and typ_tag (tt : typ_tag)
  = tt.it.tag.it $$ [typ tt.it.typ]

and typ_bind (tb : typ_bind)
  = tb.it.var.it $$ [typ tb.it.bound]

and exp_field (ef : exp_field)
  = "Field" $$ [dec ef.it.dec; vis ef.it.vis]

and operator_type t = Atom (Type.string_of_typ t)

and path p = match p.it with
  | IdH i -> "IdH" $$ [id i]
  | DotH (p,i) -> "DotH" $$ [path p; id i]

and typ t = match t.it with
  | PathT (p, ts)       -> "PathT" $$ [path p] @ List.map typ ts
  | PrimT p             -> "PrimT" $$ [Atom p]
  | ObjT (s, ts)        -> "ObjT" $$ [obj_sort s] @ List.map typ_field ts
  | ArrayT (m, t)       -> "ArrayT" $$ [mut m; typ t]
  | OptT t              -> "OptT" $$ [typ t]
  | VariantT cts        -> "VariantT" $$ List.map typ_tag cts
  | TupT ts             -> "TupT" $$ List.map typ ts
  | FuncT (s, tbs, at, rt) -> "FuncT" $$ [func_sort s] @ List.map typ_bind tbs @ [ typ at; typ rt]
  | AsyncT (t1, t2)     -> "AsyncT" $$ [typ t1; typ t2]
  | ParT t              -> "ParT" $$ [typ t]

and dec d = match d.it with
  | ExpD e -> "ExpD" $$ [exp e ]
  | IgnoreD e -> "IgnoreD" $$ [exp e ]
  | LetD (p, e) -> "LetD" $$ [pat p; exp e]
  | VarD (x, e) -> "VarD" $$ [id x; exp e]
  | TypD (x, tp, t) ->
    "TypD" $$ [id x] @ List.map typ_bind tp @ [typ t]
  | ClassD (x, tp, p, rt, s, i', efs) ->
    "ClassD" $$ id x :: List.map typ_bind tp @ [
      pat p;
      (match rt with None -> Atom "_" | Some t -> typ t);
      obj_sort s; id i'
    ] @ List.map exp_field efs

and prog prog = "BlockE"  $$ List.map dec prog.it
