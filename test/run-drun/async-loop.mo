import Prim "mo:prim";
actor a {
  public func go() {
    { var i = 0;
      var j = 0;
      label l
      loop {
       Prim.debugPrintNat(j);
       assert(j == i);
       i += 1;
       j += 1;
       if (j == 3) break l else continue l;
      } ;
      assert(i == 3);
    };


    {
      var i = 0;
      var j = 0;
      label l
      loop {
        Prim.debugPrintNat(j);
        assert(j == i);
        i += 1;
        j += 1;
        if (await async (j == 3)) break l else continue l;
        assert(false);
      };
      assert(i == 3);
    };

    {
      var i = 0;
      var j = 0;
      label l
      loop {
       Prim.debugPrintNat(j);
       assert(j == i);
       await (async (i += 1));
       j += 1;
       if (j == 3) break l else continue l;
       assert(false);
      };
      assert(i == 3);
    };

    {
      var i = 0;
      var j = 0;
      label l
      loop {
       if (j > 2) {
         break l;
         assert(false);
       };
       Prim.debugPrintNat(j);
       assert(j == i);
       await (async (i += 1));
       j += 1;
       continue l;
       assert(false);
      };
      assert(i == 3);
    };
  };
};
