open Idllib.Syntax
open Source
module M = Mo_types.Type
module I = Idllib.Typing

let m_env = ref M.Env.empty

let check_prim p =
  match p with
  | Null -> M.Prim M.Null
  | Bool -> M.Prim M.Bool
  | Int -> M.Prim M.Int
  | Int8 -> M.Prim M.Int8
  | Int16 -> M.Prim M.Int16
  | Int32 -> M.Prim M.Int32
  | Int64 -> M.Prim M.Int64
  | Nat -> M.Prim M.Nat
  | Nat8 -> M.Prim M.Nat8
  | Nat16 -> M.Prim M.Nat16
  | Nat32 -> M.Prim M.Nat32
  | Nat64 -> M.Prim M.Nat64
  | Float32 -> raise (Invalid_argument "float32 not supported")
  | Float64 -> M.Prim M.Float
  | Text -> M.Prim M.Text
  | Reserved -> M.Any
  | Empty -> M.Non

let check_modes ms =
  match ms with
  | [] -> (M.Write, M.Promises)
  | [{it=Oneway; _}] -> (M.Write, M.Returns)
  | [{it=Query; _}] -> (M.Query, M.Promises)
  | _ -> assert false

let check_label lab =
  match lab.it with
  | Named name -> Idllib.Escape.escape name
  | Id id -> Idllib.Escape.escape_num id
  | Unnamed id -> Idllib.Escape.escape_num id

let is_tuple fs =
  List.length fs > 1 &&
    let fs = List.mapi (fun i f -> (i, f)) fs in
    List.for_all (fun (i, f) ->
        match f.it.label.it with
        | Unnamed id -> Lib.Uint32.to_int id = i
        | _ -> false) fs

let rec check_typ env t =
  match t.it with
  | PrimT p -> check_prim p
  | PrincipalT -> M.Prim M.Principal
  | VarT {it=id; _} ->
     (match M.Env.find_opt id !m_env with
      | None ->
         let con = Mo_types.Con.fresh id (M.Abs ([], M.Pre)) in
         let res_t = M.Con (con, []) in
         m_env := M.Env.add id res_t !m_env;
         let t' = I.Env.find id env in
         let t' = check_typ env t' in
         M.set_kind con (M.Def ([], t'));
         res_t
      | Some t -> t
     )
  | OptT t -> M.Opt (check_typ env t)
  | VecT t -> M.Array (check_typ env t)
  | RecordT fs ->
     if is_tuple fs then
       M.Tup (List.map (fun f -> check_typ env f.it.typ) fs)
     else
       let fs = List.map (check_field env) fs in
       M.Obj (M.Object, List.sort M.compare_field fs)
  | VariantT fs ->
     let fs = List.map (check_variant_field env) fs in
     M.Variant (List.sort M.compare_field fs)
  | FuncT (ms, ts1, ts2) ->
     let (s, c) = check_modes ms in
     M.Func (M.Shared s, c, [M.scope_bind], List.map (check_typ env) ts1, List.map (check_typ env) ts2)
  | ServT ms ->
     let fs = List.map (check_meth env) ms in
     M.Obj (M.Actor, List.sort M.compare_field fs)
  | PreT -> assert false
and check_field env f =
  M.{lab = check_label f.it.label; typ = check_typ env f.it.typ}
and check_variant_field env f =
  match f.it.typ.it with
  | PrimT Null -> M.{lab = check_label f.it.label; typ = M.Tup []}
  | _ -> check_field env f
and check_meth env (m: typ_meth) =
  M.{lab = Idllib.Escape.escape m.it.var.it; typ = check_typ env m.it.meth}

let check_prog (env: typ I.Env.t) actor : M.typ =
  match actor with
  | Some {it=ServT ms; _} ->
     let fs = List.map (check_meth env) ms in
     let fs = M.Env.fold (fun id t fs ->
       match t with
       | M.Con (c, _) -> M.{lab = id; typ = M.Typ c}::fs
       | _ -> assert false) !m_env fs in
     M.Obj (M.Actor, List.sort M.compare_field fs)
  | None -> assert false
  | _ -> assert false

