package union_constants

import testing from "std"

/*
 * Constants of #union structs (docs/types.md, Structs (#union)): each given member written where it is, over
 * zeros, a later one overwriting what it overlaps, with numbers, floats, arrays, a nested struct, a bool, and
 * defaults when nothing is given.
 */

Bits :: struct #union {
    whole : u32,
    low : u16,
    bytes : u8[4],
    real : f32,
}

Pair :: struct {
    a : u8,
    b : u16,
}

Mixed :: struct #union {
    pair : Pair,
    raw : u32,
    flag : bool,
}

Defaulted :: struct #union {
    whole : u32 = 0x01020304,
    low : u8,
}

LOW :: Bits.{ low = 7 }
WHOLE :: Bits.{ whole = 0x11223344, low = 0x5566 }
BYTES :: Bits.{ bytes = u8.[1, 2, 3, 4] }
REAL :: Bits.{ real = 1.0 }
PAIR :: Mixed.{ pair = Pair.{ a = 9, b = 0x0102 } }
FLAG :: Mixed.{ flag = true }
DEFAULTED :: Defaulted.{}

writes_each_given_member_where_it_is #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, LOW.whole, 7, "a u16 given alone is the low half, over zeros")
    testing.expect_eq(t, WHOLE.whole, 0x11225566, "a later member overwrites the bytes it overlaps, and only those")
    testing.expect_eq(t, BYTES.whole, 0x04030201, "an array's bytes are in place, little-endian")
    testing.expect_eq(t, REAL.whole, 0x3f800000, "a float is written as its bits")
    testing.expect_eq(t, PAIR.raw, 0x01020009, "a nested struct is written with its padding zero")
    testing.expect_eq(t, FLAG.raw, 1, "true is the byte 1, over zeros")
    testing.expect_eq(t, DEFAULTED.low, 4, "with nothing given, the default is written, its low byte read through another member")
    return .Ok
}
