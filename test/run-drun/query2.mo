import Prim "mo:prim";
actor counter = {
  var c = 1;
  public func inc() {
    c += 1;
    Prim.debugPrintNat c;
  };
  public func printCounter () {
    Prim.debugPrintNat c;
  };
  public func get() : async Nat {
    return c
  };
  public query func read() : async Nat {
    let tmp = c;
    c += 1;
    Prim.debugPrint "In read:";
    Prim.debugPrintNat c;
    return tmp;
  };

  public func go() {
   counter.inc();
   counter.inc();
   counter.inc();
   counter.printCounter();
   let c1 = await counter.get();
   assert c1 == 4;
   let c2 = await counter.read();
   counter.printCounter();
   assert c2 == 4;
   let c3 = await counter.read();
   counter.printCounter();
   Prim.debugPrint("The following fails in the interpreter, for lack of query semantics");
   assert c3 == 4;
  };
};
counter.go(); //OR-CALL ingress go "DIDL\x00\x00"


/* Disabled, while we don’t have first-class shared functions

  { // fully explicit syntax

  let _ : actor { read : shared query () -> async Nat } = counter;

  shared query func f () : async Nat { 666; };

  type Query = shared query () -> async Nat;

  let _ : Query = counter.read;

  };

  {

  // sugar, surpressing shared

  let _ : actor { read: query () -> async Nat } = counter;

  query func f () : async Nat { 666; };

  type Query = query () -> async Nat;

  let _ : Query = counter.read;

  };
*/

