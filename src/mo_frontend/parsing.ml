
module P =
  MenhirLib.Printers.Make
    (Parser.MenhirInterpreter)
    (Printers)

(* Instantiate [ErrorReporting] for our parser. This requires
   providing a few functions -- see [CalcErrorReporting]. *)

module E =
  Menhir_error_reporting.Make
    (Parser.MenhirInterpreter)
    (Error_reporting)

(* Define a printer for explanations. We treat an explanation as if it
   were just an item: that is, we ignore the position information that
   is provided in the explanation. Indeed, this information is hard to
   show in text mode. *)

let uniq xs = List.fold_right (fun x ys -> if List.mem x ys then ys else x::ys) xs []

let abstract_symbols explanations =
  let symbols = List.sort Parser.MenhirInterpreter.compare_symbols
    (List.map (fun e -> List.hd (E.future e))  explanations) in
  let ss = List.map Printers.string_of_symbol symbols in
  String.concat "\n  " (uniq ss)

let abstract_future future =
  let ss = List.map Printers.string_of_symbol future  in
  String.concat " " ss

let rec lex_compare_futures f1 f2 =
  match f1,f2 with
  | [], [] -> 0
  | s1::ss1,s2::ss2 ->
    (match Parser.MenhirInterpreter.compare_symbols s1 s2 with
     | 0 -> lex_compare_futures ss1 ss2
     | c -> c)
  | _ -> assert false

let compare_futures f1 f2 = match compare (List.length f1) (List.length f2) with
      | 0 -> lex_compare_futures f1 f2
      | c -> c

let abstract_futures explanations =
  let futures = List.sort compare_futures (List.map E.future explanations) in
  let ss = List.map abstract_future futures in
  String.concat "\n  " (uniq ss)

let abstract_item item =
  P.print_item item;
  Printers.to_string()

let abstract_items explanations =
  let items = List.sort Parser.MenhirInterpreter.compare_items (List.map E.item explanations) in
  let ss = List.map abstract_item items in
  String.concat "  " (uniq ss)

let error_message error_detail lexeme explanations =
  let token = String.escaped lexeme in
  match error_detail with
  | 1 ->
    Printf.sprintf
      "unexpected token '%s', \nexpected one of token or <phrase>:\n  %s"
      token (abstract_symbols explanations)
  | 2 ->
    Printf.sprintf
      "unexpected token '%s', \nexpected one of token or <phrase> sequence:\n  %s"
      token (abstract_futures explanations)
  | 3 ->
    Printf.sprintf
      "unexpected token '%s'\n in position marked . of partially parsed item(s):\n%s"
      token (abstract_items explanations)
  | _ ->
    Printf.sprintf "unexpected token '%s'" token

type error_detail = int

exception Error of string

let parse error_detail checkpoint lexer lexbuf =
  try E.entry checkpoint lexer lexbuf with E.Error (_, explanations) ->
    raise (Error (error_message error_detail (Lexing.lexeme lexbuf) explanations))
