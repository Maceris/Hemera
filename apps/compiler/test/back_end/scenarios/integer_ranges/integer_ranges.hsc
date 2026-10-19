/*
 * Integer literals at the edges of their types' ranges (docs/types.md, Number Formats), each
 * kept exactly, and a u64 range up to its largest value. main returns 42 if they were.
 */
package integer_ranges_test

main :: fn() -> int {
    a : u8 = 255
    b : i8 = -128
    c : i8 = 127
    d : u64 = 0xffff_ffff_ffff_ffff
    e : i64 = -9223372036854775808
    f : u32 = -0
    g : i16 = -(-5)
    h : u8 = 0b1111_1111
    i : u16 = 0o177777
    j : f32 = 300
    w : u128 = 0xffff_ffff_ffff_ffff
    v : i128 = 0xffff_ffff_ffff_ffff
    k : u8? = 200
    total : u64 = 0
    for step in cast[u64](0)..<0xffff_ffff_ffff_ffff {
        total += 1
        if total == 3 { break }
    }
    if a != 255 || b != -128 || c != 127 || d != 0xffff_ffff_ffff_ffff || e >= 0 || f != 0 || g != 5 || h != 255 || i != 65535 || j != 300 || total != 3 || w != cast[u128](d) || v != cast[i128](d) || (w >> 64) != 0 || v < 0 {
        return 1
    }
    return 42
}
