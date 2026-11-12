package fast

import intrinsics from "base"
import math from "std"

/*
 * f64's fast kernels: SLEEF's shapes (one reduction, one polynomial with fused multiply-adds, special cases chosen
 * with select, branch-free) with series worked out for 53 bits: Taylor's for sin, exp and exp2, ln's in
 * (m - 1)/(m + 1) for log and log2, and fdlibm's for atan and asin on a reduced range. A lane a reduction doesn't
 * cover is worked out again by std/math's f64 function. n is how many lanes; a scalar runs on one.
 */

/** An f64 in every lane. */
f64_lanes :: fn[n: usize](value: f64) -> vector[f64, n] {
    return intrinsics.splat[vector[f64, n]](value)
}

/** f64 lanes' bits. */
bits_64 :: fn[n: usize](x: vector[f64, n]) -> vector[u64, n] {
    return bit_cast[vector[u64, n]](x)
}

/** f64 lanes from their bits. */
from_bits_64 :: fn[n: usize](bits: vector[u64, n]) -> vector[f64, n] {
    return bit_cast[vector[f64, n]](bits)
}

/** a × b + c rounded once, c in every lane: a step of a polynomial by Horner's rule. */
step_64 :: fn[n: usize](a: vector[f64, n], b: vector[f64, n], c: f64) -> vector[f64, n] {
    return intrinsics.fused_multiply_add(a, b, f64_lanes[n](c))
}

/** r - q × part rounded once: a step of a Cody-Waite reduction, part in every lane. */
reduce_step_64 :: fn[n: usize](q: vector[f64, n], part: f64, r: vector[f64, n]) -> vector[f64, n] {
    return intrinsics.fused_multiply_add(q, f64_lanes[n](-part), r)
}

/** |x| in each lane. */
magnitude_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    return from_bits_64(bits_64(x) & 0x7fff_ffff_ffff_ffff)
}

/** x with its sign flipped in the lanes where y's sign bit is set. */
times_sign_64 :: fn[n: usize](x: vector[f64, n], y: vector[f64, n]) -> vector[f64, n] {
    return from_bits_64(bits_64(x) ~ (bits_64(y) & 0x8000_0000_0000_0000))
}

/**
 * Whole numbers in f64 lanes, each within an i32's range, as i32 lanes: x86-64 converts those four at a time, but
 * i64 only with AVX-512.
 */
whole_64 :: fn[n: usize](x: vector[f64, n]) -> vector[i32, n] {
    return cast[vector[i32, n]](x)
}

/** 2^e in each lane, for e from -1022 to 1023. */
power_of_two_64 :: fn[n: usize](e: vector[i32, n]) -> vector[f64, n] {
    return from_bits_64(bit_cast[vector[u64, n]](cast[vector[i64, n]](e + 1023) << 52))
}

/** x × 2^e in each lane, for e from -2044 to 2046: in two steps, so neither factor leaves the normal range. */
scale_64 :: fn[n: usize](x: vector[f64, n], e: vector[i32, n]) -> vector[f64, n] {
    half :: e >> 1
    return x * power_of_two_64(half) * power_of_two_64(e - half)
}

/**
 * Work some lanes out again with std/math's f64 function: the ones the kernel doesn't cover.
 *
 * @tparam n How many lanes.
 * @param result What the kernel gave.
 * @param x The arguments.
 * @param redo Which lanes to work out again.
 * @param exact std/math's function.
 * @return result, with those lanes exact's.
 */
redo_64 :: fn[n: usize](result: vector[f64, n], x: vector[f64, n], redo: vector[bool, n], exact: (fn(x: f64) -> f64))
    -> vector[f64, n] {

    if !intrinsics.any_true(redo) {
        return result
    }
    lanes := bit_cast[f64[n]](result)
    inputs :: bit_cast[f64[n]](x)
    flags :: bit_cast[u8[n]](redo)
    for i in 0..<n {
        if flags[i] != 0 {
            lanes[i] = exact(inputs[i])
        }
    }
    return bit_cast[vector[f64, n]](lanes)
}

/** The same for a function of two. */
redo_64_2 :: fn[n: usize](result: vector[f64, n], x: vector[f64, n], y: vector[f64, n], redo: vector[bool, n],
    exact: (fn(x: f64, y: f64) -> f64)) -> vector[f64, n] {

    if !intrinsics.any_true(redo) {
        return result
    }
    lanes := bit_cast[f64[n]](result)
    first :: bit_cast[f64[n]](x)
    second :: bit_cast[f64[n]](y)
    flags :: bit_cast[u8[n]](redo)
    for i in 0..<n {
        if flags[i] != 0 {
            lanes[i] = exact(first[i], second[i])
        }
    }
    return bit_cast[vector[f64, n]](lanes)
}

/** π in four parts, the first three of 30 bits, so their products with a whole number below 2^23 are exact. */
PI_A_64 : f64 : 3.141592651605606
PI_B_64 : f64 : 1.9841871583270443e-09
PI_C_64 : f64 : 1.03403659577805e-18
PI_D_64 : f64 : 5.807711947958721e-28
/** 1/π. */
INVERSE_PI_64 : f64 : 0.3183098861837907
/** How large an angle the reduction covers: 2^22. */
TRIG_RANGE_64 : f64 : 4194304.0

/** sin's Taylor series on -π/2 to π/2, past r, over r³, in r²: (-1)^k / (2k + 1)!. */
SIN_1_64 : f64 : -0.16666666666666666
SIN_2_64 : f64 : 0.008333333333333333
SIN_3_64 : f64 : -0.0001984126984126984
SIN_4_64 : f64 : 2.7557319223985893e-06
SIN_5_64 : f64 : -2.505210838544172e-08
SIN_6_64 : f64 : 1.6059043836821613e-10
SIN_7_64 : f64 : -7.647163731819816e-13
SIN_8_64 : f64 : 2.8114572543455206e-15
SIN_9_64 : f64 : -8.22063524662433e-18
SIN_10_64 : f64 : 1.9572941063391263e-20
SIN_11_64 : f64 : -3.868170170630684e-23

/** sin r for r from -π/2 to π/2, its sign flipped where flip is set. */
sin_polynomial_64 :: fn[n: usize](r_in: vector[f64, n], flip: vector[bool, n]) -> vector[f64, n] {
    s :: r_in * r_in
    r :: intrinsics.select(flip, -r_in, r_in)
    u := f64_lanes[n](SIN_11_64)
    u = step_64(u, s, SIN_10_64)
    u = step_64(u, s, SIN_9_64)
    u = step_64(u, s, SIN_8_64)
    u = step_64(u, s, SIN_7_64)
    u = step_64(u, s, SIN_6_64)
    u = step_64(u, s, SIN_5_64)
    u = step_64(u, s, SIN_4_64)
    u = step_64(u, s, SIN_3_64)
    u = step_64(u, s, SIN_2_64)
    u = step_64(u, s, SIN_1_64)
    return intrinsics.fused_multiply_add(s, u * r, r)
}

/** sin on lanes: x - qπ, then sin's series, its sign by q's parity. */
//SPEC: SLEEF sleefsimddp.c xsin's shape
sin_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    covered :: magnitude_64(x) < TRIG_RANGE_64
    d :: intrinsics.select(covered, x, f64_lanes[n](0))
    q :: intrinsics.round_even(d * INVERSE_PI_64)
    r := reduce_step_64(q, PI_A_64, d)
    r = reduce_step_64(q, PI_B_64, r)
    r = reduce_step_64(q, PI_C_64, r)
    r = reduce_step_64(q, PI_D_64, r)
    odd :: (whole_64(q) & 1) != 0
    result :: sin_polynomial_64(r, odd)
    return redo_64(intrinsics.select(x == 0, x, result), x, ~covered, math.sin_64)
}

/** cos on lanes: x - qπ/2 for an odd q, then sin's series. */
//SPEC: SLEEF sleefsimddp.c xcos's shape
cos_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    covered :: magnitude_64(x) < TRIG_RANGE_64
    d :: intrinsics.select(covered, x, f64_lanes[n](0))
    q :: 1 + 2 * intrinsics.round_even(d * INVERSE_PI_64 - 0.5)
    r := reduce_step_64(q, PI_A_64 * 0.5, d)
    r = reduce_step_64(q, PI_B_64 * 0.5, r)
    r = reduce_step_64(q, PI_C_64 * 0.5, r)
    r = reduce_step_64(q, PI_D_64 * 0.5, r)
    flip :: (whole_64(q) & 2) == 0
    return redo_64(sin_polynomial_64(r, flip), x, ~covered, math.cos_64)
}

/** 1/ln 2. */
INVERSE_LN2_64 : f64 : 1.4426950408889634
/** ln 2 in two parts, the first of 32 bits, so its product with a whole number below 2^21 is exact. */
LN2_HI_64 : f64 : 0.6931471803691238
LN2_LO_64 : f64 : 1.9082149292705877e-10

/** e^r's Taylor series past 1 + r, over r², in r: 1/k! from k = 2. */
EXP_2_64 : f64 : 0.5
EXP_3_64 : f64 : 0.16666666666666666
EXP_4_64 : f64 : 0.041666666666666664
EXP_5_64 : f64 : 0.008333333333333333
EXP_6_64 : f64 : 0.001388888888888889
EXP_7_64 : f64 : 0.0001984126984126984
EXP_8_64 : f64 : 2.48015873015873e-05
EXP_9_64 : f64 : 2.7557319223985893e-06
EXP_10_64 : f64 : 2.755731922398589e-07
EXP_11_64 : f64 : 2.505210838544172e-08
EXP_12_64 : f64 : 2.08767569878681e-09
EXP_13_64 : f64 : 1.6059043836821613e-10

/** Where exp overflows, and where it's 0 even as a subnormal. */
EXP_OVERFLOW_64 : f64 : 709.782712893384
EXP_UNDERFLOW_64 : f64 : -745.1332191019412

/** exp on lanes: x - q ln 2, the series, scaled by 2^q. */
//SPEC: SLEEF sleefsimddp.c xexp's shape
exp_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    d :: intrinsics.minimum(intrinsics.maximum(intrinsics.select(x == x, x, f64_lanes[n](0)), f64_lanes[n](-750)),
        f64_lanes[n](710))
    q :: intrinsics.round_even(d * INVERSE_LN2_64)
    s := reduce_step_64(q, LN2_HI_64, d)
    s = reduce_step_64(q, LN2_LO_64, s)
    u := f64_lanes[n](EXP_13_64)
    u = step_64(u, s, EXP_12_64)
    u = step_64(u, s, EXP_11_64)
    u = step_64(u, s, EXP_10_64)
    u = step_64(u, s, EXP_9_64)
    u = step_64(u, s, EXP_8_64)
    u = step_64(u, s, EXP_7_64)
    u = step_64(u, s, EXP_6_64)
    u = step_64(u, s, EXP_5_64)
    u = step_64(u, s, EXP_4_64)
    u = step_64(u, s, EXP_3_64)
    u = step_64(u, s, EXP_2_64)
    u = 1 + intrinsics.fused_multiply_add(s * s, u, s)
    scaled :: scale_64(u, whole_64(q))
    result :: intrinsics.select(x > EXP_OVERFLOW_64, f64_lanes[n](math.infinity[f64]()),
        intrinsics.select(x < EXP_UNDERFLOW_64, f64_lanes[n](0), scaled))
    return intrinsics.select(x == x, result, x)
}

/** 2^r's Taylor series past 1, over r, in r: (ln 2)^k / k!. */
EXP2_1_64 : f64 : 0.6931471805599453
EXP2_2_64 : f64 : 0.24022650695910072
EXP2_3_64 : f64 : 0.05550410866482158
EXP2_4_64 : f64 : 0.009618129107628477
EXP2_5_64 : f64 : 0.0013333558146428443
EXP2_6_64 : f64 : 0.0001540353039338161
EXP2_7_64 : f64 : 1.5252733804059841e-05
EXP2_8_64 : f64 : 1.321548679014431e-06
EXP2_9_64 : f64 : 1.01780860092397e-07
EXP2_10_64 : f64 : 7.054911620801123e-09
EXP2_11_64 : f64 : 4.4455382718708116e-10
EXP2_12_64 : f64 : 2.5678435993488206e-11
EXP2_13_64 : f64 : 1.3691488853904128e-12

/** exp2 on lanes: x less its nearest whole number q, the series, scaled by 2^q. */
//SPEC: SLEEF sleefsimddp.c xexp2's shape
exp2_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    d :: intrinsics.minimum(intrinsics.maximum(intrinsics.select(x == x, x, f64_lanes[n](0)), f64_lanes[n](-1080)),
        f64_lanes[n](1025))
    q :: intrinsics.round_even(d)
    s :: d - q
    u := f64_lanes[n](EXP2_13_64)
    u = step_64(u, s, EXP2_12_64)
    u = step_64(u, s, EXP2_11_64)
    u = step_64(u, s, EXP2_10_64)
    u = step_64(u, s, EXP2_9_64)
    u = step_64(u, s, EXP2_8_64)
    u = step_64(u, s, EXP2_7_64)
    u = step_64(u, s, EXP2_6_64)
    u = step_64(u, s, EXP2_5_64)
    u = step_64(u, s, EXP2_4_64)
    u = step_64(u, s, EXP2_3_64)
    u = step_64(u, s, EXP2_2_64)
    u = step_64(u, s, EXP2_1_64)
    u = step_64(u, s, 1)
    scaled :: scale_64(u, whole_64(q))
    result :: intrinsics.select(x >= 1024, f64_lanes[n](math.infinity[f64]()), intrinsics.select(x < -1075, f64_lanes[n](0),
        scaled))
    return intrinsics.select(x == x, result, x)
}

/** The least normal f64, 2^-1022. */
LEAST_NORMAL_64 : f64 : 2.2250738585072014e-308
/** 2^64, which scales a subnormal f64 up to normal. */
TWO_TO_64_64 : f64 : 18446744073709551616.0

/**
 * Split positive finite lanes into e and m with x = 2^e × m, m from 0.75 to 1.5.
 *
 * @tparam n How many lanes.
 * @param x The numbers: positive and finite, subnormals too.
 * @return e, and m.
 */
split_64 :: fn[n: usize](x: vector[f64, n]) -> (vector[i32, n], vector[f64, n]) {
    subnormal :: x < LEAST_NORMAL_64
    d :: intrinsics.select(subnormal, x * TWO_TO_64_64, x)
    biased :: cast[vector[i32, n]]((bits_64(d * (1.0 / 0.75)) >> 52) & 0x7ff)
    e :: biased - 1023
    m :: from_bits_64(bits_64(d) - (bit_cast[vector[u64, n]](cast[vector[i64, n]](e)) << 52))
    return intrinsics.select(subnormal, e - 64, e), m
}

/** What a logarithm gives where it has no finite value: -infinity at ±0, NaN below 0 and for NaN, infinity at infinity. */
log_special_64 :: fn[n: usize](x: vector[f64, n], result: vector[f64, n]) -> vector[f64, n] {
    infinity :: f64_lanes[n](math.infinity[f64]())
    with_ends :: intrinsics.select(x == 0, -infinity, intrinsics.select(x == infinity, infinity, result))
    return intrinsics.select((x < 0) | (x != x), f64_lanes[n](math.nan[f64]()), with_ends)
}

/** ln m's series in r = (m - 1)/(m + 1), over r, in r²: 2/(2k + 1). */
LOG_1_64 : f64 : 0.6666666666666666
LOG_2_64 : f64 : 0.4
LOG_3_64 : f64 : 0.2857142857142857
LOG_4_64 : f64 : 0.2222222222222222
LOG_5_64 : f64 : 0.18181818181818182
LOG_6_64 : f64 : 0.15384615384615385
LOG_7_64 : f64 : 0.13333333333333333
LOG_8_64 : f64 : 0.11764705882352941
LOG_9_64 : f64 : 0.10526315789473684
LOG_10_64 : f64 : 0.09523809523809523
LOG_11_64 : f64 : 0.08695652173913043

/** log on lanes: x = 2^e × m, then e ln 2 + ln m from its series in (m - 1)/(m + 1). */
//SPEC: SLEEF sleefsimddp.c xlog's shape
log_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    usual :: (x > 0) & (x < math.infinity[f64]())
    e, m :: split_64(intrinsics.select(usual, x, f64_lanes[n](1)))
    r :: (m - 1) / (m + 1)
    r2 :: r * r
    t := f64_lanes[n](LOG_11_64)
    t = step_64(t, r2, LOG_10_64)
    t = step_64(t, r2, LOG_9_64)
    t = step_64(t, r2, LOG_8_64)
    t = step_64(t, r2, LOG_7_64)
    t = step_64(t, r2, LOG_6_64)
    t = step_64(t, r2, LOG_5_64)
    t = step_64(t, r2, LOG_4_64)
    t = step_64(t, r2, LOG_3_64)
    t = step_64(t, r2, LOG_2_64)
    t = step_64(t, r2, LOG_1_64)
    t = step_64(t, r2, 2)
    k :: cast[vector[f64, n]](e)
    // e ln 2's first part is exact, so the rest goes in with ln m
    result :: k * LN2_HI_64 + intrinsics.fused_multiply_add(r, t, k * LN2_LO_64)
    return log_special_64(x, result)
}

/** log2 m's series in r = (m - 1)/(m + 1), over r, in r²: 2/((2k + 1) ln 2). */
LOG2_0_64 : f64 : 2.8853900817779268
LOG2_1_64 : f64 : 0.9617966939259756
LOG2_2_64 : f64 : 0.5770780163555853
LOG2_3_64 : f64 : 0.4121985831111324
LOG2_4_64 : f64 : 0.3205988979753252
LOG2_5_64 : f64 : 0.2623081892525388
LOG2_6_64 : f64 : 0.22195308321368667
LOG2_7_64 : f64 : 0.19235933878519512
LOG2_8_64 : f64 : 0.16972882833987804
LOG2_9_64 : f64 : 0.15186263588304877
LOG2_10_64 : f64 : 0.1373995277037108
LOG2_11_64 : f64 : 0.12545174268599682

/** log2 on lanes: x = 2^e × m, then e + log2 m from its series in (m - 1)/(m + 1). */
//SPEC: SLEEF sleefsimddp.c xlog2's shape
log2_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    usual :: (x > 0) & (x < math.infinity[f64]())
    e, m :: split_64(intrinsics.select(usual, x, f64_lanes[n](1)))
    r :: (m - 1) / (m + 1)
    r2 :: r * r
    t := f64_lanes[n](LOG2_11_64)
    t = step_64(t, r2, LOG2_10_64)
    t = step_64(t, r2, LOG2_9_64)
    t = step_64(t, r2, LOG2_8_64)
    t = step_64(t, r2, LOG2_7_64)
    t = step_64(t, r2, LOG2_6_64)
    t = step_64(t, r2, LOG2_5_64)
    t = step_64(t, r2, LOG2_4_64)
    t = step_64(t, r2, LOG2_3_64)
    t = step_64(t, r2, LOG2_2_64)
    t = step_64(t, r2, LOG2_1_64)
    t = step_64(t, r2, LOG2_0_64)
    result :: intrinsics.fused_multiply_add(r, t, cast[vector[f64, n]](e))
    return log_special_64(x, result)
}

/** tan(π/8) and tan(3π/8), where atan's reduction changes its reference point. */
TAN_PI_OVER_8_64 : f64 : 0.41421356237309503
TAN_3_PI_OVER_8_64 : f64 : 2.414213562373095

/** atan z for z from -tan(π/8) to tan(π/8), as hi - ((z s - lo) - z): fdlibm's polynomial, with hi + lo added. */
atan_reduced_64 :: fn[n: usize](z: vector[f64, n], hi: vector[f64, n], lo: vector[f64, n]) -> vector[f64, n] {
    z2 :: z * z
    w :: z2 * z2
    s1 := f64_lanes[n](math.ATAN_T10)
    s1 = step_64(s1, w, math.ATAN_T8)
    s1 = step_64(s1, w, math.ATAN_T6)
    s1 = step_64(s1, w, math.ATAN_T4)
    s1 = step_64(s1, w, math.ATAN_T2)
    s1 = step_64(s1, w, math.ATAN_T0)
    s2 := f64_lanes[n](math.ATAN_T9)
    s2 = step_64(s2, w, math.ATAN_T7)
    s2 = step_64(s2, w, math.ATAN_T5)
    s2 = step_64(s2, w, math.ATAN_T3)
    s2 = step_64(s2, w, math.ATAN_T1)
    s :: z2 * s1 + w * s2
    return hi - ((z * s - lo) - z)
}

/**
 * atan on lanes: |x| to tan(π/8) as it is, to tan(3π/8) from π/4 by (|x| - 1)/(|x| + 1), above from π/2 by -1/|x|;
 * one division, its parts chosen per lane, and the sign put back.
 */
//SPEC: fdlibm s_atan.c's polynomial, on three intervals
atan_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    a :: magnitude_64(x)
    small :: a <= TAN_PI_OVER_8_64
    middle :: ~small & (a <= TAN_3_PI_OVER_8_64)
    numerator :: intrinsics.select(small, a, intrinsics.select(middle, a - 1, f64_lanes[n](-1)))
    denominator :: intrinsics.select(small, f64_lanes[n](1), intrinsics.select(middle, a + 1, a))
    z :: numerator / denominator
    hi :: intrinsics.select(small, f64_lanes[n](0), intrinsics.select(middle, f64_lanes[n](math.ATAN_HI_1),
        f64_lanes[n](math.ATAN_HI_3)))
    lo :: intrinsics.select(small, f64_lanes[n](0), intrinsics.select(middle, f64_lanes[n](math.ATAN_LO_1),
        f64_lanes[n](math.ATAN_LO_3)))
    result :: atan_reduced_64(z, hi, lo)
    return intrinsics.select(x != x, x, times_sign_64(result, x))
}

/** π in two parts. */
PI_HI_64 : f64 : 3.141592653589793
PI_LO_64 : f64 : 1.2246467991473532e-16
/** Magnitudes past which atan2's sums could overflow or its quotient's parts underflow: 2^1000 and 2^-1000. */
ATAN2_LARGE_64 : f64 : 1.0715086071862673e301
ATAN2_SMALL_64 : f64 : 9.332636185032189e-302

/**
 * atan2 on lanes: atan of the smaller magnitude over the larger, reduced as atan's is with one division; then π/2 less
 * it where |y| is the larger, π less that for a negative x, and y's sign. Zeros, infinities, NaN and magnitudes past
 * 2^±1000 by std/math.
 */
//SPEC: fdlibm s_atan.c's polynomial, on two intervals
atan2_lanes_64 :: fn[n: usize](y: vector[f64, n], x: vector[f64, n]) -> vector[f64, n] {
    ay :: magnitude_64(y)
    ax :: magnitude_64(x)
    usual :: (ax > ATAN2_SMALL_64) & (ax < ATAN2_LARGE_64) & (ay > ATAN2_SMALL_64) & (ay < ATAN2_LARGE_64)
    safe_y :: intrinsics.select(usual, ay, f64_lanes[n](1))
    safe_x :: intrinsics.select(usual, ax, f64_lanes[n](2))
    swap :: safe_y > safe_x
    smaller :: intrinsics.select(swap, safe_x, safe_y)
    larger :: intrinsics.select(swap, safe_y, safe_x)
    middle :: smaller > larger * TAN_PI_OVER_8_64
    z :: intrinsics.select(middle, smaller - larger, smaller) / intrinsics.select(middle, smaller + larger, larger)
    hi :: intrinsics.select(middle, f64_lanes[n](math.ATAN_HI_1), f64_lanes[n](0))
    lo :: intrinsics.select(middle, f64_lanes[n](math.ATAN_LO_1), f64_lanes[n](0))
    angle :: atan_reduced_64(z, hi, lo)
    turned :: intrinsics.select(swap, (math.ATAN_HI_3 - angle) + math.ATAN_LO_3, angle)
    result :: intrinsics.select(x < 0, (PI_HI_64 - turned) + PI_LO_64, turned)
    return redo_64_2(times_sign_64(result, y), y, x, ~usual, math.atan2_64)
}

/** asin t for t from 0 to 1/2, past t: t × R(t²), R fdlibm's rational function. */
asin_tail_64 :: fn[n: usize](t: vector[f64, n], t2: vector[f64, n]) -> vector[f64, n] {
    return t * math.asin_rational_lanes(t2)
}

/** asin on lanes: below 1/2 x + x R(x²), above it π/2 - 2 asin √((1 - |x|)/2). */
//SPEC: fdlibm e_asin.c's rational function, without its extra precision
asin_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    a :: magnitude_64(x)
    small :: a < 0.5
    t2 :: intrinsics.select(small, x * x, (1 - a) * 0.5)
    t :: intrinsics.select(small, a, intrinsics.square_root(t2))
    w :: asin_tail_64(t, t2)
    result :: intrinsics.select(small, t + w, math.ATAN_HI_3 - (2 * (t + w) - math.ATAN_LO_3))
    return times_sign_64(result, x)
}

/** acos on lanes: below 1/2 π/2 - asin x, above it 2 asin √((1 - |x|)/2), from π for a negative x. */
//SPEC: fdlibm e_acos.c's rational function, without its extra precision
acos_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    a :: magnitude_64(x)
    small :: a < 0.5
    t2 :: intrinsics.select(small, x * x, (1 - a) * 0.5)
    t :: intrinsics.select(small, x, intrinsics.square_root(t2))
    w :: asin_tail_64(t, t2)
    near :: math.ATAN_HI_3 - (t - (math.ATAN_LO_3 - w))
    far :: 2 * (t + w)
    return intrinsics.select(small, near, intrinsics.select(x < 0, PI_HI_64 - (far - PI_LO_64), far))
}
