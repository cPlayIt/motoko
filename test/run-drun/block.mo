import Prim "mo:prim";
actor a {
  public func go() {
    let a = async {
       let (a,b) = ("a1","b1"); 
       Prim.debugPrint a;
       Prim.debugPrint b;
    };

    let b = async {
       let (a,b) = await (async ("a2","b2"));
       Prim.debugPrint a;
       Prim.debugPrint b;
    };

    let c = async {
       func f(a:Text,b:Text):(){ Prim.debugPrint a; Prim.debugPrint b;};
       let (a,b) = await (async ("a3","b3"));
       let _ = f(a,b);
    };

    let d = async {
       var f = 1;
       Prim.debugPrintNat (f);
       let (a,b) = await (async ("a4","b4"));
       f += 2;
       Prim.debugPrintNat (f);
    };


    let e = async {
       var f = await (async 5);
       Prim.debugPrintNat (f);
       let (a,b) = await (async ("a5","b5"));
       f += 1;
       Prim.debugPrintNat (f);
    };
  }
};
a.go(); //OR-CALL ingress go "DIDL\x00\x00"
