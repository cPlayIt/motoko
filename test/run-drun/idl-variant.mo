import Prim "mo:prim";

type Either = { #left: Word32; #right: Char; #fix: Either };

func to_left(e : Either) : Either
  = switch e {
      case (#right n) #left (Prim.charToWord32 n);
      case (#fix t) #fix (to_left t);
      case other other
    };

actor {
  public query func numify(t: Either) : async Either {
    to_left t
  }
}

//CALL query numify 0x4449444c016b03d583b702008790c0bd0479dc9790cb0e790100000220000000

//SKIP run
//SKIP run-ir
//SKIP run-low
