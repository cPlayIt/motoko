import Prim "mo:prim";
actor {
  // top-level tuple
  public query func len2(x:Text, y:Text) : async (Int,Int) {
    (x.len(), y.len())
  };
  // a pair embedded in top-level tuple
  public query func len3((x:Text, i:Int32), y:Text) : async (Int,Int,Int) {
    (x.len(), y.len(), Prim.int32ToInt i)
  };
  // a triple embedded in top-level tuple
  public query func len3a((x:Text, i:Int32, z:?(Text,Int32)), y:Text) : async (Int,Int,Int) {
    (x.len(), y.len(), Prim.int32ToInt i)
  }
}

//CALL query len2 "DIDL\x00\x02\x71\x71\x02Hi\x05World"
//CALL query len3 0x4449444c016c02007101750200710548656c6c6f0102030405576f726c64
//CALL query len3a 0x4449444c036c02007101756c030071017502026e000201710548656c6c6f010203040005576f726c64
//  testing redundant first tuple member (repeated hash with different type), currently ignored, it is although invalid IDL data
//CALL query len3 0x4449444c016c030071007601750200710548656c6c6fdead0102030405576f726c64
//  testing redundant third tuple member, gets ignored
//CALL query len3 0x4449444c016c030071017502760200710548656c6c6f01020304dead05576f726c64
//  testing third tuple member (recursive option, containing null), gets ignored
//CALL query len3a 0x4449444c026c030071017502016e000200710548656c6c6f010203040005576f726c64

//SKIP run
//SKIP run-ir
//SKIP run-low
