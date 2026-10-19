/*
 * Integer literals at the edges of their types' ranges (docs/types.md, Number Formats), each
 * kept exactly, and a u64 range up to its largest value. Operators on known integers and named
 * constants, worked out and generated as one constant each, so 512 / 4 is 128 as a u8, not worked out
 * in a u8. main returns 42 if they were.
 */
package integer_ranges_test

QUARTER :: 512 / 4
BIG :: 1 << 40
NEG :: -300
MASK :: 0xff00 >> 8

check_folded :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

// 0 if every known integer was worked out the way docs/operators.md defines its operator
folded :: fn() -> int {
    a : u8 = 512 / 4
    b : u8 = QUARTER
    c : u8 = 300 - 100
    d : i8 = -7 / 2
    e : i8 = -7 % 2
    f : i8 = -7 %% 2
    g : i8 = 7 %% -2
    h : i8 = -5 >> 1
    i : u8 = MASK
    j : u64 = BIG
    k : i16 = NEG
    l : i8 = ~5
    m : u8 = ~-6
    n : u8 = 0xf0 | 0x0f
    o : u8 = 0x1f0 & 0xff
    p : u8 = 0x1ff ~ 0x100
    q : f32 = 3 * 100
    r : u8 = 255 + 1 - 1
    s : u64 = 0xffff_ffff_ffff_ffff - 1 + 1
    t : i64 = -9223372036854775807 - 1
    errors := 0
    errors += check_folded(a == 128, 1)
    errors += check_folded(b == 128, 2)
    errors += check_folded(c == 200, 3)
    errors += check_folded(d == -3, 4)
    errors += check_folded(e == -1, 5)
    errors += check_folded(f == 1, 6)
    errors += check_folded(g == -1, 7)
    errors += check_folded(h == -3, 8)
    errors += check_folded(i == 255, 9)
    errors += check_folded(j == 1099511627776, 10)
    errors += check_folded(k == -300, 11)
    errors += check_folded(l == -6, 12)
    errors += check_folded(m == 5, 13)
    errors += check_folded(n == 255, 14)
    errors += check_folded(o == 240, 15)
    errors += check_folded(p == 255, 16)
    errors += check_folded(q == 300, 17)
    errors += check_folded(r == 255, 18)
    errors += check_folded(s == 0xffff_ffff_ffff_ffff, 19)
    errors += check_folded(t < 0 && t + 1 == -9223372036854775807, 20)
    return errors
}

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
    if folded() != 0 {
        return 100 + folded()
    }
    return 42
}
