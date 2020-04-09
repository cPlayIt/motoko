open Mo_frontend
open Mo_config
module Lsp = Lsp.Lsp_t

type cursor_target = CIdent of string | CQualified of string * string

let string_of_cursor_target = function
  | CIdent i -> "(CIdent " ^ i ^ ")"
  | CQualified (q, i) -> "CQUalified (" ^ q ^ ", " ^ i ^ ")"

let cursor_target_at_pos (position : Lsp.position) (file_contents : string) :
    cursor_target option =
  let line = position.Lsp.position_line + 1 in
  let column = position.Lsp.position_character + 1 in
  let lexbuf = Lexing.from_string file_contents in
  let next () = Lexer.token Lexer.Normal lexbuf in
  let pos_past_cursor pos =
    pos.Source.line > line
    || (pos.Source.line = line && pos.Source.column >= column)
  in
  let rec loop = function
    | _ when pos_past_cursor (Lexer.region lexbuf).Source.left -> None
    | Parser.ID ident -> (
        match next () with
        | Parser.DOT -> (
            match next () with
            | Parser.ID prefix ->
                let next_token_end = (Lexer.region lexbuf).Source.right in
                if pos_past_cursor next_token_end then
                  Some (CQualified (ident, prefix))
                else loop (Parser.ID prefix)
            | tkn ->
                let next_token_start = (Lexer.region lexbuf).Source.left in
                if pos_past_cursor next_token_start then Some (CIdent ident)
                else loop tkn )
        | _ when pos_past_cursor (Lexer.region lexbuf).Source.left ->
            Some (CIdent ident)
        | tkn -> loop tkn )
    | Parser.EOF -> None
    | _ -> loop (next ())
  in
  try loop (next ()) with _ -> None

let is_package_path (path : string) =
  let open Pipeline.URL in
  match parse path with Ok (Package _) -> true | Ok Prim -> true | _ -> false

let uri_for_package (path : string) =
  let open Pipeline.URL in
  match parse path with
  | Ok (Package (pkg, path)) -> (
      match Flags.M.find_opt pkg !Flags.package_urls with
      | None -> None
      | Some pkg_path ->
          (* Resolved package paths are always absolute *)
          (* TBR: But Flags.package_urls does not contain the resolved paths! *)
          Some ("file://" ^ Filename.concat pkg_path path) )
  | _ -> None

let import_relative_to_project_root root module_path dependency =
  if is_package_path dependency then Some dependency
  else
    match Lib.FilePath.relative_to root module_path with
    | None -> None
    | Some root_to_module ->
        root_to_module
        |> Filename.dirname
        |> Fun.flip Filename.concat dependency
        |> Lib.FilePath.normalise
        |> Option.some

(* Given the source of a module, figure out under what names what
   modules have been imported. Normalizes the imported modules
   filepaths relative to the project root *)
let parse_module_header project_root current_file_path file =
  let lexbuf = Lexing.from_string file in
  let next () = Lexer.token Lexer.Normal lexbuf in
  let res = ref [] in
  let rec loop = function
    | Parser.IMPORT -> (
        match next () with
        | Parser.ID alias -> (
            match next () with
            | Parser.TEXT path ->
                let path =
                  import_relative_to_project_root project_root current_file_path
                    path
                in
                ( match path with
                | Some path -> res := (alias, path) :: !res
                | None -> () );
                loop (next ())
            | tkn -> loop tkn )
        | tkn -> loop tkn )
    | Parser.EOF -> List.rev !res
    | tkn -> loop (next ())
  in
  try loop (next ()) with _ -> List.rev !res

type unresolved_target = { qualifier : string; ident : string }

type resolved_target = { qualifier : string; ident : string; path : string }

type identifier_target =
  | Ident of string
  | Alias of string * string
  | Unresolved of unresolved_target
  | Resolved of resolved_target

let identifier_at_pos project_root file_path file_contents position =
  let imported = parse_module_header project_root file_path file_contents in
  cursor_target_at_pos position file_contents
  |> Option.map (function
       | CIdent s -> (
           match List.find_opt (fun (alias, _) -> alias = s) imported with
           | None -> Ident s
           | Some (alias, path) -> Alias (alias, path) )
       | CQualified (qual, ident) -> (
           match List.find_opt (fun (alias, _) -> alias = qual) imported with
           | None -> Unresolved { qualifier = qual; ident }
           | Some (alias, path) -> Resolved { qualifier = qual; ident; path } ))
