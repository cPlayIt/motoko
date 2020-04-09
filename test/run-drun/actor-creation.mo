import Prim "mo:prim";
Prim.debugPrint ("main actor creating a");
actor a {
  public func foo() {
    Prim.debugPrint ("a.foo() called");

    Prim.debugPrint ("a creating b");
    actor b {
      public func foo() {
      Prim.debugPrint ("b.foo() called");
    };
    Prim.debugPrint ("b created");
    };

    Prim.debugPrint ("a calling b.foo()");
    b.foo();
    Prim.debugPrint ("a.foo() done");
  };

  Prim.debugPrint ("a created");
};

a.foo(); //OR-CALL ingress foo "DIDL\x00\x00"
// certainly won’t work on drun
//SKIP comp
//SKIP comp-ref
