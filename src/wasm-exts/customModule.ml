(* Extend the idea of a module as defined in Wasm.Syntax
   with custom sections that we are interested in
*)

open Wasm.Ast

type name_section = {
  module_ : string option;
  function_names : (int32 * string) list;
  locals_names : (int32 * (int32 * string) list) list;
}

let empty_name_section : name_section = {
  module_ = None;
  function_names = [];
  locals_names = [];
}

type dylink_section = {
  memory_size : int32;
  memory_alignment : int32;
  table_size : int32;
  table_alignment : int32;
  needed_dynlibs : string list;
}

type extended_module = {
  (* The non-custom sections *)
  module_ : module_';
  (* name section *)
  name : name_section;
  (* dylib section *)
  dylink : dylink_section option;
  }
