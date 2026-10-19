/*
 * Integer literals out of range of the type they become (docs/types.md, Number Formats): given a
 * type, defaulting to int, as a range's bound, beside a typed operand, and too large for any integer.
 * Operators on known integers are worked out, and named constants keep their values, so they're
 * checked too; so is dividing by a known zero.
 */
package integer_ranges

LARGE :: 300
SHIFTED :: 1 << 8

takes_byte :: fn(b: u8) -> u8 { return b }
gives_small :: fn() -> i8 { return 128 }

Small :: struct { b: u8 }

main :: fn() -> int {
    small : u8 = 300
    negative : u32 = -1
    too_low : i8 = -129
    big := 0xffff_ffff_ffff_ffff
    for step in 0..<0xffff_ffff_ffff_ffff {}
    huge : u64 = 0x1_0000_0000_0000_0000
    _ = takes_byte(256)
    s := Small.{b = 256}
    sum := small + 300
    small += 256
    folded : u8 = 255 + 1
    named : u8 = LARGE
    named_shift : u8 = SHIFTED
    product : i8 = 100 * 2
    difference : u32 = 1 - 2
    overflowing := 0xffff_ffff_ffff_ffff * 2
    too_far := 1 << 64
    by_zero := 10 / 0
    n : int = 5
    typed_by_zero := n % 0
    negated : i8 = -(LARGE)
    // In range
    fine : u8 = 255
    lowest : i8 = -128
    widest : u64 = 0xffff_ffff_ffff_ffff
    quarter : u8 = 512 / 4
    back_down : u8 = 255 + 1 - 1
    return 0
}
