import Prim "mo:prim";

func f():() -> Int {
  { label exit : (() -> Int) {
      func g() : Int = x; // reference x
      break exit (func() : Int{ g(); }); // early exit omits definition of x
      let x:Int = 666;
      func():Int{777;};
    }
  };
};

Prim.debugPrint "1";
let h = f();

Prim.debugPrint "2";
let wrong = h();
