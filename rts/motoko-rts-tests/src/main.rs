#![feature(ptr_offset_from)]

mod bigint;
mod closure_table;
mod crc32;
mod leb128;
mod principal_id;
mod text;
mod utf8;

use motoko_rts::types::*;

fn main() {
    if std::mem::size_of::<usize>() != 4 {
        println!("Motoko RTS only works on 32-bit architectures");
        std::process::exit(1);
    }

    unsafe {
        closure_table::test();
        bigint::test();
        utf8::test();
        crc32::test();
        principal_id::test();
        text::test();
        leb128::test();
    }
}

// Called by the RTS to panic
#[no_mangle]
extern "C" fn rts_trap(_msg: *const u8, _len: Bytes<u32>) -> ! {
    panic!("rts_trap_with called");
}

// Called by RTS BigInt functions to panic. Normally generated by the compiler
#[no_mangle]
extern "C" fn bigint_trap() -> ! {
    panic!("bigint_trap called");
}

// Called by the RTS for debug prints
#[no_mangle]
unsafe extern "C" fn print_ptr(ptr: usize, len: u32) {
    let str: &[u8] = core::slice::from_raw_parts(ptr as *const u8, len as usize);
    println!("[RTS] {}", String::from_utf8_lossy(str));
}
