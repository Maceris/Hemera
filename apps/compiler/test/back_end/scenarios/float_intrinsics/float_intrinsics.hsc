package float_intrinsics

import intrinsics from "base"
import runtime from "base"
import testing from "std"

/*
 * base/intrinsics' float and bit-count functions (docs/types.md, Floats). Built for a CPU without SSE4.1 and FMA, they
 * round by adding and fuse in software (runtime.fused_multiply_add_f64 and _f32); built for one with them, by their
 * instructions, and the software is held to the instruction there, bit for bit.
 */

/** One number and what each rounding gives, as f64s. */
Rounding :: struct {
    x : f64,
    floor : f64,
    ceil : f64,
    trunc : f64,
    round_even : f64,
}

/** Bit for bit, so -0 isn't +0, and any NaN is any other. */
same :: fn(a: f64, b: f64) -> bool {
    return (a != a && b != b) || bit_cast[u64](a) == bit_cast[u64](b)
}

/** The same for f32s. */
same_32 :: fn(a: f32, b: f32) -> bool {
    return (a != a && b != b) || bit_cast[u32](a) == bit_cast[u32](b)
}

/** An f64's bits, any NaN's as one quiet NaN's, so expect_eq tells -0 from +0 and takes NaNs as equal. */
bits :: fn(x: f64) -> u64 {
    return if x != x { 0x7ff8_0000_0000_0000 } else { bit_cast[u64](x) }
}

/** The same for f32s. */
bits_32 :: fn(x: f32) -> u32 {
    return if x != x { 0x7fc0_0000 } else { bit_cast[u32](x) }
}

ROUNDINGS :: Rounding.[
    Rounding.{x = 0, floor = 0, ceil = 0, trunc = 0, round_even = 0},
    Rounding.{x = -0.0, floor = -0.0, ceil = -0.0, trunc = -0.0, round_even = -0.0},
    Rounding.{x = 0.5, floor = 0, ceil = 1, trunc = 0, round_even = 0},
    Rounding.{x = -0.5, floor = -1, ceil = -0.0, trunc = -0.0, round_even = -0.0},
    Rounding.{x = 1.5, floor = 1, ceil = 2, trunc = 1, round_even = 2},
    Rounding.{x = -1.5, floor = -2, ceil = -1, trunc = -1, round_even = -2},
    Rounding.{x = 2.5, floor = 2, ceil = 3, trunc = 2, round_even = 2},
    Rounding.{x = -2.5, floor = -3, ceil = -2, trunc = -2, round_even = -2},
    Rounding.{x = 0.7, floor = 0, ceil = 1, trunc = 0, round_even = 1},
    Rounding.{x = -0.3, floor = -1, ceil = -0.0, trunc = -0.0, round_even = -0.0},
    Rounding.{x = 3, floor = 3, ceil = 3, trunc = 3, round_even = 3},
    Rounding.{x = -7, floor = -7, ceil = -7, trunc = -7, round_even = -7},
    // 2^52 - 0.5, the last with a half, and 2^52 + 2, whole
    Rounding.{x = 4503599627370495.5, floor = 4503599627370495, ceil = 4503599627370496, trunc = 4503599627370495,
        round_even = 4503599627370496},
    Rounding.{x = 4503599627370498, floor = 4503599627370498, ceil = 4503599627370498, trunc = 4503599627370498,
        round_even = 4503599627370498},
    Rounding.{x = -4503599627370495.5, floor = -4503599627370496, ceil = -4503599627370495, trunc = -4503599627370495,
        round_even = -4503599627370496},
    Rounding.{x = 1e300, floor = 1e300, ceil = 1e300, trunc = 1e300, round_even = 1e300},
    Rounding.{x = 1e-300, floor = 0, ceil = 1, trunc = 0, round_even = 0},
    Rounding.{x = -1e-300, floor = -1, ceil = -0.0, trunc = -0.0, round_even = -0.0},
]

rounds_f64s_as_ieee_754_says #test(ROUNDINGS) :: fn(t: ptr[mut testing.T], item: Rounding) -> testing.Outcome {
    testing.expect_eq(t, bits(intrinsics.floor(item.x)), bits(item.floor), "floor: %{x} against %{x}")
    testing.expect_eq(t, bits(intrinsics.ceil(item.x)), bits(item.ceil), "ceil: %{x} against %{x}")
    testing.expect_eq(t, bits(intrinsics.trunc(item.x)), bits(item.trunc), "trunc: %{x} against %{x}")
    testing.expect_eq(t, bits(intrinsics.round_even(item.x)), bits(item.round_even), "round_even: %{x} against %{x}")
    return .Ok
}

rounds_infinities_and_nans_to_themselves #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    infinity :: bit_cast[f64](cast[u64](0x7ff0_0000_0000_0000))
    nan :: bit_cast[f64](cast[u64](0x7ff8_0000_0000_0000))
    for x in f64.[infinity, -infinity] {
        testing.expect(t, same(intrinsics.floor(x), x) && same(intrinsics.ceil(x), x) && same(intrinsics.trunc(x), x)
            && same(intrinsics.round_even(x), x), "an infinity stays itself")
    }
    testing.expect(t, intrinsics.floor(nan) != intrinsics.floor(nan), "a NaN stays a NaN")
    testing.expect(t, intrinsics.round_even(nan) != intrinsics.round_even(nan), "a NaN stays a NaN")
    return .Ok
}

/** Every f32 rounding agrees with the f64 one on the same number, which is exact in both. */
rounds_f32s_as_f64s_do #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    x :: bit_cast[f32](testing.draw[u32](source))
    wide :: cast[f64](x)
    testing.expect_eq(t, bits_32(intrinsics.floor(x)), bits_32(cast[f32](intrinsics.floor(wide))), "floor: %{x} against %{x}")
    testing.expect_eq(t, bits_32(intrinsics.ceil(x)), bits_32(cast[f32](intrinsics.ceil(wide))), "ceil: %{x} against %{x}")
    testing.expect_eq(t, bits_32(intrinsics.trunc(x)), bits_32(cast[f32](intrinsics.trunc(wide))), "trunc: %{x} against %{x}")
    testing.expect_eq(t, bits_32(intrinsics.round_even(x)), bits_32(cast[f32](intrinsics.round_even(wide))),
        "round_even: %{x} against %{x}")
    return .Ok
}

/** 2^23 - 0.5, halfway, and 2^23 - 1.5, rounded to even in f32. */
rounds_f32s_near_where_they_are_whole #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, intrinsics.round_even(cast[f32](8388607.5)) == 8388608, "8388607.5 to even")
    testing.expect(t, intrinsics.round_even(cast[f32](8388606.5)) == 8388606, "8388606.5 to even")
    testing.expect(t, intrinsics.floor(cast[f32](8388607.5)) == 8388607, "8388607.5 down")
    testing.expect(t, intrinsics.ceil(cast[f32](-8388607.5)) == -8388607, "-8388607.5 up")
    return .Ok
}

rounds_vectors_lane_by_lane #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    v :: vector[f32, 4].{-1.5, -0.5, 0.5, 2.5}
    testing.expect(t, intrinsics.all_true(intrinsics.floor(v) == vector[f32, 4].{-2, -1, 0, 2}), "floor")
    testing.expect(t, intrinsics.all_true(intrinsics.ceil(v) == vector[f32, 4].{-1, 0, 1, 3}), "ceil")
    testing.expect(t, intrinsics.all_true(intrinsics.trunc(v) == vector[f32, 4].{-1, 0, 0, 2}), "trunc")
    testing.expect(t, intrinsics.all_true(intrinsics.round_even(v) == vector[f32, 4].{-2, 0, 0, 2}), "round_even")
    w :: vector[f64, 2].{-2.5, 9}
    testing.expect(t, intrinsics.all_true(intrinsics.square_root(intrinsics.copy_sign(w, vector[f64, 2].{1, 1})) == vector[f64, 2].{
        intrinsics.square_root(2.5), 3}), "square_root and copy_sign")
    testing.expect(t, intrinsics.all_true(intrinsics.fused_multiply_add(w, w, w) == vector[f64, 2].{3.75, 90}), "fused_multiply_add")
    return .Ok
}

takes_the_least_and_greatest_as_ieee_754_2019_does #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    nan :: bit_cast[f64](cast[u64](0x7ff8_0000_0000_0000))
    testing.expect(t, intrinsics.minimum(1.0, 2.0) == 1 && intrinsics.maximum(1.0, 2.0) == 2, "numbers")
    testing.expect(t, intrinsics.minimum(nan, 2.0) != intrinsics.minimum(nan, 2.0), "a NaN wins the least")
    testing.expect(t, intrinsics.maximum(2.0, nan) != intrinsics.maximum(2.0, nan), "and the greatest")
    testing.expect(t, same(intrinsics.minimum(0.0, -0.0), -0.0) && same(intrinsics.minimum(-0.0, 0.0), -0.0), "-0 is less")
    testing.expect(t, same(intrinsics.maximum(0.0, -0.0), 0) && same(intrinsics.maximum(-0.0, 0.0), 0), "+0 is greater")
    testing.expect(t, same(intrinsics.copy_sign(2.0, -0.0), -2) && same(intrinsics.copy_sign(-3.0, 1.0), 3), "copy_sign")
    small :: vector[f32, 4].{1, -2, 3, -4}
    testing.expect(t, intrinsics.all_true(intrinsics.minimum(small, -small) == vector[f32, 4].{-1, -2, -3, -4}), "lane by lane")
    return .Ok
}

fuses_with_one_rounding #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // 0.1 × 10 rounds to exactly 1, so * then + gives 0; fused, what 0.1 lacks of a tenth shows
    tenth : f64 = 0.1
    testing.expect(t, tenth * 10 - 1 == 0, "unfused, the error's lost")
    testing.expect(t, intrinsics.fused_multiply_add(tenth, 10.0, -1.0) == 5.551115123125783e-17, "fused, it's kept")
    testing.expect(t, runtime.fused_multiply_add_f64(tenth, 10, -1) == 5.551115123125783e-17, "in software too")
    tenth_32 : f32 = 0.1
    testing.expect(t, runtime.fused_multiply_add_f32(tenth_32, 10, -1) == intrinsics.fused_multiply_add(tenth_32, 10.0, -1.0),
        "and in f32")
    testing.expect(t, runtime.fused_multiply_add_f32(tenth_32, 10, -1) == cast[f32](cast[f64](tenth_32) * 10 - 1), "exactly")
    return .Ok
}

/** An f64 drawn to land anywhere, sometimes near what cancels the product, for software against hardware. */
draw_triple :: fn(source: ptr[mut testing.Source]) -> f64[3] {
    x := bit_cast[f64](testing.draw[u64](source))
    y := bit_cast[f64](testing.draw[u64](source))
    z := bit_cast[f64](testing.draw[u64](source))
    match testing.draw_below(source, 4) {
        case 0 => {
            // Exponents near each other, so the sum isn't just the bigger
            x = bit_cast[f64]((bit_cast[u64](x) & 0x800f_ffff_ffff_ffff) | (cast[u64](testing.draw_between(source, 900, 1100)) << 52))
            y = bit_cast[f64]((bit_cast[u64](y) & 0x800f_ffff_ffff_ffff) | (cast[u64](testing.draw_between(source, 900, 1100)) << 52))
            z = -(x * y) * (1 + cast[f64](testing.draw_between(source, -8, 8)) * 1e-16)
        }
        case 1 => {
            // Results near the subnormals
            x = bit_cast[f64]((bit_cast[u64](x) & 0x800f_ffff_ffff_ffff) | (cast[u64](testing.draw_between(source, 400, 600)) << 52))
            y = bit_cast[f64]((bit_cast[u64](y) & 0x800f_ffff_ffff_ffff) | (cast[u64](testing.draw_between(source, 400, 600)) << 52))
            z = bit_cast[f64](testing.draw_below(source, 0x0030_0000_0000_0000) | (bit_cast[u64](z) & 0x8000_0000_0000_0000))
        }
        case _ => {}
    }
    return f64.[x, y, z]
}

fuses_f64s_in_software_as_the_instruction_does #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    xyz :: draw_triple(source)
    hardware :: intrinsics.fused_multiply_add(xyz[0], xyz[1], xyz[2])
    software :: runtime.fused_multiply_add_f64(xyz[0], xyz[1], xyz[2])
    testing.expect_eq(t, bits(software), bits(hardware), "software %{x}, hardware %{x}")
    return .Ok
}

fuses_f32s_in_software_as_the_instruction_does #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    x :: bit_cast[f32](testing.draw[u32](source))
    y :: bit_cast[f32](testing.draw[u32](source))
    z := bit_cast[f32](testing.draw[u32](source))
    if testing.draw_bool(source) {
        z = cast[f32](-(cast[f64](x) * cast[f64](y)))
    }
    hardware :: intrinsics.fused_multiply_add(x, y, z)
    software :: runtime.fused_multiply_add_f32(x, y, z)
    testing.expect_eq(t, bits_32(software), bits_32(hardware), "software %{x}, hardware %{x}")
    return .Ok
}

counts_bits #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, intrinsics.leading_zeros(cast[u32](1)), 31, "leading, 1")
    testing.expect_eq(t, intrinsics.leading_zeros(cast[u32](0)), 32, "leading, 0")
    testing.expect_eq(t, intrinsics.leading_zeros(cast[u64](0x00ff_0000_0000_0000)), 8, "leading, u64")
    testing.expect_eq(t, intrinsics.trailing_zeros(cast[u16](0x0100)), 8, "trailing")
    testing.expect_eq(t, intrinsics.trailing_zeros(cast[u8](0)), 8, "trailing, 0")
    testing.expect_eq(t, intrinsics.count_ones(cast[u64](0xf0f0)), 8, "ones")
    testing.expect_eq(t, intrinsics.count_ones(cast[i32](-1)), 32, "ones, signed")
    lanes :: intrinsics.leading_zeros(vector[u32, 4].{1, 2, 0x8000_0000, 0})
    testing.expect(t, intrinsics.all_true(lanes == vector[u32, 4].{31, 30, 0, 32}), "lane by lane")
    return .Ok
}
