import Prim "mo:prim";

//MOC-FLAG --release

Prim.debugPrint "This should appear";
debug { Prim.debugPrint "This shouldn't appear" };
Prim.debugPrint "This should appear too";

