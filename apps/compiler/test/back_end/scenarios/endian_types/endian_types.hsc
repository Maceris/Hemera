/*
 * Endian-specific integers and floats (docs/types.md, Endian-Specific Types): stored in their own byte order, read
 * as their native types, computed with as those, and stored with a cast.
 */
package endian_types

import testing from "std"

/** A header as a wire format lays it out: a byte, a big-endian length, a little-endian flags field. */
Header :: struct #packed {
    /** What the header is for; any value. */
    kind : u8,
    /** How long what follows is, in bytes. */
    length : u32be,
    /** Flags; any bits. */
    flags : u16le,
}

/**
 * Double a value, through a parameter of the native type, which an endian value converts to.
 *
 * @param value The value; wraps past u32's range.
 * @return Twice value.
 */
twice :: fn(value: u32) -> u32 {
    return value * 2
}

stores_in_their_own_byte_order #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    big : u32be = 0x01020304
    bytes := bit_cast[u8[4]](big)
    testing.expect_eq(t, bytes, u8.[1, 2, 3, 4], "big-endian puts the most significant byte first")
    little : u32le = 0x01020304
    little_bytes := bit_cast[u8[4]](little)
    testing.expect_eq(t, little_bytes[0], 4, "little-endian puts the least significant byte first")
    testing.expect_eq(t, little_bytes[3], 1, "and the most significant last")
    signed : i16be = -2
    signed_bytes := bit_cast[u8[2]](signed)
    testing.expect_eq(t, signed_bytes[0], 0xff, "-2 in two's complement is 0xfffe, high byte first")
    testing.expect_eq(t, signed_bytes[1], 0xfe, "then the low byte")
    float : f32be = 1.0
    float_bytes := bit_cast[u8[4]](float)
    testing.expect_eq(t, float_bytes[0], 0x3f, "1.0 is 0x3f800000, sign and exponent first")
    testing.expect_eq(t, float_bytes[1], 0x80, "the exponent's last bit")
    testing.expect_eq(t, float_bytes[3], 0, "no fraction bits")
    return .Ok
}

reads_as_their_native_types #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    big : u32be = 0x01020304
    native : u32 = big
    testing.expect_eq(t, native, 0x01020304, "assigned to a u32, the value is the same")
    wide : u64 = big
    testing.expect_eq(t, wide, 0x01020304, "widened, the value is the same")
    signed : i16be = -2
    widened : i64 = signed
    testing.expect_eq(t, widened, -2, "a signed one widens with its sign")
    float : f32be = 1.0
    double : f64 = float
    testing.expect_eq(t, double, 1.0, "a float widens to the same value")
    return .Ok
}

computes_as_their_native_types #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    big : u32be = 0x01020304
    native : u32 = big
    sum := big + 1
    testing.expect_eq(t, sum, 0x01020305, "adding one adds to the value, not the first byte")
    testing.expect(t, big == cast[u32be](native), "the native value cast back is equal")
    testing.expect(t, big != cast[u32be](sum), "a different value cast is not")
    testing.expect_lt(t, big, 0x01020305, "compared by value, it's below the next")
    testing.expect_gt(t, big, 0x01020303, "and above the one before")
    back : u32be = cast[u32be](sum)
    back_bytes := bit_cast[u8[4]](back)
    testing.expect_eq(t, back_bytes[3], 5, "cast back to big-endian, the low byte is last")
    testing.expect_eq(t, twice(big), 0x02040608, "passed as a u32, it's the value that's doubled")
    return .Ok
}

lays_out_a_packed_wire_header #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    header : Header
    header.kind = 7
    header.length = 300
    header.flags = cast[u16le](0x0102)
    header_bytes := bit_cast[u8[7]](header)
    testing.expect_eq(t, size_of(Header), 7, "packed, there's no padding between a byte, four and two")
    testing.expect_eq(t, header_bytes[0], 7, "kind comes first")
    testing.expect_eq(t, header_bytes[1], 0, "300 is 0x0000012c, its high byte first")
    testing.expect_eq(t, header_bytes[3], 1, "300's second byte from the bottom")
    testing.expect_eq(t, header_bytes[4], 0x2c, "300's low byte, last of the length")
    testing.expect_eq(t, header_bytes[5], 2, "flags' low byte comes first")
    testing.expect_eq(t, header_bytes[6], 1, "then flags' high byte")
    testing.expect_eq(t, header.length + 1, 301, "a field reads as its native value")
    return .Ok
}
