/*
 * ~ of an untyped constant, worked out in the type it's used as (docs/operators.md, Integer operators): ~0xff with a
 * u64 is 0xffff_ffff_ffff_ff00, with a u8 0x00, and with a signed type -256, as it is untyped. main returns 42 if they
 * all held, or the number of the first that didn't.
 */
package complement_constants

MASK :: 0xff
// Alone it's the untyped -256
NOT_MASK :: ~0xff
#assert NOT_MASK == -256

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

main :: fn() -> int {
    errors := 0
    x : u64 = 0x1234
    y : u8 = 0xf3
    z : i32 = 0x1234
    errors += check(x & ~MASK == 0x1200 && (x | ~MASK) == 0xffff_ffff_ffff_ff34, 1)
    errors += check(y & ~0x0f == 0xf0 && y & ~MASK == 0, 2)
    errors += check(z & ~MASK == 0x1200 && z & NOT_MASK == 0x1200, 3)
    // As a value of the type, assigned or compared
    w : u16 = ~0xff
    errors += check(w == 0xff00 && w == ~0xff, 4)
    errors += check(cast[u32](~0) == 0xffff_ffff, 5)
    if errors == 0 {
        return 42
    }
    return errors
}
