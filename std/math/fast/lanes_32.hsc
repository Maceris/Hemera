package fast

import intrinsics from "base"
import math from "std"

/*
 * f32's fast kernels, f32 throughout: SLEEF's (Naoki Shibata's) 3.5-ulp algorithms and coefficients, each a reduction,
 * a short polynomial with fused multiply-adds, and special cases chosen with select, branch-free. A lane a kernel's
 * reduction doesn't cover, like a huge angle, is worked out again by std/math's f32 function. n is how many lanes; a
 * scalar runs on one.
 */

/** An f32 in every lane. */
f32_lanes :: fn[n: usize](value: f32) -> vector[f32, n] {
    return intrinsics.splat[vector[f32, n]](value)
}

/** An i32 in every lane. */
i32_lanes :: fn[n: usize](value: i32) -> vector[i32, n] {
    return intrinsics.splat[vector[i32, n]](value)
}

/** f32 lanes' bits. */
bits_32 :: fn[n: usize](x: vector[f32, n]) -> vector[u32, n] {
    return bit_cast[vector[u32, n]](x)
}

/** f32 lanes from their bits. */
from_bits_32 :: fn[n: usize](bits: vector[u32, n]) -> vector[f32, n] {
    return bit_cast[vector[f32, n]](bits)
}

/** a × b + c rounded once, c in every lane: a step of a polynomial by Horner's rule. */
step_32 :: fn[n: usize](a: vector[f32, n], b: vector[f32, n], c: f32) -> vector[f32, n] {
    return intrinsics.fused_multiply_add(a, b, f32_lanes[n](c))
}

/** r - q × part rounded once: a step of a Cody-Waite reduction, part in every lane. */
reduce_step_32 :: fn[n: usize](q: vector[f32, n], part: f32, r: vector[f32, n]) -> vector[f32, n] {
    return intrinsics.fused_multiply_add(q, f32_lanes[n](-part), r)
}

/** |x| in each lane. */
magnitude_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    return from_bits_32(bits_32(x) & 0x7fff_ffff)
}

/** x with its sign flipped in the lanes where y's sign bit is set. */
times_sign_32 :: fn[n: usize](x: vector[f32, n], y: vector[f32, n]) -> vector[f32, n] {
    return from_bits_32(bits_32(x) ~ (bits_32(y) & 0x8000_0000))
}

/** 2^e in each lane, for e from -126 to 127. */
power_of_two_32 :: fn[n: usize](e: vector[i32, n]) -> vector[f32, n] {
    return from_bits_32(bit_cast[vector[u32, n]]((e + 127) << 23))
}

/** x × 2^e in each lane, for e from -252 to 254: in two steps, so neither factor leaves the normal range. */
scale_32 :: fn[n: usize](x: vector[f32, n], e: vector[i32, n]) -> vector[f32, n] {
    half :: e >> 1
    return x * power_of_two_32(half) * power_of_two_32(e - half)
}

/** The exponent of each lane, normal or infinite, unbiased: floor(log2 |x|). */
exponent_32 :: fn[n: usize](x: vector[f32, n]) -> vector[i32, n] {
    return bit_cast[vector[i32, n]]((bits_32(x) >> 23) & 0xff) - 127
}

/**
 * Work some lanes out again with std/math's f32 function: the ones the kernel doesn't cover.
 *
 * @tparam n How many lanes.
 * @param result What the kernel gave.
 * @param x The arguments.
 * @param redo Which lanes to work out again.
 * @param exact std/math's function.
 * @return result, with those lanes exact's.
 */
redo_32 :: fn[n: usize](result: vector[f32, n], x: vector[f32, n], redo: vector[bool, n], exact: (fn(x: f32) -> f32))
    -> vector[f32, n] {

    if !intrinsics.any_true(redo) {
        return result
    }
    lanes := bit_cast[f32[n]](result)
    inputs :: bit_cast[f32[n]](x)
    flags :: bit_cast[u8[n]](redo)
    for i in 0..<n {
        if flags[i] != 0 {
            lanes[i] = exact(inputs[i])
        }
    }
    return bit_cast[vector[f32, n]](lanes)
}

/** π in four parts, each short enough that its product with a whole number below 2^15 is exact. */
PI_A_32 : f32 : 3.140625
PI_B_32 : f32 : 0.0009670257568359375
PI_C_32 : f32 : 6.2771141529083251953e-07
PI_D_32 : f32 : 1.2154201256553420762e-10
/** 1/π. */
INVERSE_PI_32 : f32 : 0.318309886183790671537767526745028724
/** 2/π. */
TWO_OVER_PI_32 : f32 : 0.636619772367581343075535053490057448
/** How large an angle the four-part reduction covers. */
TRIG_RANGE_32 : f32 : 39000

/** sin's polynomial on -π/2 to π/2, in r²: SLEEF's xsinf. */
SIN_0_32 : f32 : 2.6083159809786593541503e-06
SIN_1_32 : f32 : -0.0001981069071916863322258
SIN_2_32 : f32 : 0.00833307858556509017944336
SIN_3_32 : f32 : -0.166666597127914428710938

/** sin r for r from -π/2 to π/2, its sign flipped where flip is set. */
sin_polynomial_32 :: fn[n: usize](r_in: vector[f32, n], flip: vector[bool, n]) -> vector[f32, n] {
    s :: r_in * r_in
    r :: intrinsics.select(flip, -r_in, r_in)
    u := f32_lanes[n](SIN_0_32)
    u = step_32(u, s, SIN_1_32)
    u = step_32(u, s, SIN_2_32)
    u = step_32(u, s, SIN_3_32)
    return intrinsics.fused_multiply_add(s, u * r, r)
}

/** sin on lanes: x - qπ, then sin's polynomial, its sign by q's parity. */
//SPEC: SLEEF sleefsimdsp.c xsinf
sin_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    covered :: magnitude_32(x) < TRIG_RANGE_32
    d :: intrinsics.select(covered, x, f32_lanes[n](0))
    q :: intrinsics.round_even(d * INVERSE_PI_32)
    r := reduce_step_32(q, PI_A_32, d)
    r = reduce_step_32(q, PI_B_32, r)
    r = reduce_step_32(q, PI_C_32, r)
    r = reduce_step_32(q, PI_D_32, r)
    odd :: (cast[vector[i32, n]](q) & 1) != 0
    result :: sin_polynomial_32(r, odd)
    // sin(-0) is -0
    return redo_32(intrinsics.select(x == 0, x, result), x, ~covered, math.sin[f32])
}

/** cos on lanes: x - qπ/2 for an odd q, then sin's polynomial. */
//SPEC: SLEEF sleefsimdsp.c xcosf
cos_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    covered :: magnitude_32(x) < TRIG_RANGE_32
    d :: intrinsics.select(covered, x, f32_lanes[n](0))
    q :: 1 + 2 * intrinsics.round_even(d * INVERSE_PI_32 - 0.5)
    r := reduce_step_32(q, PI_A_32 * 0.5, d)
    r = reduce_step_32(q, PI_B_32 * 0.5, r)
    r = reduce_step_32(q, PI_C_32 * 0.5, r)
    r = reduce_step_32(q, PI_D_32 * 0.5, r)
    flip :: (cast[vector[i32, n]](q) & 2) == 0
    return redo_32(sin_polynomial_32(r, flip), x, ~covered, math.cos[f32])
}

/** tan's polynomial on -π/4 to π/4, in r²: SLEEF's xtanf. */
TAN_0_32 : f32 : 0.00927245803177356719970703
TAN_1_32 : f32 : 0.00331984995864331722259521
TAN_2_32 : f32 : 0.0242998078465461730957031
TAN_3_32 : f32 : 0.0534495301544666290283203
TAN_4_32 : f32 : 0.133383005857467651367188
TAN_5_32 : f32 : 0.333331853151321411132812

/** tan on lanes: x - qπ/2, the polynomial, and its reciprocal for an odd q. */
//SPEC: SLEEF sleefsimdsp.c xtanf
tan_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    covered :: magnitude_32(x) < TRIG_RANGE_32
    d :: intrinsics.select(covered, x, f32_lanes[n](0))
    q :: intrinsics.round_even(d * TWO_OVER_PI_32)
    r := reduce_step_32(q, PI_A_32 * 0.5, d)
    r = reduce_step_32(q, PI_B_32 * 0.5, r)
    r = reduce_step_32(q, PI_C_32 * 0.5, r)
    r = reduce_step_32(q, PI_D_32 * 0.5, r)
    s :: r * r
    odd :: (cast[vector[i32, n]](q) & 1) != 0
    y :: intrinsics.select(odd, -r, r)
    u := f32_lanes[n](TAN_0_32)
    u = step_32(u, s, TAN_1_32)
    u = step_32(u, s, TAN_2_32)
    u = step_32(u, s, TAN_3_32)
    u = step_32(u, s, TAN_4_32)
    u = step_32(u, s, TAN_5_32)
    t :: intrinsics.fused_multiply_add(s, u * y, y)
    result :: intrinsics.select(odd, 1.0 / t, t)
    return redo_32(intrinsics.select(x == 0, x, result), x, ~covered, math.tan[f32])
}

/** 1/ln 2. */
INVERSE_LN2_32 : f32 : 1.442695040888963407359924681001892137
/** ln 2 in two parts, the first short enough that its product with a whole number below 2^8 is exact. */
LN2_HI_32 : f32 : 0.693145751953125
LN2_LO_32 : f32 : 1.428606765330187045e-06

/** e^r's polynomial, less 1 and r, over r²: SLEEF's xexpf. */
EXP_0_32 : f32 : 0.000198527617612853646278381
EXP_1_32 : f32 : 0.00139304355252534151077271
EXP_2_32 : f32 : 0.00833336077630519866943359
EXP_3_32 : f32 : 0.0416664853692054748535156
EXP_4_32 : f32 : 0.166666671633720397949219
EXP_5_32 : f32 : 0.5

/** exp on lanes: x - q ln 2, the polynomial, scaled by 2^q. */
//SPEC: SLEEF sleefsimdsp.c xexpf
exp_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    // Past 100 it's infinite and below -104 0 anyway; NaN to 0 for the arithmetic, and back below
    d :: intrinsics.minimum(intrinsics.maximum(intrinsics.select(x == x, x, f32_lanes[n](0)), f32_lanes[n](-104)),
        f32_lanes[n](100))
    q :: intrinsics.round_even(d * INVERSE_LN2_32)
    s := reduce_step_32(q, LN2_HI_32, d)
    s = reduce_step_32(q, LN2_LO_32, s)
    u := f32_lanes[n](EXP_0_32)
    u = step_32(u, s, EXP_1_32)
    u = step_32(u, s, EXP_2_32)
    u = step_32(u, s, EXP_3_32)
    u = step_32(u, s, EXP_4_32)
    u = step_32(u, s, EXP_5_32)
    u = 1 + intrinsics.fused_multiply_add(s * s, u, s)
    scaled :: scale_32(u, cast[vector[i32, n]](q))
    result :: intrinsics.select(x > 100, f32_lanes[n](math.infinity[f32]()), intrinsics.select(x < -104, f32_lanes[n](0),
        scaled))
    return intrinsics.select(x == x, result, x)
}

/** 2^r's polynomial, less 1, over r: SLEEF's xexp2f. */
EXP2_0_32 : f32 : 0.1535920892e-3
EXP2_1_32 : f32 : 0.1339262701e-2
EXP2_2_32 : f32 : 0.9618384764e-2
EXP2_3_32 : f32 : 0.5550347269e-1
EXP2_4_32 : f32 : 0.2402264476e+0
EXP2_5_32 : f32 : 0.6931471825e+0

/** exp2 on lanes: x less its nearest whole number q, the polynomial, scaled by 2^q. */
//SPEC: SLEEF sleefsimdsp.c xexp2f
exp2_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    d :: intrinsics.minimum(intrinsics.maximum(intrinsics.select(x == x, x, f32_lanes[n](0)), f32_lanes[n](-151)),
        f32_lanes[n](129))
    q :: intrinsics.round_even(d)
    s :: d - q
    u := f32_lanes[n](EXP2_0_32)
    u = step_32(u, s, EXP2_1_32)
    u = step_32(u, s, EXP2_2_32)
    u = step_32(u, s, EXP2_3_32)
    u = step_32(u, s, EXP2_4_32)
    u = step_32(u, s, EXP2_5_32)
    u = step_32(u, s, 1)
    scaled :: scale_32(u, cast[vector[i32, n]](q))
    result :: intrinsics.select(x >= 128, f32_lanes[n](math.infinity[f32]()), intrinsics.select(x < -150, f32_lanes[n](0),
        scaled))
    return intrinsics.select(x == x, result, x)
}

/** The least normal f32, 2^-126. */
LEAST_NORMAL_32 : f32 : 1.17549435e-38
/** 2^64, which scales a subnormal f32 up to normal. */
TWO_TO_64_32 : f32 : 18446744073709551616.0

/**
 * Split positive finite lanes into e and m with x = 2^e × m, m from 0.75 to 1.5.
 *
 * @tparam n How many lanes.
 * @param x The numbers: positive and finite, subnormals too.
 * @return e, and m.
 */
split_32 :: fn[n: usize](x: vector[f32, n]) -> (vector[i32, n], vector[f32, n]) {
    subnormal :: x < LEAST_NORMAL_32
    d :: intrinsics.select(subnormal, x * TWO_TO_64_32, x)
    e :: exponent_32(d * (1.0 / 0.75))
    m :: from_bits_32(bit_cast[vector[u32, n]](bit_cast[vector[i32, n]](bits_32(d)) - (e << 23)))
    return intrinsics.select(subnormal, e - 64, e), m
}

/** What a logarithm gives where it has no finite value: -infinity at ±0, NaN below 0 and for NaN, infinity at infinity. */
log_special_32 :: fn[n: usize](x: vector[f32, n], result: vector[f32, n]) -> vector[f32, n] {
    infinity :: f32_lanes[n](math.infinity[f32]())
    with_ends :: intrinsics.select(x == 0, -infinity, intrinsics.select(x == infinity, infinity, result))
    return intrinsics.select((x < 0) | (x != x), f32_lanes[n](math.nan[f32]()), with_ends)
}

/** ln's polynomial in ((m - 1)/(m + 1))²: SLEEF's xlogf. */
LOG_0_32 : f32 : 0.2392828464508056640625
LOG_1_32 : f32 : 0.28518211841583251953125
LOG_2_32 : f32 : 0.400005877017974853515625
LOG_3_32 : f32 : 0.666666686534881591796875
/** ln 2. */
LN2_32 : f32 : 0.693147180559945286226764

/** log on lanes: x = 2^e × m, then ln m from a series in (m - 1)/(m + 1), and e ln 2. */
//SPEC: SLEEF sleefsimdsp.c xlogf
log_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    usual :: (x > 0) & (x < math.infinity[f32]())
    e, m :: split_32(intrinsics.select(usual, x, f32_lanes[n](1)))
    r :: (m - 1) / (m + 1)
    r2 :: r * r
    t := f32_lanes[n](LOG_0_32)
    t = step_32(t, r2, LOG_1_32)
    t = step_32(t, r2, LOG_2_32)
    t = step_32(t, r2, LOG_3_32)
    t = step_32(t, r2, 2)
    result :: intrinsics.fused_multiply_add(r, t, cast[vector[f32, n]](e) * LN2_32)
    return log_special_32(x, result)
}

/** log2's polynomial in ((m - 1)/(m + 1))²: SLEEF's xlog2f_u35. */
LOG2_0_32 : f32 : 0.4374550283
LOG2_1_32 : f32 : 0.5764790177
LOG2_2_32 : f32 : 0.9618012905120
/** 2/ln 2. */
TWO_OVER_LN2_32 : f32 : 2.885390081777926774

/** log2 on lanes: x = 2^e × m, then e + log2 m from a series in (m - 1)/(m + 1). */
//SPEC: SLEEF sleefsimdsp.c xlog2f_u35
log2_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    usual :: (x > 0) & (x < math.infinity[f32]())
    e, m :: split_32(intrinsics.select(usual, x, f32_lanes[n](1)))
    r :: (m - 1) / (m + 1)
    r2 :: r * r
    t := f32_lanes[n](LOG2_0_32)
    t = step_32(t, r2, LOG2_1_32)
    t = step_32(t, r2, LOG2_2_32)
    result :: intrinsics.fused_multiply_add(r2 * r, t, intrinsics.fused_multiply_add(r, f32_lanes[n](TWO_OVER_LN2_32),
        cast[vector[f32, n]](e)))
    return log_special_32(x, result)
}

/** atan's polynomial on 0 to 1, in t²: SLEEF's xatanf. */
ATAN_0_32 : f32 : 0.00282363896258175373077393
ATAN_1_32 : f32 : -0.0159569028764963150024414
ATAN_2_32 : f32 : 0.0425049886107444763183594
ATAN_3_32 : f32 : -0.0748900920152664184570312
ATAN_4_32 : f32 : 0.106347933411598205566406
ATAN_5_32 : f32 : -0.142027363181114196777344
ATAN_6_32 : f32 : 0.199926957488059997558594
ATAN_7_32 : f32 : -0.333331018686294555664062
/** π/2, π/4 and π, rounded to f32. */
PI_OVER_2_32 : f32 : 1.570796326794896557998982
PI_OVER_4_32 : f32 : 0.785398163397448309615660845819875721
PI_32 : f32 : 3.14159265358979323846264338327950288

/** atan t for t from -1 to 1. */
atan_polynomial_32 :: fn[n: usize](t: vector[f32, n]) -> vector[f32, n] {
    t2 :: t * t
    u := f32_lanes[n](ATAN_0_32)
    u = step_32(u, t2, ATAN_1_32)
    u = step_32(u, t2, ATAN_2_32)
    u = step_32(u, t2, ATAN_3_32)
    u = step_32(u, t2, ATAN_4_32)
    u = step_32(u, t2, ATAN_5_32)
    u = step_32(u, t2, ATAN_6_32)
    u = step_32(u, t2, ATAN_7_32)
    return intrinsics.fused_multiply_add(t, t2 * u, t)
}

/** atan on lanes: |x| up to 1 as it is, above it π/2 - atan(1/|x|), and the sign put back. */
//SPEC: SLEEF sleefsimdsp.c xatanf
atan_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    a :: magnitude_32(x)
    above :: a > 1
    t :: atan_polynomial_32(intrinsics.select(above, 1.0 / a, a))
    result :: intrinsics.select(above, PI_OVER_2_32 - t, t)
    return times_sign_32(result, x)
}

/** atan2 on lanes: atan of the smaller over the larger, a multiple of π/2 added, and the ends as C has them. */
//SPEC: SLEEF sleefsimdsp.c xatan2f, atan2kf
atan2_lanes_32 :: fn[n: usize](y: vector[f32, n], x: vector[f32, n]) -> vector[f32, n] {
    ay :: magnitude_32(y)
    ax :: magnitude_32(x)
    // atan2(|y|, x) = q π/2 + atan(s): q -2 for a negative x, plus 1 where |y| is the larger
    quarter := intrinsics.select(x < 0, f32_lanes[n](-2), f32_lanes[n](0))
    swap :: ay > ax
    quarter = intrinsics.select(swap, quarter + 1, quarter)
    s :: intrinsics.select(swap, -ax, ay) / intrinsics.select(swap, ay, ax)
    r := times_sign_32(intrinsics.fused_multiply_add(quarter, f32_lanes[n](PI_OVER_2_32), atan_polynomial_32(s)), x)
    infinity :: f32_lanes[n](math.infinity[f32]())
    x_infinite :: ax == infinity
    // x infinite or 0: 0 or π for x infinite, π/2 for 0; then y infinite: π/4, 3π/4 or π/2
    r = intrinsics.select(x_infinite | (x == 0), PI_OVER_2_32 - intrinsics.select(x_infinite,
        times_sign_32(f32_lanes[n](PI_OVER_2_32), x), f32_lanes[n](0)), r)
    r = intrinsics.select(ay == infinity, PI_OVER_2_32 - intrinsics.select(x_infinite,
        times_sign_32(f32_lanes[n](PI_OVER_4_32), x), f32_lanes[n](0)), r)
    // y = ±0: 0, or π for a negative x, -0 included
    r = intrinsics.select(y == 0, intrinsics.select((bits_32(x) & 0x8000_0000) != 0, f32_lanes[n](PI_32), f32_lanes[n](0)), r)
    return intrinsics.select((x != x) | (y != y), f32_lanes[n](math.nan[f32]()), times_sign_32(r, y))
}

/** asin's polynomial in x²: SLEEF's xasinf and xacosf. */
ASIN_0_32 : f32 : 0.4197454825e-1
ASIN_1_32 : f32 : 0.2424046025e-1
ASIN_2_32 : f32 : 0.4547423869e-1
ASIN_3_32 : f32 : 0.7495029271e-1
ASIN_4_32 : f32 : 0.1666677296e+0

/** asin's polynomial less 1, over x³, in x². */
asin_polynomial_32 :: fn[n: usize](x2: vector[f32, n]) -> vector[f32, n] {
    u := f32_lanes[n](ASIN_0_32)
    u = step_32(u, x2, ASIN_1_32)
    u = step_32(u, x2, ASIN_2_32)
    u = step_32(u, x2, ASIN_3_32)
    return step_32(u, x2, ASIN_4_32)
}

/** asin on lanes: below 1/2 the polynomial, above it π/2 - 2 asin √((1 - |x|)/2). */
//SPEC: SLEEF sleefsimdsp.c xasinf
asin_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    a :: magnitude_32(x)
    small :: a < 0.5
    x2 :: intrinsics.select(small, x * x, (1 - a) * 0.5)
    z :: intrinsics.select(small, a, intrinsics.square_root(x2))
    u :: intrinsics.fused_multiply_add(asin_polynomial_32(x2), z * x2, z)
    result :: intrinsics.select(small, u, intrinsics.fused_multiply_add(u, f32_lanes[n](-2), f32_lanes[n](PI_OVER_2_32)))
    return times_sign_32(result, x)
}

/** π in two parts, for π - r. */
PI_HI_32 : f32 : 3.1415927410125732422
PI_LO_32 : f32 : -8.7422776573475857731e-08

/** acos on lanes: below 1/2 π/2 - asin x, above it 2 asin √((1 - |x|)/2), from π for a negative x. */
//SPEC: SLEEF sleefsimdsp.c xacosf
acos_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    a :: magnitude_32(x)
    small :: a < 0.5
    x2 :: intrinsics.select(small, x * x, (1 - a) * 0.5)
    z :: intrinsics.select(a == 1, f32_lanes[n](0), intrinsics.select(small, a, intrinsics.square_root(x2)))
    u :: asin_polynomial_32(x2) * (x2 * z)
    near :: PI_OVER_2_32 - (times_sign_32(z, x) + times_sign_32(u, x))
    far :: (z + u) * 2
    result :: intrinsics.select(small, near, far)
    return intrinsics.select(~small & (x < 0), (PI_HI_32 - result) + PI_LO_32, result)
}

/** ∛ of m from 0.5 to 1, as m^(-1/3): SLEEF's xcbrtf's polynomial. */
CUBE_ROOT_0_32 : f32 : -0.601564466953277587890625
CUBE_ROOT_1_32 : f32 : 2.8208892345428466796875
CUBE_ROOT_2_32 : f32 : -5.532182216644287109375
CUBE_ROOT_3_32 : f32 : 5.898262500762939453125
CUBE_ROOT_4_32 : f32 : -3.8095417022705078125
CUBE_ROOT_5_32 : f32 : 2.2241256237030029296875
/** ∛2 and ∛4. */
CUBE_ROOT_2_ROOT_32 : f32 : 1.2599210498948731647672106
CUBE_ROOT_4_ROOT_32 : f32 : 1.5874010519681994747517056

/**
 * cube_root on lanes: x = 2^e × m, m from 0.5 to 1; ∛m from a polynomial for m^(-1/3) and a Newton step; times
 * 2^(e/3), the remainder's ∛2 or ∛4 in too. ±0, infinities and NaN are themselves; subnormals by std/math.
 */
//SPEC: SLEEF sleefsimdsp.c xcbrtf
cube_root_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    a :: magnitude_32(x)
    usual :: (a >= LEAST_NORMAL_32) & (a < math.infinity[f32]())
    d :: intrinsics.select(usual, a, f32_lanes[n](1))
    e :: exponent_32(d) + 1
    m :: scale_32(d, -e)
    // e/3 and its remainder, through floats, kept positive by 6144, a multiple of 3
    t :: cast[vector[f32, n]](e) + 6144
    third :: cast[vector[i32, n]](t * (1.0 / 3.0))
    remainder :: cast[vector[i32, n]](t - cast[vector[f32, n]](third) * 3)
    q := intrinsics.select(remainder == 1, f32_lanes[n](CUBE_ROOT_2_ROOT_32), f32_lanes[n](1))
    q = intrinsics.select(remainder == 2, f32_lanes[n](CUBE_ROOT_4_ROOT_32), q)
    q = scale_32(q, third - 2048)
    u := f32_lanes[n](CUBE_ROOT_0_32)
    u = step_32(u, m, CUBE_ROOT_1_32)
    u = step_32(u, m, CUBE_ROOT_2_32)
    u = step_32(u, m, CUBE_ROOT_3_32)
    u = step_32(u, m, CUBE_ROOT_4_32)
    u = step_32(u, m, CUBE_ROOT_5_32)
    y :: m * u * u
    root :: (y - (2.0 / 3.0) * y * intrinsics.fused_multiply_add(y, u, f32_lanes[n](-1))) * q
    result :: intrinsics.select(usual, times_sign_32(root, x), x)
    return redo_32(result, x, (a != 0) & (a < LEAST_NORMAL_32), math.cube_root[f32])
}
