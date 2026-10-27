package union_constants

/*
 * Constants of #union structs (docs/types.md, Structs (#union)): each given member written where it is, over
 * zeros, a later one overwriting what it overlaps, with numbers, floats, arrays, a nested struct, a bool, and
 * defaults when nothing is given. main returns 42 if every constant has the bytes it should.
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

main :: fn() -> int {
    if LOW.whole != 7 { return 1 }
    if WHOLE.whole != 0x11225566 { return 2 }
    if BYTES.whole != 0x04030201 { return 3 }
    if REAL.whole != 0x3f800000 { return 4 }
    if PAIR.raw != 0x01020009 { return 5 }
    if FLAG.raw != 1 { return 6 }
    if DEFAULTED.low != 4 { return 7 }
    return 42
}
