/*
 * Endian-specific integers and floats (docs/types.md, Endian-Specific Types): stored in their own byte order, read
 * as their native types, computed with as those, and stored with a cast. main returns 42 if they all held, or the
 * number of the first that didn't.
 */
package endian_types

// A header as a wire format lays it out: a byte, a big-endian length, a little-endian flags field
Header :: struct #packed {
    kind : u8,
    length : u32be,
    flags : u16le,
}

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

// Through a parameter of the native type, which the endian value converts to
twice :: fn(value: u32) -> u32 {
    return value * 2
}

main :: fn() -> int {
    errors := 0
    big : u32be = 0x01020304
    bytes := bit_cast[u8[4]](big)
    errors += check(bytes[0] == 1 && bytes[1] == 2 && bytes[2] == 3 && bytes[3] == 4, 1)
    little : u32le = 0x01020304
    little_bytes := bit_cast[u8[4]](little)
    errors += check(little_bytes[0] == 4 && little_bytes[3] == 1, 2)
    native : u32 = big
    errors += check(native == 0x01020304, 3)
    wide : u64 = big
    errors += check(wide == 0x01020304, 4)
    sum := big + 1
    errors += check(sum == 0x01020305, 5)
    errors += check(big == cast[u32be](native) && big != cast[u32be](sum), 6)
    errors += check(big < 0x01020305 && big > 0x01020303, 7)
    back : u32be = cast[u32be](sum)
    back_bytes := bit_cast[u8[4]](back)
    errors += check(back_bytes[3] == 5, 8)
    errors += check(twice(big) == 0x02040608, 9)
    signed : i16be = -2
    signed_bytes := bit_cast[u8[2]](signed)
    errors += check(signed_bytes[0] == 0xff && signed_bytes[1] == 0xfe, 10)
    widened : i64 = signed
    errors += check(widened == -2, 11)
    float : f32be = 1.0
    float_bytes := bit_cast[u8[4]](float)
    errors += check(float_bytes[0] == 0x3f && float_bytes[1] == 0x80 && float_bytes[3] == 0, 12)
    double : f64 = float
    errors += check(double == 1.0, 13)
    header : Header
    header.kind = 7
    header.length = 300
    header.flags = cast[u16le](0x0102)
    header_bytes := bit_cast[u8[7]](header)
    errors += check(size_of(Header) == 7 && header_bytes[0] == 7 && header_bytes[1] == 0 && header_bytes[3] == 1
        && header_bytes[4] == 0x2c && header_bytes[5] == 2 && header_bytes[6] == 1, 14)
    errors += check(header.length + 1 == 301, 15)
    if errors == 0 {
        return 42
    }
    return errors
}
