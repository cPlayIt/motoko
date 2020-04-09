import Prim "mo:prim";
/* test n-ary async/await */

actor a {
  /* n-ary args */
  public func f0_0() : async () {};
  public func f1_0(x:Int) : async () {
    assert(x == 1);
  };
  public func f2_0(x:Int,y:Bool) : async () {
    assert(x==1);
    assert(y==true);
  };
  public func f3_0(x:Int,y:Bool,z:Text) : async () {
    assert(x == 1);
    assert(y == true);
    assert(z == "a");
  };

  public func go1() {
    {
      let t = "0_0";
      ignore async {
        await f0_0();
        Prim.debugPrint t;
      };
    };

    {
      let t = "1_0";
      ignore async {
        await f1_0(1);
        Prim.debugPrint t;
      };
    };

    {
      let t = "2_0";
      ignore async {
        await f2_0(1,true);
        Prim.debugPrint t;
      };
    };

    {
    let t = "3_0";
      ignore async {
        await f3_0(1,true,"a");
        Prim.debugPrint t;
      };
    };
  };

  /* n-ary returns */
  public func g0_0() : async () {};
  public func g0_1() : async Int {
     1;
  };
  public func g0_2() : async (Int,Bool) {
     (1,true);
  };
  public func g0_3() : async (Int,Bool,Text) {
     (1,true,"a");
  };

  public func go2() {
    {
      let t = "0_0";
      ignore async {
        await g0_0();
        Prim.debugPrint t;
      };
    };

    {
      let t = "0_1";
      ignore async {
        let x = await g0_1();
        assert(x == 1);
        Prim.debugPrint t;
        x;
      };
    };

    {
      let t = "0_2";
      ignore async {
        let (x,y) = await g0_2();
        assert(x==1);
        assert(y==true);
        Prim.debugPrint t;
        (x,y);
      };
    };


    {
      let t = "0_3";
      ignore async {
        let (x,y,z) = await g0_3();
        assert(x==1);
        assert(y==true);
        assert(z=="a");
        Prim.debugPrint t;
        (x,y,z);
      };
    };
  };
};

a.go1(); //OR-CALL ingress go1 "DIDL\x00\x00"
a.go2(); //OR-CALL ingress go2 "DIDL\x00\x00"
