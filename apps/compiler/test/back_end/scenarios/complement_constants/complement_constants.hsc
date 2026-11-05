/*
 * ~ of an untyped constant, worked out in the type it's used as (docs/operators.md, Integer operators): ~0xff with a
 * u64 is 0xffff_ffff_ffff_ff00, with a u8 0x00, and with a signed type -256, as it is untyped.
 */
package complement_constants

import testing from "std"

MASK :: 0xff
// Alone it's the untyped -256
NOT_MASK :: ~0xff
#assert NOT_MASK == -256

complements_in_the_type_it_meets #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    x : u64 = 0x1234
    y : u8 = 0xf3
    z : i32 = 0x1234
    testing.expect_eq(t, x & ~MASK, 0x1200, "with a u64, ~0xff keeps every bit above the low byte")
    testing.expect_eq(t, x | ~MASK, 0xffff_ffff_ffff_ff34, "with a u64, ~0xff sets all 56 bits above the low byte")
    testing.expect_eq(t, y & ~0x0f, 0xf0, "with a u8, ~0x0f is 0xf0")
    testing.expect_eq(t, y & ~MASK, 0, "with a u8, ~0xff has no bits left")
    testing.expect_eq(t, z & ~MASK, 0x1200, "with an i32, ~0xff is -256, every bit above the low byte")
    testing.expect_eq(t, z & NOT_MASK, 0x1200, "the untyped -256 is the same mask in an i32")
    return .Ok
}

complements_as_a_value_of_the_type #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // As a value of the type, assigned or compared
    w : u16 = ~0xff
    testing.expect_eq(t, w, 0xff00, "assigned to a u16, ~0xff is worked out in 16 bits")
    testing.expect(t, w == ~0xff, "compared with a u16, ~0xff is worked out in 16 bits too")
    testing.expect_eq(t, cast[u32](~0), 0xffff_ffff, "~0 cast to a u32 is all 32 bits")
    return .Ok
}
