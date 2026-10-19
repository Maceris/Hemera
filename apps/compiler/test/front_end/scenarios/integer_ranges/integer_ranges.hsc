/*
 * Integer literals out of range of the type they become (docs/types.md, Number Formats): given a
 * type, defaulting to int, as a range's bound, beside a typed operand, and too large for any integer.
 */
package integer_ranges

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
    // In range
    fine : u8 = 255
    lowest : i8 = -128
    widest : u64 = 0xffff_ffff_ffff_ffff
    return 0
}
