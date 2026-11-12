package math

import intrinsics from "base"

/*
 * f64's functions on lanes: fdlibm's algorithms as the scalar functions have them, every branch worked out in every lane
 * and the lane's own chosen with select, so each lane gives the scalar function's bits exactly. A lane in a branch
 * that's rare and long, like a huge angle's reduction, or a special case, is worked out again by the scalar function.
 * n is how many lanes.
 */

/** f64 lanes' bits. */
lane_bits :: fn[n: usize](x: vector[f64, n]) -> vector[u64, n] {
    return bit_cast[vector[u64, n]](x)
}

/** f64 lanes' high words, signed, as fdlibm reads them. */
lane_high :: fn[n: usize](x: vector[f64, n]) -> vector[i64, n] {
    return bit_cast[vector[i64, n]](x) >> 32
}

/** f64 lanes' low words. */
lane_low :: fn[n: usize](x: vector[f64, n]) -> vector[i64, n] {
    return bit_cast[vector[i64, n]](lane_bits(x) & 0xffff_ffff)
}

/** f64 lanes with their low words zero, fdlibm's SET_LOW_WORD(x, 0). */
lane_cut :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    return bit_cast[vector[f64, n]](lane_bits(x) & 0xffff_ffff_0000_0000)
}

/** f64 lanes with their high words replaced. */
lane_with_high :: fn[n: usize](x: vector[f64, n], high: vector[i64, n]) -> vector[f64, n] {
    return bit_cast[vector[f64, n]]((bit_cast[vector[u64, n]](high) << 32) | (lane_bits(x) & 0xffff_ffff))
}

/** f64 lanes from high words, their low words zero. */
lane_from_high :: fn[n: usize](high: vector[i64, n]) -> vector[f64, n] {
    return bit_cast[vector[f64, n]](bit_cast[vector[u64, n]](high) << 32)
}

/*
 * Conversions between f64 and i64 lanes go through i32 lanes: x86-64 converts those four at a time, but i64 only with
 * AVX-512, without which each lane is converted alone. The values here all fit in an i32.
 */

/** Lanes of whole numbers, each within an i32's range, as f64. */
lane_float :: fn[n: usize](k: vector[i64, n]) -> vector[f64, n] {
    return cast[vector[f64, n]](cast[vector[i32, n]](k))
}

/** f64 lanes, each within an i32's range, truncated toward 0 to whole numbers. */
lane_whole :: fn[n: usize](x: vector[f64, n]) -> vector[i64, n] {
    return cast[vector[i64, n]](cast[vector[i32, n]](x))
}

/**
 * Work some f64 lanes out again with the scalar function, the ones the kernel doesn't cover.
 *
 * @tparam n How many lanes.
 * @param result What the kernel gave.
 * @param x The arguments.
 * @param redo Which lanes to work out again.
 * @param exact The scalar function.
 * @return result, with those lanes exact's.
 */
redo_lanes_64 :: fn[n: usize](result: vector[f64, n], x: vector[f64, n], redo: vector[bool, n], exact: (fn(x: f64) -> f64))
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
redo_lanes_64_2 :: fn[n: usize](result: vector[f64, n], x: vector[f64, n], y: vector[f64, n], redo: vector[bool, n],
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

/** exp_reduced_64 on lanes, k from -1074 to 1024. */
//SPEC: fdlibm e_exp.c
exp_reduced_lanes :: fn[n: usize](hi: vector[f64, n], lo: vector[f64, n], k: vector[i64, n]) -> vector[f64, n] {
    x :: hi - lo
    t :: x * x
    c :: x - t * (t * (t * (t * (t * EXP_P5 + EXP_P4) + EXP_P3) + EXP_P2) + EXP_P1)
    // One division: its denominator c - 2 for k = 0, 2 - c otherwise
    quotient :: (x * c) / intrinsics.select(k == 0, c - 2.0, 2.0 - c)
    at_zero :: 1 - (quotient - x)
    y :: 1 - ((lo - quotient) - hi)
    // k = 1024: y × 2 × 2^1023
    top :: k == 1024
    doubled :: intrinsics.select(top, y * 2.0, y)
    normal_k :: intrinsics.select(top, intrinsics.splat[vector[i64, n]](1023), k)
    small :: k < -1021
    scale_k :: intrinsics.select(small, k + 1000, normal_k)
    scaled :: doubled * lane_from_high(((scale_k + 0x3ff) & 0x7ff) << 20)
    result :: intrinsics.select(small, scaled * TWO_TO_MINUS_1000, scaled)
    return intrinsics.select(k == 0, at_zero, result)
}

/** exp_64 on lanes: past its range, infinite and NaN lanes by the scalar function. */
//SPEC: fdlibm e_exp.c
exp_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    hx :: lane_high(x) & 0x7fff_ffff
    negative :: x < 0
    special :: hx >= 0x4086_2e42
    // ±ln 2 reduced by k = ±1, larger by the nearest k, under 2^-28 1 + x, the rest as it is
    near :: (hx > 0x3fd6_2e42) & (hx < 0x3ff0_a2b2)
    far :: hx >= 0x3ff0_a2b2
    tiny :: hx < 0x3e30_0000
    safe :: intrinsics.select(special, intrinsics.splat[vector[f64, n]](0), x)
    rounding :: intrinsics.select(negative, intrinsics.splat[vector[f64, n]](-0.5), intrinsics.splat[vector[f64, n]](0.5))
    k_far :: lane_whole(safe * INVERSE_LN2 + rounding)
    t :: lane_float(k_far)
    one :: intrinsics.select(negative, intrinsics.splat[vector[i64, n]](-1), intrinsics.splat[vector[i64, n]](1))
    hi :: intrinsics.select(far, safe - t * LN2_HI,
        intrinsics.select(near, intrinsics.select(negative, safe + LN2_HI, safe - LN2_HI), safe))
    lo :: intrinsics.select(far, t * LN2_LO,
        intrinsics.select(near, intrinsics.select(negative, intrinsics.splat[vector[f64, n]](-LN2_LO),
        intrinsics.splat[vector[f64, n]](LN2_LO)), intrinsics.splat[vector[f64, n]](0)))
    k :: intrinsics.select(far, k_far, intrinsics.select(near, one, intrinsics.splat[vector[i64, n]](0)))
    result :: intrinsics.select(tiny, 1 + safe, exp_reduced_lanes(hi, lo, k))
    return redo_lanes_64(result, x, special, exp_64)
}

/** log_64 on lanes: zeros, negatives, subnormals, infinities and NaN by the scalar function. */
//SPEC: fdlibm e_log.c
log_lanes_64 :: fn[n: usize](x_in: vector[f64, n]) -> vector[f64, n] {
    high :: lane_high(x_in)
    special :: (high < 0x0010_0000) | (high >= 0x7ff0_0000)
    x0 :: intrinsics.select(special, intrinsics.splat[vector[f64, n]](2), x_in)
    hx0 :: lane_high(x0)
    k0 :: (hx0 >> 20) - 1023
    hx :: hx0 & 0x000f_ffff
    i0 :: (hx + 0x9_5f64) & 0x10_0000
    x :: lane_with_high(x0, hx | (i0 ~ 0x3ff0_0000))
    k :: k0 + (i0 >> 20)
    f :: x - 1.0
    dk :: lane_float(k)
    at_zero :: k == 0
    // |f| under 2^-20
    near :: ((2 + hx) & 0x000f_ffff) < 3
    r_near :: f * f * (0.5 - 0.33333333333333333 * f)
    near_result :: intrinsics.select(f == 0,
        intrinsics.select(at_zero, intrinsics.splat[vector[f64, n]](0), dk * LN2_HI + dk * LN2_LO),
        intrinsics.select(at_zero, f - r_near, dk * LN2_HI - ((r_near - dk * LN2_LO) - f)))
    s :: f / (2.0 + f)
    z :: s * s
    w :: z * z
    t1 :: w * (w * (w * LOG_LG6 + LOG_LG4) + LOG_LG2)
    t2 :: z * (w * (w * (w * LOG_LG7 + LOG_LG5) + LOG_LG3) + LOG_LG1)
    i :: (hx - 0x6_147a) | (0x6_b851 - hx)
    r :: t2 + t1
    half_f_squared :: 0.5 * f * f
    upper :: intrinsics.select(at_zero, f - (half_f_squared - s * (half_f_squared + r)),
        dk * LN2_HI - ((half_f_squared - (s * (half_f_squared + r) + dk * LN2_LO)) - f))
    lower :: intrinsics.select(at_zero, f - s * (f - r), dk * LN2_HI - ((s * (f - r) - dk * LN2_LO) - f))
    result :: intrinsics.select(near, near_result, intrinsics.select(i > 0, upper, lower))
    return redo_lanes_64(result, x_in, special, log_64)
}

/** sin_kernel_64 on lanes. */
//SPEC: fdlibm k_sin.c
sin_kernel_lanes :: fn[n: usize](x: vector[f64, n], y: vector[f64, n], has_tail: bool) -> vector[f64, n] {
    z :: x * x
    w :: z * z
    r :: z * (z * SIN_S4 + SIN_S3) + SIN_S2 + z * w * (z * SIN_S6 + SIN_S5)
    v :: z * x
    if !has_tail {
        return x + v * (z * r + SIN_S1)
    }
    return x - ((z * (0.5 * y - v * r) - y) - v * SIN_S1)
}

/** cos_kernel_64 on lanes. */
//SPEC: fdlibm k_cos.c
cos_kernel_lanes :: fn[n: usize](x: vector[f64, n], y: vector[f64, n]) -> vector[f64, n] {
    z :: x * x
    w := z * z
    r :: z * (z * (z * COS_C3 + COS_C2) + COS_C1) + w * w * (z * (z * COS_C6 + COS_C5) + COS_C4)
    half_z :: 0.5 * z
    w = 1 - half_z
    return w + (((1 - w) - half_z) + (z * r - x * y))
}

/**
 * reduce_64 on lanes, for |x| up to 2^20 π/2: the near multiples of π/2 by one subtraction, the rest by the medium
 * reduction's rounds; larger lanes say so, for the scalar function.
 *
 * @tparam n How many lanes.
 * @param x The angles.
 * @return n modulo 4, y0 and y1 as reduce_64 gives them, and which lanes are too large.
 */
//SPEC: fdlibm e_rem_pio2.c
reduce_lanes :: fn[n: usize](x: vector[f64, n]) -> (vector[i64, n], vector[f64, n], vector[f64, n], vector[bool, n]) {
    negative :: x < 0
    ix :: lane_high(x) & 0x7fff_ffff
    large :: ix >= 0x4139_21fb
    safe :: intrinsics.select(large, intrinsics.splat[vector[f64, n]](0), x)
    // One subtraction of 1 to 4 times π/2, but where the cancellation needs more of π/2
    first :: (ix <= 0x400f_6a7a) & ((ix & 0xf_ffff) != 0x9_21fb)
    second :: (ix > 0x400f_6a7a) & (ix <= 0x401c_463b) & (ix != 0x4012_d97c) & (ix != 0x4019_21fb)
    direct :: first | second
    reduced_n := intrinsics.splat[vector[i64, n]](0)
    y0 := intrinsics.splat[vector[f64, n]](0)
    y1 := intrinsics.splat[vector[f64, n]](0)
    if intrinsics.any_true(direct) {
        multiple_i :: intrinsics.select(first, intrinsics.select(ix <= 0x4002_d97c, intrinsics.splat[vector[i64, n]](1),
            intrinsics.splat[vector[i64, n]](2)), intrinsics.select(ix <= 0x4015_fdbc, intrinsics.splat[vector[i64, n]](3),
            intrinsics.splat[vector[i64, n]](4)))
        multiple :: lane_float(multiple_i)
        // x - m π/2 for a positive x, x + m π/2 for a negative one
        step :: intrinsics.select(negative, -multiple, multiple)
        z :: safe - step * PI_OVER_2_1
        direct_y0 :: z - step * PI_OVER_2_1_TAIL
        reduced_n = intrinsics.select(negative, -multiple_i, multiple_i)
        y0 = direct_y0
        y1 = (z - direct_y0) - step * PI_OVER_2_1_TAIL
    }
    if !intrinsics.any_true(~direct & ~large) {
        return reduced_n & 3, y0, y1, large
    }
    // The medium reduction
    count0 :: (safe * INVERSE_PI_OVER_2 + TO_WHOLE) - TO_WHOLE
    r0 :: safe - count0 * PI_OVER_2_1
    w0 :: count0 * PI_OVER_2_1_TAIL
    down :: r0 - w0 < -PI_OVER_4
    up :: r0 - w0 > PI_OVER_4
    count :: intrinsics.select(down, count0 - 1, intrinsics.select(up, count0 + 1, count0))
    r1 :: safe - count * PI_OVER_2_1
    w1 :: count * PI_OVER_2_1_TAIL
    y0_1 :: r1 - w1
    ex :: ix >> 20
    ey1 :: bit_cast[vector[i64, n]]((lane_bits(y0_1) >> 52) & 0x7ff)
    second_round :: ex - ey1 > 16
    w2 :: count * PI_OVER_2_2
    r2 :: r1 - w2
    w2b :: count * PI_OVER_2_2_TAIL - ((r1 - r2) - w2)
    y0_2 :: r2 - w2b
    ey2 :: bit_cast[vector[i64, n]]((lane_bits(y0_2) >> 52) & 0x7ff)
    third_round :: second_round & (ex - ey2 > 49)
    w3 :: count * PI_OVER_2_3
    r3 :: r2 - w3
    w3b :: count * PI_OVER_2_3_TAIL - ((r2 - r3) - w3)
    y0_3 :: r3 - w3b
    medium_y0 :: intrinsics.select(third_round, y0_3, intrinsics.select(second_round, y0_2, y0_1))
    medium_r :: intrinsics.select(third_round, r3, intrinsics.select(second_round, r2, r1))
    medium_w :: intrinsics.select(third_round, w3b, intrinsics.select(second_round, w2b, w1))
    medium_y1 :: (medium_r - medium_y0) - medium_w
    medium_n :: lane_whole(count)
    return intrinsics.select(direct, reduced_n, medium_n) & 3, intrinsics.select(direct, y0, medium_y0),
        intrinsics.select(direct, y1, medium_y1), large
}

/** sin_64 or cos_64 on lanes: cos where cosine is true. */
sin_or_cos_lanes :: fn[n: usize](x: vector[f64, n], cosine: bool) -> vector[f64, n] {
    ix :: lane_high(x) & 0x7fff_ffff
    small :: ix <= 0x3fe9_21fb
    special :: ix >= 0x7ff0_0000
    zero :: intrinsics.splat[vector[f64, n]](0)
    near_zero := zero
    if intrinsics.any_true(small) {
        near_zero = if cosine {
            intrinsics.select(ix < 0x3e46_a09e, intrinsics.splat[vector[f64, n]](1), cos_kernel_lanes(x, zero))
        }
        else {
            intrinsics.select(ix < 0x3e50_0000, x, sin_kernel_lanes(x, zero, false))
        }
        if !intrinsics.any_true(~small) {
            return near_zero
        }
    }
    quadrant, y0, y1, large :: reduce_lanes(intrinsics.select(small | special, zero, x))
    s :: sin_kernel_lanes(y0, y1, true)
    c :: cos_kernel_lanes(y0, y1)
    // sin: 0 s, 1 c, 2 -s, 3 -c; cos: 0 c, 1 -s, 2 -c, 3 s
    sin_value :: intrinsics.select((quadrant & 1) == 1, c, s)
    sin_signed :: intrinsics.select((quadrant & 2) == 2, -sin_value, sin_value)
    cos_value :: intrinsics.select((quadrant & 1) == 1, s, c)
    cos_signed :: intrinsics.select(((quadrant + 1) & 2) == 2, -cos_value, cos_value)
    reduced :: if cosine { cos_signed } else { sin_signed }
    result :: intrinsics.select(small, near_zero, intrinsics.select(special, x - x, reduced))
    return redo_lanes_64(result, x, large & ~small & ~special, if cosine { cos_64 } else { sin_64 })
}

/** sin_64 on lanes. */
sin_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    return sin_or_cos_lanes(x, false)
}

/** cos_64 on lanes. */
cos_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    return sin_or_cos_lanes(x, true)
}

/** tan_kernel_64 on lanes, odd per lane. */
//SPEC: fdlibm k_tan.c, as musl's __tan
tan_kernel_lanes :: fn[n: usize](x_in: vector[f64, n], y_in: vector[f64, n], odd: vector[bool, n]) -> vector[f64, n] {
    hx :: lane_high(x_in)
    big :: (hx & 0x7fff_ffff) >= 0x3fe5_9428
    negative :: hx < 0
    flip :: big & negative
    x0 :: intrinsics.select(flip, -x_in, x_in)
    y0 :: intrinsics.select(flip, -y_in, y_in)
    x :: intrinsics.select(big, (PI_OVER_4 - x0) + (PI_OVER_4_LO - y0), x0)
    y :: intrinsics.select(big, intrinsics.splat[vector[f64, n]](0), y0)
    z :: x * x
    w :: z * z
    r0 :: w * (w * (w * (w * (w * TAN_T11 + TAN_T9) + TAN_T7) + TAN_T5) + TAN_T3) + TAN_T1
    v0 :: z * (w * (w * (w * (w * (w * TAN_T12 + TAN_T10) + TAN_T8) + TAN_T6) + TAN_T4) + TAN_T2)
    s0 :: z * x
    r :: y + z * (s0 * (r0 + v0) + y) + s0 * TAN_T0
    w2 :: x + r
    sign_one :: intrinsics.select(odd, intrinsics.splat[vector[f64, n]](-1), intrinsics.splat[vector[f64, n]](1))
    big_v :: sign_one - 2.0 * (x + (r - w2 * w2 / (w2 + sign_one)))
    big_result :: intrinsics.select(negative, -big_v, big_v)
    w0 :: lane_cut(w2)
    v :: r - (w0 - x)
    a :: -1.0 / w2
    a0 :: lane_cut(a)
    odd_result :: a0 + a * (1.0 + a0 * w0 + a0 * v)
    return intrinsics.select(big, big_result, intrinsics.select(odd, odd_result, w2))
}

/** tan_64 on lanes. */
//SPEC: fdlibm s_tan.c
tan_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    ix :: lane_high(x) & 0x7fff_ffff
    small :: ix <= 0x3fe9_21fb
    special :: ix >= 0x7ff0_0000
    zero :: intrinsics.splat[vector[f64, n]](0)
    near_zero := zero
    if intrinsics.any_true(small) {
        near_zero = intrinsics.select(ix < 0x3e40_0000, x, tan_kernel_lanes(x, zero, intrinsics.splat[vector[bool, n]](false)))
        if !intrinsics.any_true(~small) {
            return near_zero
        }
    }
    quadrant, y0, y1, large :: reduce_lanes(intrinsics.select(small | special, zero, x))
    reduced :: tan_kernel_lanes(y0, y1, (quadrant & 1) == 1)
    result :: intrinsics.select(small, near_zero, intrinsics.select(special, x - x, reduced))
    return redo_lanes_64(result, x, large & ~small & ~special, tan_64)
}

/** atan_64 on lanes. */
//SPEC: fdlibm s_atan.c
atan_lanes_64 :: fn[n: usize](x_in: vector[f64, n]) -> vector[f64, n] {
    hx :: lane_high(x_in)
    ix :: hx & 0x7fff_ffff
    huge :: ix >= 0x4410_0000
    tiny :: ix < 0x3e40_0000
    small :: ix < 0x3fdc_0000
    magnitude :: lane_magnitude(x_in)
    // Which reference point: 0 to 3, or none for small
    id0 :: (ix >= 0x3fdc_0000) & (ix < 0x3fe6_0000)
    id1 :: (ix >= 0x3fe6_0000) & (ix < 0x3ff3_0000)
    id2 :: (ix >= 0x3ff3_0000) & (ix < 0x4003_8000)
    // One division, its parts chosen per lane
    numerator :: intrinsics.select(id0, 2.0 * magnitude - 1, intrinsics.select(id1, magnitude - 1,
        intrinsics.select(id2, magnitude - 1.5, intrinsics.splat[vector[f64, n]](-1.0))))
    denominator :: intrinsics.select(id0, 2.0 + magnitude, intrinsics.select(id1, magnitude + 1,
        intrinsics.select(id2, 1 + 1.5 * magnitude, magnitude)))
    x :: intrinsics.select(small, x_in, numerator / denominator)
    z :: x * x
    w :: z * z
    s1 :: z * (w * (w * (w * (w * (w * ATAN_T10 + ATAN_T8) + ATAN_T6) + ATAN_T4) + ATAN_T2) + ATAN_T0)
    s2 :: w * (w * (w * (w * (w * ATAN_T9 + ATAN_T7) + ATAN_T5) + ATAN_T3) + ATAN_T1)
    small_result :: x - x * (s1 + s2)
    hi :: intrinsics.select(id0, intrinsics.splat[vector[f64, n]](ATAN_HI_0), intrinsics.select(id1,
        intrinsics.splat[vector[f64, n]](ATAN_HI_1), intrinsics.select(id2, intrinsics.splat[vector[f64, n]](ATAN_HI_2),
        intrinsics.splat[vector[f64, n]](ATAN_HI_3))))
    lo :: intrinsics.select(id0, intrinsics.splat[vector[f64, n]](ATAN_LO_0), intrinsics.select(id1,
        intrinsics.splat[vector[f64, n]](ATAN_LO_1), intrinsics.select(id2, intrinsics.splat[vector[f64, n]](ATAN_LO_2),
        intrinsics.splat[vector[f64, n]](ATAN_LO_3))))
    referenced :: hi - ((x * (s1 + s2) - lo) - x)
    signed :: intrinsics.select(hx < 0, -referenced, referenced)
    huge_result :: intrinsics.select(hx > 0, intrinsics.splat[vector[f64, n]](ATAN_HI_3 + ATAN_LO_3),
        intrinsics.splat[vector[f64, n]](-ATAN_HI_3 - ATAN_LO_3))
    result :: intrinsics.select(tiny, x_in, intrinsics.select(small, small_result, signed))
    return intrinsics.select(huge, intrinsics.select(x_in != x_in, x_in + x_in, huge_result), result)
}

/** atan2_64 on lanes: zeros, infinities, NaN and x = 1 by the scalar function. */
//SPEC: fdlibm e_atan2.c
atan2_lanes_64 :: fn[n: usize](y: vector[f64, n], x: vector[f64, n]) -> vector[f64, n] {
    hx :: lane_high(x)
    ix :: hx & 0x7fff_ffff
    hy :: lane_high(y)
    iy :: hy & 0x7fff_ffff
    infinity :: intrinsics.splat[vector[f64, n]](infinity_64())
    special :: (x != x) | (y != y) | (x == 0) | (y == 0) | (lane_magnitude(x) == infinity) | (lane_magnitude(y) == infinity)
        | (x == 1)
    safe_x :: intrinsics.select(special, intrinsics.splat[vector[f64, n]](2), x)
    safe_y :: intrinsics.select(special, intrinsics.splat[vector[f64, n]](1), y)
    m0 :: ((hy >> 31) & 1) | ((hx >> 30) & 2)
    k :: (iy - ix) >> 20
    far :: k > 60
    behind :: (hx < 0) & (k < -60)
    z :: intrinsics.select(far, intrinsics.splat[vector[f64, n]](PI_OVER_2_HI + 0.5 * PI_LO),
        intrinsics.select(behind, intrinsics.splat[vector[f64, n]](0), atan_lanes_64(lane_magnitude(safe_y / safe_x))))
    m :: intrinsics.select(far, m0 & 1, m0)
    result :: intrinsics.select(m == 0, z, intrinsics.select(m == 1, -z, intrinsics.select(m == 2, PI_64 - (z - PI_LO),
        (z - PI_LO) - PI_64)))
    return redo_lanes_64_2(result, y, x, special, atan2_64)
}

/** asin_64 on lanes: |x| from 1 by the scalar function. */
//SPEC: fdlibm e_asin.c
asin_lanes_64 :: fn[n: usize](x_in: vector[f64, n]) -> vector[f64, n] {
    hx :: lane_high(x_in)
    ix :: hx & 0x7fff_ffff
    special :: ix >= 0x3ff0_0000
    x :: intrinsics.select(special, intrinsics.splat[vector[f64, n]](0), x_in)
    tiny :: ix < 0x3e50_0000
    small :: ix < 0x3fe0_0000
    t0 :: x * x
    p0 :: t0 * (t0 * (t0 * (t0 * (t0 * (t0 * ASIN_P5 + ASIN_P4) + ASIN_P3) + ASIN_P2) + ASIN_P1) + ASIN_P0)
    q0 :: 1 + t0 * (t0 * (t0 * (t0 * ASIN_Q4 + ASIN_Q3) + ASIN_Q2) + ASIN_Q1)
    small_result :: x + x * (p0 / q0)
    w :: 1 - lane_magnitude(x)
    t :: w * 0.5
    p :: t * (t * (t * (t * (t * (t * ASIN_P5 + ASIN_P4) + ASIN_P3) + ASIN_P2) + ASIN_P1) + ASIN_P0)
    q :: 1 + t * (t * (t * (t * ASIN_Q4 + ASIN_Q3) + ASIN_Q2) + ASIN_Q1)
    r :: p / q
    s :: intrinsics.square_root(t)
    near_one :: PI_OVER_2_HI - (2.0 * (s + s * r) - PI_OVER_2_LO)
    df :: lane_cut(s)
    c :: (t - df * df) / (s + df)
    pp :: 2.0 * s * r - (PI_OVER_2_LO - 2.0 * c)
    qq :: ATAN_HI_1 - 2.0 * df
    middle :: ATAN_HI_1 - (pp - qq)
    large :: intrinsics.select(ix >= 0x3fef_3333, near_one, middle)
    signed :: intrinsics.select(hx > 0, large, -large)
    result :: intrinsics.select(tiny, x, intrinsics.select(small, small_result, signed))
    return redo_lanes_64(result, x_in, special, asin_64)
}

/** acos_64 on lanes: |x| from 1 by the scalar function. */
//SPEC: fdlibm e_acos.c
acos_lanes_64 :: fn[n: usize](x_in: vector[f64, n]) -> vector[f64, n] {
    hx :: lane_high(x_in)
    ix :: hx & 0x7fff_ffff
    special :: ix >= 0x3ff0_0000
    x :: intrinsics.select(special, intrinsics.splat[vector[f64, n]](0), x_in)
    small :: ix < 0x3fe0_0000
    z0 :: x * x
    r0 :: asin_rational_lanes(z0)
    small_result :: intrinsics.select(ix <= 0x3c60_0000, intrinsics.splat[vector[f64, n]](PI_OVER_2_HI + PI_OVER_2_LO),
        PI_OVER_2_HI - (x - (PI_OVER_2_LO - x * r0)))
    zn :: (1 + x) * 0.5
    sn :: intrinsics.square_root(zn)
    wn :: asin_rational_lanes(zn) * sn - PI_OVER_2_LO
    below :: PI_64 - 2.0 * (sn + wn)
    zp :: (1 - x) * 0.5
    sp :: intrinsics.square_root(zp)
    df :: lane_cut(sp)
    c :: (zp - df * df) / (sp + df)
    wp :: asin_rational_lanes(zp) * sp + c
    above :: 2.0 * (df + wp)
    result :: intrinsics.select(small, small_result, intrinsics.select(hx < 0, below, above))
    return redo_lanes_64(result, x_in, special, acos_64)
}

/** asin_rational_64 on lanes. */
asin_rational_lanes :: fn[n: usize](z: vector[f64, n]) -> vector[f64, n] {
    p :: z * (z * (z * (z * (z * (z * ASIN_P5 + ASIN_P4) + ASIN_P3) + ASIN_P2) + ASIN_P1) + ASIN_P0)
    q :: 1 + z * (z * (z * (z * ASIN_Q4 + ASIN_Q3) + ASIN_Q2) + ASIN_Q1)
    return p / q
}

/** An f64 in every lane. */
f64_lanes :: fn[n: usize](value: f64) -> vector[f64, n] {
    return intrinsics.splat[vector[f64, n]](value)
}

/** An i64 in every lane. */
i64_lanes :: fn[n: usize](value: i64) -> vector[i64, n] {
    return intrinsics.splat[vector[i64, n]](value)
}

/** exp2_64 on lanes: NaN, from 1024 and below -1075 by the scalar function. */
exp2_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    special :: (x != x) | (x >= 1024) | (x < -1075)
    safe :: intrinsics.select(special, f64_lanes[n](0), x)
    whole :: intrinsics.round_even(safe)
    fraction :: safe - whole
    hi :: fraction * LN2
    lo :: -(intrinsics.fused_multiply_add(fraction, f64_lanes[n](LN2), -hi) + fraction * LN2_TAIL)
    result :: exp_reduced_lanes(hi, lo, lane_whole(whole))
    return redo_lanes_64(result, x, special, exp2_64)
}

/** log_one_plus_kernel_64 on lanes. */
log_one_plus_kernel_lanes :: fn[n: usize](f: vector[f64, n]) -> vector[f64, n] {
    s :: f / (2.0 + f)
    z :: s * s
    w :: z * z
    t1 :: w * (w * (w * LOG_LG6 + LOG_LG4) + LOG_LG2)
    t2 :: z * (w * (w * (w * LOG_LG7 + LOG_LG5) + LOG_LG3) + LOG_LG1)
    r :: t2 + t1
    half_f_squared :: 0.5 * f * f
    return s * (half_f_squared + r)
}

/** log_split_64 on lanes, for positive normal lanes. */
log_split_lanes :: fn[n: usize](x: vector[f64, n]) -> (vector[i64, n], vector[f64, n]) {
    hx0 :: lane_high(x)
    k0 :: (hx0 >> 20) - 1023
    hx :: hx0 & 0x000f_ffff
    i :: (hx + 0x9_5f64) & 0x10_0000
    split :: lane_with_high(x, hx | (i ~ 0x3ff0_0000))
    return k0 + (i >> 20), split - 1.0
}

/**
 * log2_64 or log10_64 on lanes: zeros, negatives, subnormals, infinities and NaN by the scalar functions.
 *
 * @tparam n How many lanes.
 * @param x The arguments.
 * @param two True for log2, false for log10.
 * @return The logarithms.
 */
log_base_lanes :: fn[n: usize](x: vector[f64, n], two: bool) -> vector[f64, n] {
    high :: lane_high(x)
    special :: (high < 0x0010_0000) | (high >= 0x7ff0_0000)
    safe :: intrinsics.select(special, f64_lanes[n](2), x)
    k, f :: log_split_lanes(safe)
    y :: lane_float(k)
    half_f_squared :: 0.5 * f * f
    r :: log_one_plus_kernel_lanes(f)
    hi :: lane_cut(f - half_f_squared)
    lo :: (f - hi) - half_f_squared + r
    result := f64_lanes[n](0)
    if two {
        value_hi :: hi * INVERSE_LN2_HI
        value_lo :: (lo + hi) * INVERSE_LN2_LO + lo * INVERSE_LN2_HI
        w :: y + value_hi
        result = (value_lo + ((y - w) + value_hi)) + w
    }
    else {
        value_hi :: hi * INVERSE_LN10_HI
        y2 :: y * LOG10_2_HI
        value_lo :: y * LOG10_2_LO + (lo + hi) * INVERSE_LN10_LO + lo * INVERSE_LN10_HI
        w :: y2 + value_hi
        result = (value_lo + ((y2 - w) + value_hi)) + w
    }
    result = intrinsics.select(safe == 1, f64_lanes[n](0), result)
    if two {
        return redo_lanes_64(result, x, special, log2_64)
    }
    return redo_lanes_64(result, x, special, log10_64)
}

/** log2_64 on lanes. */
log2_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    return log_base_lanes(x, true)
}

/** log10_64 on lanes. */
log10_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    return log_base_lanes(x, false)
}

/** exp_minus_one_64 on lanes: from 56 ln 2 in magnitude, infinities and NaN by the scalar function. */
//SPEC: fdlibm s_expm1.c
exp_minus_one_lanes_64 :: fn[n: usize](x_in: vector[f64, n]) -> vector[f64, n] {
    hx :: lane_high(x_in) & 0x7fff_ffff
    negative :: x_in < 0
    special :: hx >= 0x4043_687a
    x0 :: intrinsics.select(special, f64_lanes[n](0), x_in)
    reduced :: hx > 0x3fd6_2e42
    near :: reduced & (hx < 0x3ff0_a2b2)
    tiny :: ~reduced & (hx < 0x3c90_0000)
    rounding :: intrinsics.select(negative, f64_lanes[n](-0.5), f64_lanes[n](0.5))
    k_far :: lane_whole(x0 * INVERSE_LN2 + rounding)
    t_far :: lane_float(k_far)
    hi :: intrinsics.select(near, intrinsics.select(negative, x0 + LN2_HI, x0 - LN2_HI), x0 - t_far * LN2_HI)
    lo :: intrinsics.select(near, intrinsics.select(negative, f64_lanes[n](-LN2_LO), f64_lanes[n](LN2_LO)), t_far * LN2_LO)
    k :: intrinsics.select(reduced, intrinsics.select(near, intrinsics.select(negative, i64_lanes[n](-1), i64_lanes[n](1)), k_far),
        i64_lanes[n](0))
    xr :: hi - lo
    x :: intrinsics.select(reduced, xr, x0)
    c :: intrinsics.select(reduced, (hi - xr) - lo, f64_lanes[n](0))
    half_x :: 0.5 * x
    half_x_squared :: x * half_x
    r1 :: 1 + half_x_squared * (half_x_squared * (half_x_squared * (half_x_squared * (half_x_squared * EXPM1_Q5 + EXPM1_Q4)
        + EXPM1_Q3) + EXPM1_Q2) + EXPM1_Q1)
    t :: 3.0 - r1 * half_x
    e0 :: half_x_squared * ((r1 - t) / (6.0 - x * t))
    at_zero :: x - (x * e0 - half_x_squared)
    e :: (x * (e0 - c) - c) - half_x_squared
    minus_one :: 0.5 * (x - e) - 0.5
    plus_one :: intrinsics.select(x < -0.25, -2.0 * (e - (x + 0.5)), 1 + 2.0 * (x - e))
    clamped_k :: clamp_lanes(k, -1022, 1023)
    scale :: lane_from_high(((clamped_k + 0x3ff) & 0x7ff) << 20)
    wide :: (1 - (e - x)) * scale - 1
    under_20 :: clamp_lanes(k, 0, 19)
    t_low :: lane_from_high(0x3ff0_0000 - (i64_lanes[n](0x20_0000) >> under_20))
    low :: (t_low - (e - x)) * scale
    from_20 :: clamp_lanes(k, 20, 56)
    t_high :: lane_from_high((0x3ff - from_20) << 20)
    high :: ((x - (e + t_high)) + 1) * scale
    general :: intrinsics.select((k <= -2) | (k > 56), wide, intrinsics.select(k < 20, low, high))
    result :: intrinsics.select(tiny, x0, intrinsics.select(k == 0, at_zero, intrinsics.select(k == -1, minus_one,
        intrinsics.select(k == 1, plus_one, general))))
    return redo_lanes_64(result, x_in, special, exp_minus_one_64)
}

/** log_one_plus_64 on lanes: from -1 down, infinities and NaN by the scalar function. */
//SPEC: fdlibm s_log1p.c
log_one_plus_lanes_64 :: fn[n: usize](x_in: vector[f64, n]) -> vector[f64, n] {
    hx :: lane_high(x_in)
    ax :: hx & 0x7fff_ffff
    special :: (x_in <= -1) | (hx >= 0x7ff0_0000) | (x_in != x_in)
    x :: intrinsics.select(special, f64_lanes[n](0.5), x_in)
    below :: hx < 0x3fda_827a
    tiny :: below & (ax < 0x3e20_0000)
    tiny_result :: intrinsics.select(ax < 0x3c90_0000, x, x - x * x * 0.5)
    // From √2/2 - 1 to √2 - 1, with no reduction: 0xbfd2bec4 as an i32
    unreduced :: below & ~tiny & ((hx > 0) | (hx <= -1076707644))
    huge :: hx >= 0x4340_0000
    u0 :: intrinsics.select(huge, x, 1.0 + x)
    hu0 :: lane_high(u0)
    k0 :: (hu0 >> 20) - 1023
    c0 :: intrinsics.select(huge, f64_lanes[n](0), intrinsics.select(k0 > 0, 1.0 - (u0 - x), x - (u0 - 1.0)) / u0)
    hu1 :: hu0 & 0x000f_ffff
    low :: hu1 < 0x6_a09e
    u :: intrinsics.select(low, lane_with_high(u0, hu1 | 0x3ff0_0000), lane_with_high(u0, hu1 | 0x3fe0_0000))
    k_reduced :: intrinsics.select(low, k0, k0 + 1)
    hu_reduced :: intrinsics.select(low, hu1, (0x0010_0000 - hu1) >> 2)
    k :: intrinsics.select(unreduced, i64_lanes[n](0), k_reduced)
    hu :: intrinsics.select(unreduced, i64_lanes[n](1), hu_reduced)
    c :: intrinsics.select(unreduced, f64_lanes[n](0), c0)
    f :: intrinsics.select(unreduced, x, u - 1.0)
    half_f_squared :: 0.5 * f * f
    dk :: lane_float(k)
    at_zero :: k == 0
    r_small :: half_f_squared * (1.0 - 0.66666666666666666 * f)
    small_result :: intrinsics.select(f == 0, intrinsics.select(at_zero, f64_lanes[n](0), dk * LN2_HI + (c + dk * LN2_LO)),
        intrinsics.select(at_zero, f - r_small, dk * LN2_HI - ((r_small - (dk * LN2_LO + c)) - f)))
    s :: f / (2.0 + f)
    z :: s * s
    r :: z * (z * (z * (z * (z * (z * (z * LOG_LG7 + LOG_LG6) + LOG_LG5) + LOG_LG4) + LOG_LG3) + LOG_LG2) + LOG_LG1)
    general :: intrinsics.select(at_zero, f - (half_f_squared - s * (half_f_squared + r)),
        dk * LN2_HI - ((half_f_squared - (s * (half_f_squared + r) + (dk * LN2_LO + c))) - f))
    result :: intrinsics.select(tiny, tiny_result, intrinsics.select(hu == 0, small_result, general))
    return redo_lanes_64(result, x_in, special, log_one_plus_64)
}

/** A 32-bit word divided by 3, in u64 lanes: a multiply and a shift, exact for every word. */
third_of_words :: fn[n: usize](word: vector[u64, n]) -> vector[u64, n] {
    return (word * 0xaaaa_aaab) >> 33
}

/** cube_root_64 on lanes. */
//SPEC: fdlibm s_cbrt.c, as FreeBSD has it
cube_root_lanes_64 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    bits :: lane_bits(x)
    sign :: (bits >> 32) & 0x8000_0000
    hx :: (bits >> 32) & 0x7fff_ffff
    special :: (hx >= 0x7ff0_0000) | ((bits << 1) == 0)
    safe :: intrinsics.select(special, f64_lanes[n](1), x)
    subnormal :: hx < 0x0010_0000
    scaled :: lane_from_high(i64_lanes[n](0x4350_0000)) * safe
    high_scaled :: (lane_bits(scaled) >> 32) & 0x7fff_ffff
    guess_high :: intrinsics.select(subnormal, sign | (third_of_words(high_scaled) + cast[u64](CUBE_ROOT_B2)),
        sign | (third_of_words(hx) + cast[u64](CUBE_ROOT_B1)))
    t0 :: bit_cast[vector[f64, n]](guess_high << 32)
    r0 :: (t0 * t0) * (t0 / safe)
    t1 :: t0 * ((r0 * (r0 * CUBE_ROOT_P2 + CUBE_ROOT_P1) + CUBE_ROOT_P0) + ((r0 * r0) * r0) * (r0 * CUBE_ROOT_P4 + CUBE_ROOT_P3))
    t :: bit_cast[vector[f64, n]]((lane_bits(t1) + 0x8000_0000) & 0xffff_ffff_c000_0000)
    s :: t * t
    r1 :: safe / s
    w :: t + t
    r :: (r1 - t) / (w + r1)
    result :: t + t * r
    return intrinsics.select(special, x + x, result)
}

/** hypotenuse_64 on lanes. */
//SPEC: musl src/math/hypot.c
hypotenuse_lanes_64 :: fn[n: usize](x_in: vector[f64, n], y_in: vector[f64, n]) -> vector[f64, n] {
    ux0 :: lane_bits(x_in) & 0x7fff_ffff_ffff_ffff
    uy0 :: lane_bits(y_in) & 0x7fff_ffff_ffff_ffff
    swap :: ux0 < uy0
    ux :: intrinsics.select(swap, uy0, ux0)
    uy :: intrinsics.select(swap, ux0, uy0)
    ex :: bit_cast[vector[i64, n]](ux >> 52)
    ey :: bit_cast[vector[i64, n]](uy >> 52)
    x0 :: bit_cast[vector[f64, n]](ux)
    y0 :: bit_cast[vector[f64, n]](uy)
    big :: ex > 0x3ff + 510
    small :: ~big & (ey < 0x3ff - 450)
    z :: intrinsics.select(big, f64_lanes[n](power_of_two_64(700)), intrinsics.select(small, f64_lanes[n](power_of_two_64(-700)),
        f64_lanes[n](1.0)))
    factor :: intrinsics.select(big, f64_lanes[n](power_of_two_64(-700)), intrinsics.select(small, f64_lanes[n](power_of_two_64(700)),
        f64_lanes[n](1.0)))
    x :: intrinsics.select(big | small, x0 * factor, x0)
    y :: intrinsics.select(big | small, y0 * factor, y0)
    xc :: x * HYPOTENUSE_SPLIT
    xh :: x - xc + xc
    xl :: x - xh
    hx :: x * x
    lx :: xh * xh - hx + 2 * xh * xl + xl * xl
    yc :: y * HYPOTENUSE_SPLIT
    yh :: y - yc + yc
    yl :: y - yh
    hy :: y * y
    ly :: yh * yh - hy + 2 * yh * yl + yl * yl
    result :: z * intrinsics.square_root(ly + lx + hy + hx)
    return intrinsics.select(ey == 0x7ff, y0, intrinsics.select((ex == 0x7ff) | (uy == 0), x0,
        intrinsics.select(ex - ey > 64, x0 + y0, result)))
}

/** i64 lanes clamped to from low to high. */
clamp_lanes :: fn[n: usize](k: vector[i64, n], low: i64, high: i64) -> vector[i64, n] {
    above :: intrinsics.select(k < low, i64_lanes[n](low), k)
    return intrinsics.select(above > high, i64_lanes[n](high), above)
}

/**
 * power_64 on lanes. The kernel takes a normal x to a y under 2^30 in magnitude, whole if x is negative, with a normal
 * result; the scalar function does the rest: y of 0, ±1, 2 or 1/2, x of 0, ±1 or infinity, a subnormal x, NaN, and
 * results that overflow, underflow or are subnormal.
 *
 * @tparam n How many lanes.
 * @param x_in The bases.
 * @param y_in The powers.
 * @return x^y in each lane, the scalar function's bits.
 */
//SPEC: fdlibm e_pow.c
power_lanes_64 :: fn[n: usize](x_in: vector[f64, n], y_in: vector[f64, n]) -> vector[f64, n] {
    hx_in :: lane_high(x_in)
    ix_in :: hx_in & 0x7fff_ffff
    iy :: lane_high(y_in) & 0x7fff_ffff
    negative_x :: hx_in < 0
    y_bounded :: (iy < 0x41d0_0000) & (y_in == y_in)
    whole_part :: lane_whole(intrinsics.select(y_bounded, y_in, f64_lanes[n](3)))
    whole :: lane_float(whole_part) == y_in
    special :: ~y_bounded | (x_in != x_in) | (y_in == 0) | (y_in == 1) | (y_in == -1) | (y_in == 2) | (y_in == 0.5)
        | (ix_in < 0x0010_0000) | (ix_in >= 0x7ff0_0000) | (x_in == 1) | (x_in == -1) | (negative_x & ~whole)
    negative :: negative_x & ((whole_part & 1) != 0)
    x :: intrinsics.select(special, f64_lanes[n](2), x_in)
    y :: intrinsics.select(special, f64_lanes[n](3), y_in)
    ax0 :: bit_cast[vector[f64, n]](lane_bits(x) & 0x7fff_ffff_ffff_ffff)
    ix0 :: lane_high(ax0)
    // ax from 1 to 2, and whether it's nearer 1.5 than 1 or 2
    j0 :: ix0 & 0x000f_ffff
    low :: j0 <= 0x3_988e
    middle :: ~low & (j0 < 0xb_b67a)
    high :: ~low & ~middle
    n0 :: (ix0 >> 20) - 0x3ff
    exponent :: intrinsics.select(high, n0 + 1, n0)
    ix :: intrinsics.select(high, (j0 | 0x3ff0_0000) - 0x0010_0000, j0 | 0x3ff0_0000)
    k :: intrinsics.select(middle, i64_lanes[n](1), i64_lanes[n](0))
    ax :: lane_with_high(ax0, ix)
    bp :: intrinsics.select(middle, f64_lanes[n](1.5), f64_lanes[n](1.0))
    dp_h :: intrinsics.select(middle, f64_lanes[n](POW_DP_H), f64_lanes[n](0))
    dp_l :: intrinsics.select(middle, f64_lanes[n](POW_DP_L), f64_lanes[n](0))
    // s = s_h + s_l = (x - 1) / (x + 1) or (x - 1.5) / (x + 1.5)
    u0 :: ax - bp
    v0 :: 1 / (ax + bp)
    ss :: u0 * v0
    s_h :: lane_cut(ss)
    t_h0 :: lane_from_high(((ix >> 1) | 0x2000_0000) + 0x0008_0000 + (k << 18))
    t_l0 :: ax - (t_h0 - bp)
    s_l :: v0 * ((u0 - s_h * t_h0) - s_h * t_l0)
    // log(ax)
    s2 :: ss * ss
    r0 :: s2 * s2 * (s2 * (s2 * (s2 * (s2 * (s2 * POW_L6 + POW_L5) + POW_L4) + POW_L3) + POW_L2) + POW_L1)
    r :: r0 + s_l * (s_h + ss)
    s_h_squared :: s_h * s_h
    t_h :: lane_cut(3.0 + s_h_squared + r)
    t_l :: r - ((t_h - 3.0) - s_h_squared)
    u1 :: s_h * t_h
    v1 :: s_l * t_h + t_l * ss
    p_h0 :: lane_cut(u1 + v1)
    p_l0 :: v1 - (p_h0 - u1)
    z_h :: p_h0 * POW_CP_H
    z_l :: p_h0 * POW_CP_L + p_l0 * POW_CP + dp_l
    t0 :: lane_float(exponent)
    t1 :: lane_cut(((z_h + z_l) + dp_h) + t0)
    t2 :: z_l - (((t1 - t0) - dp_h) - z_h)
    // y split into y1 + y2, so y1 × t1 is exact
    y1 :: lane_cut(y)
    p_l :: (y - y1) * t1 + y * t2
    p_h1 :: y1 * t1
    z0 :: p_l + p_h1
    j :: lane_high(z0)
    out_of_range :: (j >= 0x4090_0000) | ((j & 0x7fff_ffff) >= 0x4090_cc00)
    // 2^(p_h + p_l): z = scale + p_h, |p_h| at most a half
    i :: j & 0x7fff_ffff
    big :: i > 0x3fe0_0000
    k1 :: clamp_lanes((i >> 20) - 0x3ff, -1, 19)
    rounded :: j + (i64_lanes[n](0x0010_0000) >> (k1 + 1))
    k2 :: clamp_lanes(((rounded & 0x7fff_ffff) >> 20) - 0x3ff, 0, 20)
    whole_high :: lane_from_high(rounded & ~(i64_lanes[n](0x000f_ffff) >> k2))
    magnitude :: ((rounded & 0x000f_ffff) | 0x0010_0000) >> (20 - k2)
    scale :: intrinsics.select(big, intrinsics.select(j < 0, -magnitude, magnitude), i64_lanes[n](0))
    p_h :: intrinsics.select(big, p_h1 - whole_high, p_h1)
    t :: lane_cut(p_l + p_h)
    u :: t * POW_LG2_H
    v :: (p_l - (t - p_h)) * LN2 + t * POW_LG2_L
    z1 :: u + v
    w :: v - (z1 - u)
    tt :: z1 * z1
    t3 :: z1 - tt * (tt * (tt * (tt * (tt * EXP_P5 + EXP_P4) + EXP_P3) + EXP_P2) + EXP_P1)
    r1 :: (z1 * t3) / (t3 - 2.0) - (w + z1 * w)
    z :: 1 - (r1 - z1)
    result_high :: lane_high(z) + (scale << 20)
    subnormal :: (result_high >> 20) <= 0
    magnitude_result :: lane_with_high(z, result_high)
    result :: intrinsics.select(negative, -magnitude_result, magnitude_result)
    return redo_lanes_64_2(result, x_in, y_in, special | out_of_range | subnormal, power_64)
}
