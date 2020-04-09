import Prim "mo:prim";
actor a {
  public func go() {

    var cnt : Nat = 0;
    func f(m: Text, i:Nat) : async Nat {
        Prim.debugPrint (m # " cnt: " # debug_show cnt # " i: " # debug_show i);
        cnt += 1;
        cnt;
    };



    let e = async {
        var i = 5;
        Prim.debugPrint "  e-while\n";
        while (i < 10) {
            let _ = await f("  e",i);
            i += 1;
        };
        Prim.debugPrint "  e-exit\n";
    };

    Prim.debugPrint "g";

    let g = async {
        var i = 10;
        Prim.debugPrint "g-label\n";
        label lp
        while (true) {
            if (i < 15) {
                let _ = await f("g",i);
                i += 1;
                continue lp;
            } else {};
            break lp;
        };
        Prim.debugPrint "g-exit\n";
    };

  }
};
a.go(); //OR-CALL ingress go "DIDL\x00\x00"
