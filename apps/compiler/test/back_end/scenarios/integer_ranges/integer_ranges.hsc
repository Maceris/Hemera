/*
 * Integer literals at the edges of their types' ranges (docs/types.md, Number Formats), each
 * kept exactly, and a u64 range up to its largest value. Operators on known integers and named
 * constants, worked out and generated as one constant each, so 512 / 4 is 128 as a u8, not worked out
 * in a u8.
 */
package integer_ranges_test

import testing from "std"

/** 128, a constant too large for a u8's parts but not for a u8 once worked out. */
QUARTER :: 512 / 4
/** 2^40, past 32 bits. */
BIG :: 1 << 40
/** A negative constant, given to an i16. */
NEG :: -300
/** 255, from a shift of a constant wider than a u8. */
MASK :: 0xff00 >> 8

keeps_literals_at_their_types_edges #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
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
    testing.expect_eq(t, a, 255, "a u8's largest value")
    testing.expect_eq(t, b, -128, "an i8's smallest value")
    testing.expect_eq(t, c, 127, "an i8's largest value")
    testing.expect_eq(t, d, 0xffff_ffff_ffff_ffff, "a u64's largest value")
    testing.expect(t, e < 0, "an i64's smallest value is kept negative, not wrapped")
    testing.expect_eq(t, f, 0, "-0 is 0, in range of an unsigned type")
    testing.expect_eq(t, g, 5, "a negated negative is positive")
    testing.expect_eq(t, h, 255, "eight binary ones")
    testing.expect_eq(t, i, 65535, "sixteen bits in octal")
    testing.expect_eq(t, j, 300, "an integer literal given to a float")
    testing.expect_eq(t, w, cast[u128](d), "a u128 holds a u64's largest value exactly")
    testing.expect_eq(t, v, cast[i128](d), "an i128 holds a u64's largest value exactly")
    testing.expect_eq(t, w >> 64, 0, "the u128 has nothing above its low 64 bits")
    testing.expect(t, v >= 0, "an i128 is wide enough that a u64's largest value is positive in it")
    return .Ok
}

ranges_up_to_a_u64s_largest_value #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    total : u64 = 0
    for step in cast[u64](0)..<0xffff_ffff_ffff_ffff {
        total += 1
        if total == 3 { break }
    }
    testing.expect_eq(t, total, 3, "a range to a u64's largest value is a range, run until it's left")
    return .Ok
}

folds_operators_on_known_integers #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
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
    u : i64 = -9223372036854775807 - 1
    // docs/operators.md defines each operator these are worked out with
    testing.expect_eq(t, a, 128, "512 / 4 is worked out before it's a u8")
    testing.expect_eq(t, b, 128, "a named constant is worked out the same way")
    testing.expect_eq(t, c, 200, "300 - 100 is in range once worked out")
    testing.expect_eq(t, d, -3, "/ truncates toward zero")
    testing.expect_eq(t, e, -1, "% takes the dividend's sign")
    testing.expect_eq(t, f, 1, "%% takes the divisor's sign")
    testing.expect_eq(t, g, -1, "%% with a negative divisor is negative")
    testing.expect_eq(t, h, -3, ">> of a negative shifts in its sign, rounding down")
    testing.expect_eq(t, i, 255, "0xff00 >> 8 is in a u8's range")
    testing.expect_eq(t, j, 1099511627776, "1 << 40 is worked out wider than 32 bits")
    testing.expect_eq(t, k, -300, "a negative named constant in an i16")
    testing.expect_eq(t, l, -6, "~5 is -6 in two's complement")
    testing.expect_eq(t, m, 5, "~-6 is 5")
    testing.expect_eq(t, n, 255, "| of the two halves of a byte")
    testing.expect_eq(t, o, 240, "& keeps the bits both have, cutting 0x1f0 to a byte")
    testing.expect_eq(t, p, 255, "~ between two values is exclusive or")
    testing.expect_eq(t, q, 300, "an integer product given to a float")
    testing.expect_eq(t, r, 255, "255 + 1 - 1 is in range once worked out, though 256 isn't")
    testing.expect_eq(t, s, 0xffff_ffff_ffff_ffff, "a u64's largest value less 1 and plus 1 again")
    testing.expect(t, u < 0, "an i64's smallest value, made by subtracting, is negative")
    testing.expect_eq(t, u + 1, -9223372036854775807, "one above an i64's smallest value")
    return .Ok
}
