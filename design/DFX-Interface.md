Stable CLI for dfx
==================

An important way of using the Motoko compiler is via the the `dfx` tool,
provided by the DFINITY SDK, which provides project and package management
support.

This document describes the interface that `moc` and related tools provide to
`dfx`. The goal is that
 * the Motoko developers know which command line flags have to
   be kept stable in order to not break `dfx`, and that
 * the SDK developers have a single place to read about the moc interface, and
   a place to express additional requirements (by collaborating on a PR against
   this document.)

This interface includes:
 * nix derivations imported by SDK
 * binaries executed
 * command line arguments and environment varialbes passed to these binaries
 * where these binaries read files and
 * where these binaries write files, output or temporary
 * where they do _not_ write to, so that upgrading `moc` doesn’t suddenly leave
   artifacts where `dfx` does not expect them

It does not replace proper documentation, but should be kept rather concise.

Nix derivations
---------------

The `motoko` repository defines the following nix derivations, as attributes of
the top-level `default.nix`:

* `moc-bin`: contains `bin/moc`
* `mo-ide`: contains `bin/mo-ide`
* `didc`: contains `bin/didc`
* `rts`: contains `rts/mo-rts.wasm`, the Motoko runtime system
* `stdlib`: contains the standard library, directly in the top level directory,
  as `*.mo` files. It does not contain extra files (test files, for example)
* `stdlib-adocs`: contains the documentation of the standard library, directly
  in the top level directory, as `*.adoc` files. There is an `index.adoc`
  file.

The `default.nix` file itself takes an optional `system` parameter which is
either `"x86_64-linux"` or `"x86_64-darwin"`, and defaults to
`builtins.currentSystem`.

All binaries are either built statically (Linux) or only use system libraries (OSX).

Compiling Motoko Files to Wasm
------------------------------

In order to compile a motoko file, `dfx` invokes `moc` with

    moc some/path/input.mo            \
        -o another/path/output.wasm   \
        { --package pkgname pkgpath } \
        { --actor-alias alias url }
        [ --actor-idl actorpath ]

in an environment where `MOC_RTS` points to the location of the Motoko runtime system.

This _reads_ the following files
 * `some/path/input.mo`
 * any `.mo` file referenced by `some/path/input.mo`, either relatively, absolutely or via the provided package aliases
 * for every actor import `ic:canisterid` imported by any of the Motoko files, it reads `actorpath/canisterid.did`, see section Resolving Canister Ids below.
 * the given `mo-rts.wasm` file.

The package name `prim` is special and should not be set using `--package`.

No constraints are imposed where imported files reside (this may be refined to prevent relative imports from looking outside the project and the declared packages)

This _writes_ to `another/path/output.wasm`, but has no other effect. It does
not create `another/path/`.

Compiler warnings and errors are reported to `stderr`. Nothing writes to `stdout`.

Compiling Motoko Files to IDL
-----------------------------

As the previous point, but passing `--idl` to `moc`.

The IDL generation does not issue any warnings.


Resolving Canister aliases
--------------------------

For every actor imported using `import "canister:alias"`, the Motoko compiler treats that as `import "ic:canisterid"`, if the command line flag `--actor-alias alias ic:canisterid` is given.

The first argument to `--actor-alias` is the alias without the URL scheme. The second argument must be a valid `"ic:"` url according to the [textual representation] of principal ids.

The given aliases must be unique (i.e. no `--actor-alias a ic:00 --actor-alias a ic:ABCDE01A7`).

[textual representation]: https://docs.dfinity.systems/spec/public/#textual-ids

Resolving Canister types
------------------------

For every actor imported using `import "ic:canisterid"` (or `import "canister:alias"` if `alias` resolves to `ic:canisterid` as described above), the motoko compiler assumes the presence of a file `canisterid.did` in the actor idl path specified by `--actor-idl`. This file informs motoko about the interface of that canister, e.g. the output of `moc --idl` for a locally known canister, or the IDL file as fetched from the Internet Computer.

The `canisterid` here refers the “textual representation“ without the `ic:` prefix, but including the checksum. Note that this representation is unique.

This files informs motoko about the interface of that canister. It could be the output of `moc --idl` for a locally known canister, or the IDL file as fetched from the Internet Computer, or created any other way.

Open problem: how to resolve mutual canister imports.

Compiling IDL Files to JS
-------------------------

In order to compile a IDL file, `dfx` invokes `didc` with

    didc --js some/path/input.did -o another/path/output.js

This _reads_ `some/path/input.did` and any `.did` file referenced by
`some/path/input.did`.

No constraints are imposed where these imported files reside (this may be refined to prevent relative imports from looking outside the project and the declared packages)

This _writes_ to `another/path/output.js`, but has no other effect. It does
not create `another/path/`.

Compiler warnings and errors are reported to `stderr`. Nothing writes to `stdout`.

Invoking the IDE
----------------

In order to start the language server, `dfx` invokes

    mo-ide --canister-main some/path/main.mo \
        { --package pkgname pkgpath }        \
        { --actor-alias alias url }
        [ --actor-idl actorpath ]

with `stdin` and `stdout` connected to the LSP client.

This may _read_ the same files as `moc` would.

Listing dependencies
--------------------

The command

    moc --print-deps some/path/input.mo

prints to the standard output all URLs _directly_ imported by
`some/path/input.mo`, one per line. Each line outputs the original
URL, and optionally a full path if `moc` can resolve the URL, separated by a space.
For example,

    mo:stdlib/list
    mo:other_package/Some/Module
    ic:ABCDE01A7
    canister:alias
    ./local_import some/path/local_import.mo
    ./runtime some/path/runtime.wasm

This _reads_ only `some/path/input.mo`, and writes no files.

By transitively exploring the dependency graph using this command (and
resolving URLs appropriately before passing them as files to `moc`), one can
determine the full set of set of `.mo` files read by the two compilation modes
described above (to wasm and to IDL).
