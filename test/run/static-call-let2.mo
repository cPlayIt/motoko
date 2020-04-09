func go () {
  func foobar1() = ();
  let foobaz1 = foobar1;
  foobaz1();
};

func foobar2() = ();
let foobaz2 = foobar2;
foobaz2();

// CHECK: func $go
// CHECK-NOT: call_indirect
// CHECK: call $foobar1

// CHECK: func $start
// CHECK-NOT: call_indirect
// CHECK: call $foobar2
