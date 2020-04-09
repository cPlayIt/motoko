import Prim "mo:prim";
actor a {

  public shared ctxt func c1 () : async () {
    let c : Principal = ctxt.caller;
    return;
  };

  public shared {caller} func c2 () : async () {
    let c1 : Principal = caller;
    return;
  };

  public shared _ func c3 () : async () {
    return;
  };

  public shared {} func c4 () : async () {
  };

  public shared {caller = c} func c5 (c:Bool) : async () { // allow shadowing
    let c1 : Bool = c;
    return;
  };

  public shared query {caller} func c6 () : async () {
    let c1 : Principal = caller;
    return;
  };

  public shared {caller} func c7() : async Principal {
    return caller;
  };

  // NB: The following tests are more about Blob than Principal
  // Maybe move to their own tests once we have intro forms for blobs

  public shared query {caller} func c8() : async Word32 {
    Prim.hashBlob (Prim.blobOfPrincipal caller);
  };

  public shared query {caller} func c9() : async Nat {
      (Prim.blobOfPrincipal caller).size();
  };

  public shared query {caller} func c10() : async ?Word8 {
      (Prim.blobOfPrincipal caller).bytes().next();
  };

};

ignore a.c1(); //OR-CALL ingress c1 0x4449444C0000
ignore a.c2(); //OR-CALL ingress c2 0x4449444C0000
ignore a.c3(); //OR-CALL ingress c3 0x4449444C0000
ignore a.c4(); //OR-CALL ingress c4 0x4449444C0000
ignore a.c6(); //OR-CALL query c6 0x4449444C0000
ignore a.c7(); //OR-CALL ingress c7 0x4449444C0000
ignore a.c8(); //OR-CALL query c8 0x4449444C0000
ignore a.c9(); //OR-CALL query c9 0x4449444C0000
ignore a.c10(); //OR-CALL query c10 0x4449444C0000



