open Mo_types
open Mo_values
open Ir_def

open Ir
open Source

module V = Value
module T = Type
module CC = Call_conv

(* Context *)

type val_env = V.def V.Env.t
type lab_env = V.value V.cont V.Env.t
type ret_env = V.value V.cont option
type throw_env = V.value V.cont option
type reply_env = V.value V.cont option
type reject_env = V.value V.cont option
type actor_env = V.value V.Env.t ref (* indexed by actor ids *)

type state = actor_env

let initial_state () = ref V.Env.empty

type scope = val_env

type flags = {
  trace : bool;
  print_depth : int;
}

type env =
  { flags : flags;
    flavor : Ir.flavor;
    vals : val_env;
    labs : lab_env;
    rets : ret_env;
    throws : throw_env;
    replies : reply_env;
    rejects : reject_env;
    async : bool;
    caller : V.value;
    self : V.actor_id;
    actor_env : actor_env;
  }

let adjoin_scope s ve = V.Env.adjoin s ve

let adjoin_vals c ve = {c with vals = V.Env.adjoin c.vals ve}

let empty_scope = V.Env.empty

let env_of_scope flags flavor ae ve =
  { flags;
    flavor;
    vals = ve;
    labs = V.Env.empty;
    rets = None;
    throws = None;
    replies = None;
    rejects = None;
    caller = V.Text V.top_id;
    self = V.top_id;
    async = false;
    actor_env = ae;
  }

let context env = V.Text env.self

(* Error handling *)

exception Trap of Source.region * string

let trap at fmt = Printf.ksprintf (fun s -> raise (Trap (at, s))) fmt

let find id env =
  try V.Env.find id env
  with Not_found ->
    trap no_region "unbound identifier %s" id

(* Tracing *)

let trace_depth = ref 0

let trace fmt =
  Printf.ksprintf (fun s ->
    Printf.printf "%s%s\n%!" (String.make (2 * !trace_depth) ' ') s
  ) fmt

let string_of_val env = V.string_of_val env.flags.print_depth
let string_of_def flags = V.string_of_def flags.print_depth
let string_of_arg env = function
  | V.Tup _ as v -> string_of_val env v
  | v -> "(" ^ string_of_val env v ^ ")"


(* Debugging aids *)

let last_env = ref (env_of_scope { trace = false; print_depth = 2} Ir.full_flavor (initial_state ()) empty_scope)
let last_region = ref Source.no_region

let print_exn flags exn =
  Printf.printf "%!";
  let at = Source.string_of_region !last_region in
  Printf.eprintf "%s: internal error, %s\n" at (Printexc.to_string exn);
  Printf.eprintf "\nLast environment:\n";
  Value.Env.iter
    (fun x d -> Printf.eprintf "%s = %s\n" x (string_of_def flags d))
    !last_env.vals;
  Printf.eprintf "\n";
  Printexc.print_backtrace stderr;
  Printf.eprintf "%!"

(* Scheduling *)

module Scheduler =
struct
  let q : (unit -> unit) Queue.t = Queue.create ()

  let queue work = Queue.add work q
  let yield () =
    trace_depth := 0;
    try Queue.take q () with Trap (at, msg) ->
      Printf.printf "%s: execution error, %s\n" (Source.string_of_region at) msg

  let rec run () =
    if not (Queue.is_empty q) then (yield (); run ())
end

(* Async auxiliary functions *)

(* Are these just duplicates of the corresponding functions in interpret.ml? If so, refactor *)

let make_async () : V.async =
  {V.result = Lib.Promise.make (); waiters = []}

let get_async async (k : V.value V.cont) (r : V.value V.cont) =
  match Lib.Promise.value_opt async.V.result with
  | Some (V.Ok v) -> k v
  | Some (V.Error v) -> r v
  | None -> async.V.waiters <- (k,r)::async.V.waiters

let set_async async v =
  List.iter (fun (k,_) -> Scheduler.queue (fun () -> k v)) async.V.waiters;
  Lib.Promise.fulfill async.V.result (V.Ok v);
  async.V.waiters <- []

let reject_async async v =
  List.iter (fun (_,r) -> Scheduler.queue (fun () -> r v)) async.V.waiters;
  Lib.Promise.fulfill async.V.result (V.Error v);
  async.V.waiters <- []

let reply async v =
  Scheduler.queue (fun () -> set_async async v)

let reject async v =
  match v with
  | V.Tup [ _code; message ] ->
    (* mask the error code before rejecting *)
    Scheduler.queue
      (fun () -> reject_async async (V.Tup [V.Variant("error", V.unit); message]))
  | _ -> assert false

let async env at (f: (V.value V.cont) -> (V.value V.cont) -> unit) (k : V.value V.cont) =
    let async = make_async () in
    let k' = reply async in
    let r = reject async in
    if env.flags.trace then trace "-> async %s" (string_of_region at);
    Scheduler.queue (fun () ->
      if env.flags.trace then trace "<- async %s" (string_of_region at);
      incr trace_depth;
      f (fun v ->
        if env.flags.trace then trace "<= %s" (string_of_val env v);
        decr trace_depth;
        k' v)
        r
    );
    k (V.Async async)

let await env at async k =
  if env.flags.trace then trace "=> await %s" (string_of_region at);
  decr trace_depth;
  get_async async (fun v ->
      Scheduler.queue (fun () ->
          if env.flags.trace then
            trace "<- await %s%s" (string_of_region at) (string_of_arg env v);
          incr trace_depth;
          k v
        )
    )


(* queue a lowered oneway or replying function that no longer does AsyncE on entry *)
let queue f = fun c v k -> Scheduler.queue (fun () -> f c v k)

let make_unit_message env id call_conv f =
  assert env.flavor.has_async_typ;
  let open CC in
  match call_conv with
  | {sort = T.Shared s; n_res = 0; _} ->
    (* message scheduled by AsyncE in f *)
    Value.message_func s call_conv.n_args f
  | _ ->
    failwith ("unexpected call_conv " ^ string_of_call_conv call_conv)

let make_async_message env id call_conv f =
  assert env.flavor.has_async_typ;
  let open CC in
  match call_conv with
  | {sort = T.Shared s; control = T.Promises; _} ->
    (* message scheduled by AsyncE in f *)
    Value.async_func s call_conv.n_args call_conv.n_res f
  | _ ->
    failwith ("unexpected call_conv " ^ string_of_call_conv call_conv)

let make_lowered_unit_message env id call_conv f =
  assert (not env.flavor.has_async_typ);
  let open CC in
  match call_conv with
  | {sort = T.Shared s; n_res = 0; _} ->
    (* message scheduled here (not by f) *)
    Value.message_func s call_conv.n_args (fun c v k ->
      (queue f) c v (fun _ -> ());
      k (V.unit);
    );
  | _ ->
    failwith ("unexpected call_conv " ^ string_of_call_conv call_conv)

let make_replying_message env id call_conv f =
  assert (not env.flavor.has_async_typ);
  let open CC in
  match call_conv with
  | {sort = T.Shared s; control = T.Replies; _} ->
    Value.replies_func s call_conv.n_args call_conv.n_res (fun c v k ->
      (* message scheduled here (not by f) *)
      (queue f) c v (fun _ -> ());
      k (V.unit)
    )
  | _ ->
    failwith ("unexpected call_conv " ^ string_of_call_conv call_conv)

let make_message env x cc f : V.value =
  match cc.CC.control with
  | T.Returns ->
    if env.flavor.has_async_typ then
      make_unit_message env x cc f
    else
      make_lowered_unit_message env x cc f
  | T.Promises -> make_async_message env x cc f
  | T.Replies -> make_replying_message env x cc f


(* Literals *)

let interpret_lit env lit : V.value =
  match lit with
  | NullLit -> V.Null
  | BoolLit b -> V.Bool b
  | NatLit n -> V.Int n
  | Nat8Lit n -> V.Nat8 n
  | Nat16Lit n -> V.Nat16 n
  | Nat32Lit n -> V.Nat32 n
  | Nat64Lit n -> V.Nat64 n
  | IntLit i -> V.Int i
  | Int8Lit i -> V.Int8 i
  | Int16Lit i -> V.Int16 i
  | Int32Lit i -> V.Int32 i
  | Int64Lit i -> V.Int64 i
  | Word8Lit w -> V.Word8 w
  | Word16Lit w -> V.Word16 w
  | Word32Lit w -> V.Word32 w
  | Word64Lit w -> V.Word64 w
  | FloatLit f -> V.Float f
  | CharLit c -> V.Char c
  | TextLit s -> V.Text s
  | BlobLit b -> V.Text b

(* Expressions *)

let check_call_conv exp call_conv =
  let open Call_conv in
  let exp_call_conv = call_conv_of_typ exp.note.Note.typ in
  if not (exp_call_conv = call_conv) then
    failwith (Printf.sprintf "call_conv mismatch: function %s of type %s expecting %s, found %s"
      (Wasm.Sexpr.to_string 80 (Arrange_ir.exp exp))
      (T.string_of_typ exp.note.Note.typ)
      (string_of_call_conv exp_call_conv)
      (string_of_call_conv call_conv))

let check_call_conv_arg env exp v call_conv =
  let open CC in
  if call_conv.n_args <> 1 then
  let es = try V.as_tup v
    with Invalid_argument _ ->
      failwith (Printf.sprintf "call %s: calling convention %s cannot handle non-tuple value %s"
        (Wasm.Sexpr.to_string 80 (Arrange_ir.exp exp))
        (string_of_call_conv call_conv)
        (string_of_val env v)) in
  if List.length es <> call_conv.n_args then
    failwith (Printf.sprintf "call %s: calling convention %s got tuple of wrong length %s"
        (Wasm.Sexpr.to_string 80 (Arrange_ir.exp exp))
        (string_of_call_conv call_conv)
        (string_of_val env v))


let rec interpret_exp env exp (k : V.value V.cont) =
  interpret_exp_mut env exp (function V.Mut r -> k !r | v -> k v)

and interpret_exp_mut env exp (k : V.value V.cont) =
  let open Call_conv in
  last_region := exp.at;
  last_env := env;
  Profiler.bump_region exp.at ;
  match exp.it with
  | VarE id ->
    (match Lib.Promise.value_opt (find id env.vals) with
    | Some v -> k v
    | None -> trap exp.at "accessing identifier before its definition"
    )
  | LitE lit ->
    k (interpret_lit env lit)
  | PrimE (p, es) ->
    interpret_exps env es [] (fun vs ->
      match p, vs with
      | CallPrim typs, [v1; v2] ->
        let call_conv, f = V.as_func v1 in
        check_call_conv (List.hd es) call_conv;
        check_call_conv_arg env exp v2 call_conv;
        last_region := exp.at; (* in case the following throws *)
        f (context env) v2 k
      | UnPrim (ot, op), [v1] ->
        k (try Operator.unop op ot v1 with Invalid_argument s -> trap exp.at "%s" s)
      | BinPrim (ot, op), [v1; v2] ->
        k (try Operator.binop op ot v1 v2 with _ ->
          trap exp.at "arithmetic overflow")
      | RelPrim (ot, op), [v1; v2] ->
        k (Operator.relop op ot v1 v2)
      | TupPrim, exps ->
        k (V.Tup vs)
      | ProjPrim n, [v1] ->
        k (List.nth (V.as_tup v1) n)
      | OptPrim, [v1] ->
        k (V.Opt v1)
      | TagPrim i, [v1] ->
        k (V.Variant (i, v1))
      | DotPrim n, [v1] ->
        let fs = V.as_obj v1 in
        k (try find n fs with _ -> assert false)
      | ActorDotPrim n, [v1] ->
        let id = V.as_text v1 in
        begin match V.Env.find_opt id !(env.actor_env) with
        (* not quite correct: On the platform, you can invoke and get a reject *)
        | None -> trap exp.at "Unkown actor \"%s\"" id
        | Some actor_value ->
          let fs = V.as_obj actor_value in
          match V.Env.find_opt n fs with
          | None -> trap exp.at "Actor \"%s\" has no method \"%s\"" id n
          | Some field_value -> k field_value
        end
      | ArrayPrim (mut, _), vs ->
        let vs' =
          match mut with
          | Var -> List.map (fun v -> V.Mut (ref v)) vs
          | Const -> vs
        in k (V.Array (Array.of_list vs'))
      | IdxPrim, [v1; v2] ->
        k (try (V.as_array v1).(V.Int.to_int (V.as_int v2))
           with Invalid_argument s -> trap exp.at "%s" s)
      | BreakPrim id, [v1] -> find id env.labs v1
      | RetPrim, [v1] -> Option.get env.rets v1
      | ThrowPrim, [v1] -> Option.get env.throws v1
      | AwaitPrim, [v1] ->
        assert env.flavor.has_await;
        await env exp.at (V.as_async v1) k (Option.get env.throws)
      | AssertPrim, [v1] ->
        if V.as_bool v1
        then k V.unit
        else trap exp.at "assertion failure"
      | ShowPrim ot, [v1] ->
        if Show.can_show ot
        then k (Value.Text (Show.show_val ot v1))
        else raise (Invalid_argument "debug_show")
      | CPSAsync _, [v1] ->
        assert (not env.flavor.has_await && env.flavor.has_async_typ);
        let (_, f) = V.as_func v1 in
        let typ = exp.note.Note.typ in
        begin match typ with
        | T.Func(_, _, _, [T.Func(_, _, _, [f_dom], _);T.Func(_, _, _, [r_dom], _)], _) ->
          let call_conv_f = CC.call_conv_of_typ f_dom in
          let call_conv_r = CC.call_conv_of_typ r_dom in
          async env exp.at
            (fun k' r ->
              let vk' = Value.Func (call_conv_f, fun c v _ -> k' v) in
              let vr = Value.Func (call_conv_r, fun c v _ -> r v) in
              let vc = context env in
              f vc (V.Tup [vk'; vr]) V.as_unit
            )
            k
        | _ -> assert false
        end
      | CPSAwait, [v1; v2] ->
        assert (not env.flavor.has_await && env.flavor.has_async_typ);
        begin match V.as_tup v2 with
         | [vf; vr] ->
           let (_, f) = V.as_func vf in
           let (_, r) = V.as_func vr in
           await env exp.at (V.as_async v1)
             (fun v -> f (context env) v k)
             (fun e -> r (context env) e k) (* TBR *)
        | _ -> assert false
        end
      | OtherPrim s, vs ->
        let arg = match vs with [v] -> v | _ -> V.Tup vs in
        Prim.prim s (context env) arg k
      | CastPrim _, [v1] ->
        k v1
      | ActorOfIdBlob t, [v1] ->
        k v1
      | BlobOfIcUrl, [v1] ->
        trap exp.at "BlobOfIcUrl not implemented" (* FIXME: #1001, call Lib.URL.decode_actor_url *)
      | NumConvPrim (t1, t2), vs ->
        let arg = match vs with [v] -> v | _ -> V.Tup vs in
        Prim.num_conv_prim t1 t2 (context env) arg k
      | ICReplyPrim ts, [v1] ->
        assert (not env.flavor.has_async_typ);
        let reply = Option.get env.replies in
        Scheduler.queue (fun () -> reply v1)
      | ICRejectPrim, [v1] ->
        assert (not env.flavor.has_async_typ);
        let reject = Option.get env.rejects in
        let e = V.Tup [V.Variant ("error", V.unit); v1] in
        Scheduler.queue (fun () -> reject e)
      | ICCallPrim, [v1; v2; kv; rv] ->
        let call_conv, f = V.as_func v1 in
        check_call_conv (List.hd es) call_conv;
        check_call_conv_arg env exp v2 call_conv;
        last_region := exp.at; (* in case the following throws *)
        let vc = context env in
        f (V.Tup[vc; kv; rv]) v2 k
      | ICCallerPrim, [] ->
        k env.caller
      | SelfRef _, [] ->
        k (V.Text env.self)
      | _ ->
        trap exp.at "Unknown prim or wrong number of arguments (%d given):\n  %s"
          (List.length es) (Wasm.Sexpr.to_string 80 (Arrange_ir.prim p))
    )
  | AssignE (lexp1, exp2) ->
    interpret_lexp env lexp1 (fun v1 ->
      interpret_exp env exp2 (fun v2 ->
        v1 := v2; k V.unit
      )
    )
  | BlockE (decs, exp1) ->
     interpret_block env None decs exp1 k
  | IfE (exp1, exp2, exp3) ->
    interpret_exp env exp1 (fun v1 ->
      if V.as_bool v1
      then interpret_exp env exp2 k
      else interpret_exp env exp3 k
    )
  | SwitchE (exp1, cases) ->
    interpret_exp env exp1 (fun v1 ->
      interpret_cases env cases exp.at v1 k
    )
  | TryE (exp1, cases) ->
    let k' = fun v1 -> interpret_catches env cases exp.at v1 k in
    let env' = { env with throws = Some k' } in
    interpret_exp env' exp1 k
  | LoopE exp1 ->
    interpret_exp env exp1 (fun v -> V.as_unit v; interpret_exp env exp k)
  | LabelE (id, _typ, exp1) ->
    let env' = {env with labs = V.Env.add id k env.labs} in
    interpret_exp env' exp1 k
  | AsyncE (_, exp1, _) ->
    assert env.flavor.has_await;
    async env
      exp.at
      (fun k' r ->
        let env' = {env with labs = V.Env.empty; rets = Some k'; throws = Some r; async = true}
        in interpret_exp env' exp1 k')
      k
  | DeclareE (id, typ, exp1) ->
    let env = adjoin_vals env (declare_id id) in
    interpret_exp env exp1 k
  | DefineE (id, mut, exp1) ->
    interpret_exp env exp1 (fun v ->
      let v' =
        match mut with
        | Const -> v
        | Var -> V.Mut (ref v)
      in
      define_id env id v';
      k V.unit
      )
  | SelfCallE (ts, exp_f, exp_k, exp_r) ->
    assert (not env.flavor.has_async_typ);
    (* see code for FuncE *)
    let cc = { sort = T.Shared T.Write; control = T.Replies; n_args = 0; n_res = List.length ts } in
    let f = interpret_message env exp.at "anon" []
      (fun env' -> interpret_exp env' exp_f) in
    let v = make_message env "anon" cc f in
    (* see code for ICCallPrim *)
    interpret_exp env exp_k (fun kv ->
    interpret_exp env exp_r (fun rv ->
        let _call_conv, f = V.as_func v in
        last_region := exp.at; (* in case the following throws *)
        let vc = context env in
        f (V.Tup[vc; kv; rv]) (V.Tup []) k))
  | FuncE (x, (T.Shared _ as sort), (T.Replies as control), _typbinds, args, ret_typs, e) ->
    assert (not env.flavor.has_async_typ);
    let cc = { sort; control; n_args = List.length args; n_res = List.length ret_typs } in
    let f = interpret_message env exp.at x args
      (fun env' -> interpret_exp env' e) in
    let v = make_message env x cc f in
    k v
  | FuncE (x, sort, control, _typbinds, args, ret_typs, e) ->
    let cc = { sort; control; n_args = List.length args; n_res = List.length ret_typs } in
    let f = interpret_func env exp.at sort x args
      (fun env' -> interpret_exp env' e) in
    let v = match cc.sort with
      | T.Shared _ -> make_message env x cc f
      | _ -> V.Func (cc, f)
    in
    k v
  | ActorE (ds, fs, _) ->
    let self = V.fresh_id () in
    let env0 = {env with self = self} in
    let ve = declare_decs ds V.Env.empty in
    let env' = adjoin_vals env0 ve in
    interpret_decs env' ds (fun _ ->
      let obj = interpret_fields env' fs in
      env.actor_env := V.Env.add self obj !(env.actor_env);
      k (V.Text self)
    )
  | NewObjE (sort, fs, _) ->
    k (interpret_fields env fs)

and interpret_lexp env lexp (k : (V.value ref) V.cont) =
  last_region := lexp.at;
  last_env := env;
  match lexp.it with
  | VarLE id ->
    (match Lib.Promise.value_opt (find id env.vals) with
    | Some v -> k (V.as_mut v)
    | None -> trap lexp.at "accessing identifier before its definition"
    )
  | DotLE (exp1, n) ->
    interpret_exp env exp1 (fun v1 ->
      let fs = V.as_obj v1 in
      k (V.as_mut (try find n fs with _ -> assert false))
    )
  | IdxLE (exp1, exp2) ->
    interpret_exp env exp1 (fun v1 ->
      interpret_exp env exp2 (fun v2 ->
        k (V.as_mut
          (try (V.as_array v1).(V.Int.to_int (V.as_int v2))
           with Invalid_argument s -> trap lexp.at "%s" s))
      )
    )

and interpret_fields env fs =
    let ve =
      List.fold_left
        (fun ve (f : field) ->
          V.Env.disjoint_add f.it.name (Lib.Promise.value (find f.it.var env.vals)) ve
        ) V.Env.empty fs in
    V.Obj ve

and interpret_exps env exps vs (k : V.value list V.cont) =
  match exps with
  | [] -> k (List.rev vs)
  | exp::exps' ->
    interpret_exp env exp (fun v -> interpret_exps env exps' (v::vs) k)


(* Cases *)

and interpret_cases env cases at v (k : V.value V.cont) =
  match cases with
  | [] ->
    trap at "switch value %s does not match any case" (string_of_val env v)
  | {it = {pat; exp}; at; _}::cases' ->
    match match_pat pat v with
    | Some ve -> interpret_exp (adjoin_vals env ve) exp k
    | None -> interpret_cases env cases' at v k

(* Catches *)

and interpret_catches env cases at v (k : V.value V.cont) =
  match cases with
  | [] ->
    Option.get env.throws v (* re-throw v *)
  | {it = {pat; exp}; at; _}::cases' ->
    match match_pat pat v with
    | Some ve -> interpret_exp (adjoin_vals env ve) exp k
    | None -> interpret_catches env cases' at v k

(* Argument lists *)

and match_arg a v : val_env = V.Env.singleton a.it (Lib.Promise.make_fulfilled v)

and match_args at args v : val_env =
  match args with
  | [a] -> match_arg a v
  | _ ->
    let vs = V.as_tup v in
    if (List.length vs <> List.length args) then
      failwith (Printf.sprintf "%s %s" (Source.string_of_region at) (V.string_of_val 0 v));
    List.fold_left V.Env.adjoin V.Env.empty (List.map2 match_arg args vs)

(* Patterns *)

and declare_id id =
  V.Env.singleton id (Lib.Promise.make ())

and declare_pat pat : val_env =
  match pat.it with
  | WildP | LitP _ ->  V.Env.empty
  | VarP id -> declare_id id
  | TupP pats -> declare_pats pats V.Env.empty
  | ObjP pfs -> declare_pats (pats_of_obj_pat pfs) V.Env.empty
  | OptP pat1
  | TagP (_, pat1) -> declare_pat pat1
  | AltP (pat1, pat2) -> declare_pat pat1

and declare_pats pats ve : val_env =
  match pats with
  | [] -> ve
  | pat::pats' ->
    let ve' = declare_pat pat in
    declare_pats pats' (V.Env.adjoin ve ve')


and define_id env id v =
  Lib.Promise.fulfill (find id env.vals) v

and define_pat env pat v =
  let err () = trap pat.at "value %s does not match pattern" (string_of_val env v) in
  match pat.it with
  | WildP -> ()
  | LitP _ | AltP _ ->
    if match_pat pat v = None
    then err ()
    else ()
  | VarP id -> define_id env id v
  | TupP pats -> define_pats env pats (V.as_tup v)
  | ObjP pfs -> define_field_pats env pfs (V.as_obj v)
  | OptP pat1 ->
    (match v with
    | V.Opt v1 -> define_pat env pat1 v1
    | V.Null -> err ()
    | _ -> assert false
    )
  | TagP (i, pat1) ->
    let lab, v1 = V.as_variant v in
    if lab = i
    then define_pat env pat1 v1
    else err ()

and define_pats env pats vs =
  List.iter2 (define_pat env) pats vs

and define_field_pats env pfs vs =
  let define_field (pf : pat_field) =
    define_pat env pf.it.pat (V.Env.find pf.it.name vs) in
  List.iter define_field pfs


and match_lit lit v : bool =
  match lit, v with
  | NullLit, V.Null -> true
  | BoolLit b, V.Bool b' -> b = b'
  | NatLit n, V.Int n' -> V.Int.eq n n'
  | Nat8Lit n, V.Nat8 n' -> V.Nat8.eq n n'
  | Nat16Lit n, V.Nat16 n' -> V.Nat16.eq n n'
  | Nat32Lit n, V.Nat32 n' -> V.Nat32.eq n n'
  | Nat64Lit n, V.Nat64 n' -> V.Nat64.eq n n'
  | IntLit i, V.Int i' -> V.Int.eq i i'
  | Int8Lit i, V.Int8 i' -> V.Int_8.eq i i'
  | Int16Lit i, V.Int16 i' -> V.Int_16.eq i i'
  | Int32Lit i, V.Int32 i' -> V.Int_32.eq i i'
  | Int64Lit i, V.Int64 i' -> V.Int_64.eq i i'
  | Word8Lit w, V.Word8 w' -> w = w'
  | Word16Lit w, V.Word16 w' -> w = w'
  | Word32Lit w, V.Word32 w' -> w = w'
  | Word64Lit w, V.Word64 w' -> w = w'
  | FloatLit z, V.Float z' -> z = z'
  | CharLit c, V.Char c' -> c = c'
  | TextLit u, V.Text u' -> u = u'
  | _ -> false

and match_id id v : val_env =
  V.Env.singleton id (Lib.Promise.make_fulfilled v)

and match_pat pat v : val_env option =
  match pat.it with
  | WildP -> Some V.Env.empty
  | VarP id -> Some (match_id id v)
  | LitP lit ->
    if match_lit lit v
    then Some V.Env.empty
    else None
  | TupP pats ->
    match_pats pats (V.as_tup v) V.Env.empty
  | ObjP pfs ->
    match_pat_fields pfs (V.as_obj v) V.Env.empty
  | OptP pat1 ->
    (match v with
    | V.Opt v1 -> match_pat pat1 v1
    | V.Null -> None
    | _ -> assert false
    )
  | TagP (i, pat1) ->
    let tag, v1 = V.as_variant v in
    if i = tag
    then match_pat pat1 v1
    else None
  | AltP (pat1, pat2) ->
    (match match_pat pat1 v with
    | None -> match_pat pat2 v
    | some -> some
    )

and match_pats pats vs ve : val_env option =
  match pats, vs with
  | [], [] -> Some ve
  | pat::pats', v::vs' ->
    (match match_pat pat v with
    | Some ve' -> match_pats pats' vs' (V.Env.adjoin ve ve')
    | None -> None
    )
  | _ -> assert false

and match_pat_fields pfs vs ve : val_env option =
  match pfs with
  | [] -> Some ve
  | pf::pfs' ->
    begin
      match match_pat pf.it.pat (V.Env.find pf.it.name vs) with
      | Some ve' -> match_pat_fields pfs' vs (V.Env.adjoin ve ve')
      | None -> None
    end

(* Blocks and Declarations *)

and interpret_block env ro decs exp k =
  let ve = declare_decs decs V.Env.empty in
  Option.iter (fun r -> r := ve) ro;
  let env' = adjoin_vals env ve in
  interpret_decs env' decs (fun _ -> interpret_exp env' exp k)

and declare_dec dec : val_env =
  match dec.it with
  | LetD (pat, _) -> declare_pat pat
  | VarD (id, _,  _) -> declare_id id

and declare_decs decs ve : val_env =
  match decs with
  | [] -> ve
  | dec::decs' ->
    let ve' = declare_dec dec in
    declare_decs decs' (V.Env.adjoin ve ve')


and interpret_dec env dec k =
  match dec.it with
  | LetD (pat, exp) ->
    interpret_exp env exp (fun v ->
      define_pat env pat v;
      k ()
    )
  | VarD (id, _, exp) ->
    interpret_exp env exp (fun v ->
      define_id env id (V.Mut (ref v));
      k ()
    )

and interpret_decs env decs (k : unit V.cont) =
  match decs with
  | [] -> k ()
  | d::ds -> interpret_dec env d (fun () -> interpret_decs env ds k)

and interpret_func env at sort x args f c v (k : V.value V.cont) =
  if env.flags.trace then trace "%s%s" x (string_of_arg env v);
  let caller =
    if T.is_shared_sort sort
    then c
    else env.caller
  in
  let ve = match_args at args v in
  incr trace_depth;
  let k' = fun v' ->
    if env.flags.trace then trace "<= %s" (string_of_val env v');
    decr trace_depth;
    k v'
  in
  let env' =
    { env with
      vals = V.Env.adjoin env.vals ve;
      labs = V.Env.empty;
      rets = Some k';
      async = false;
      caller = caller;
    }
  in f env' k'

and interpret_message env at x args f c v (k : V.value V.cont) =
  let v_caller, v_reply, v_reject = match V.as_tup c with
    | [v_caller; v_reply; v_reject] -> v_caller, v_reply, v_reject
    | _ -> assert false
  in
  if env.flags.trace then trace "%s%s" x (string_of_arg env v);
  let _, reply = V.as_func v_reply in
  let _, reject = V.as_func v_reject in
  let ve = match_args at args v in
  incr trace_depth;
  let k' = fun v' ->
    if env.flags.trace then trace "<= %s" (string_of_val env v');
    decr trace_depth;
    k v'
  in
  let env' =
    { env with
      vals = V.Env.adjoin env.vals ve;
      labs = V.Env.empty;
      rets = Some k';
      replies = Some (fun v -> reply (context env) v V.as_unit);
      rejects = Some (fun v -> reject (context env) v V.as_unit);
      caller = v_caller;
      async = false
    }
  in f env' k'

(* Programs *)

let interpret_prog flags state scope ((ds, exp), flavor) : scope =
  let env = env_of_scope flags flavor state scope in
  trace_depth := 0;
  let ve = ref V.Env.empty in
  try
    Scheduler.queue (fun () ->
      try interpret_block env (Some ve) ds exp  (fun v -> ())
      with Invalid_argument s -> trap !last_region "%s" s
    );
    Scheduler.run ();
    !ve
  with exn -> print_exn flags exn; !ve
