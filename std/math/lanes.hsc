package math

import intrinsics from "base"

/*
 * Kernels on f64 lanes for f32's functions (decisions recorded with the project: f32's own kernels): each takes and
 * gives f32 lanes, and works inside in f64, where a short polynomial, sized for 24 bits rather than 53, keeps the
 * error far under an f32 ulp, so rounding to f32 once is within 1 ulp. They're branch-free over the lanes; a lane a
 * kernel's reduction doesn't cover, like sin of a huge number, or the special cases of power and atan2, is worked
 * out again exactly, by the f64 function, after the others.
 *
 * n is how many lanes; a scalar f32 runs as one lane.
 */

/** 1 / ln 2. */
LANE_INVERSE_LN2 :: 1.44269504088896340735992468100189213742664595415299
/** ln 2. */
LANE_LN2 :: 0.69314718055994530941723212145817656807550013436026
/** log10 2. */
LANE_LOG10_2 :: 0.30102999566398119521373889472449302676818988146211
/** log10 e. */
LANE_LOG10_E :: 0.43429448190325182765112891891660508229439700580366
/** log2 e. */
LANE_LOG2_E :: 1.44269504088896340735992468100189213742664595415299
/** 2 / π. */
LANE_TWO_OVER_PI :: 0.63661977236758134307553505349005744813783858296183
/** π/2 rounded to f64, and what's left of it, so q π/2 is subtracted with fused multiply-adds to 106 bits. */
LANE_PI_OVER_2_HI :: 1.5707963267948965579989817342720925807952880859375
LANE_PI_OVER_2_LO :: 6.123233995736766035868820147291818e-17
/** π, π/2 and π/6. */
LANE_PI :: 3.14159265358979323846264338327950288419716939937510
LANE_PI_OVER_2 :: 1.57079632679489661923132169163975144209858469968755
LANE_PI_OVER_6 :: 0.52359877559829887307710723054658381403286156656252
/** tan(π/12), where atan's second reduction starts, and √3. */
LANE_TAN_PI_OVER_12 :: 0.26794919243112270647255365849412763305719474618962
LANE_SQRT_3 :: 1.73205080756887729352744634150587236694280525381038
/** The bits of √2 / 2, less than which a significand is doubled, so log's is from √2/2 to √2. */
LANE_SQRT_HALF_BITS :: 0x3fe6_a09e_667f_3bcd
/** How large an argument sin, cos and tan reduce in the kernel: past it, the f64 function. */
LANE_TRIG_LIMIT :: 16777216.0

/**
 * Give one value in every lane of an f64 vector.
 *
 * @tparam n How many lanes.
 * @param value The value.
 * @return value, n times.
 */
lanes_of :: fn[n: usize](value: f64) -> vector[f64, n] {
    return intrinsics.splat[vector[f64, n]](value)
}

/**
 * f64 lanes' magnitudes.
 *
 * @tparam n How many lanes.
 * @param x The lanes.
 * @return Each without its sign bit.
 */
lane_magnitude :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    return bit_cast[vector[f64, n]](bit_cast[vector[u64, n]](x) & 0x7fff_ffff_ffff_ffff)
}

/**
 * 2^k for whole k in f64 lanes, from -1022 to 1023.
 *
 * @tparam n How many lanes.
 * @param k The powers, whole numbers in that range.
 * @return 2^k in each lane, exactly.
 */
lane_power_of_two :: fn[n: usize](k: vector[f64, n]) -> vector[f64, n] {
    whole :: cast[vector[i64, n]](k) + 1023
    return bit_cast[vector[f64, n]](bit_cast[vector[u64, n]](whole) << 52)
}

/**
 * e^r for |r| up to ln 2 / 2: its Taylor series to r^8, within 2^-31 of it relatively.
 *
 * @tparam n How many lanes.
 * @param r The reduced powers.
 * @return e^r in each lane.
 */
lane_exp_series :: fn[n: usize](r: vector[f64, n]) -> vector[f64, n] {
    p := r * (1.0 / 40320.0) + 1.0 / 5040.0
    p = p * r + 1.0 / 720.0
    p = p * r + 1.0 / 120.0
    p = p * r + 1.0 / 24.0
    p = p * r + 1.0 / 6.0
    p = p * r + 0.5
    p = p * r + 1.0
    return p * r + 1.0
}

/**
 * e^x in f64 lanes, for f32's results: within 2^-30 of it relatively, for x from -150 to 150 (beyond, clamped there,
 * which f32 rounds to 0 or infinity anyway). NaN lanes give NaN.
 *
 * @tparam n How many lanes.
 * @param x The powers.
 * @return e^x in each lane.
 */
lane_exp :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    clamped :: intrinsics.minimum(intrinsics.maximum(x, lanes_of[n](-150)), lanes_of[n](150))
    // NaN's lanes reduced as 0, and given back as NaN after
    safe :: intrinsics.select(clamped == clamped, clamped, lanes_of[n](0))
    k :: intrinsics.round_even(safe * LANE_INVERSE_LN2)
    r :: safe - k * LANE_LN2
    result :: lane_exp_series(r) * lane_power_of_two(k)
    return intrinsics.select(x == x, result, x)
}

/**
 * 2^x in f64 lanes, for f32's results: within 2^-30 of it relatively, exact for whole x, from -160 to 160 (beyond,
 * clamped). NaN lanes give NaN.
 *
 * @tparam n How many lanes.
 * @param x The powers.
 * @return 2^x in each lane.
 */
lane_exp2 :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    clamped :: intrinsics.minimum(intrinsics.maximum(x, lanes_of[n](-160)), lanes_of[n](160))
    safe :: intrinsics.select(clamped == clamped, clamped, lanes_of[n](0))
    k :: intrinsics.round_even(safe)
    result :: lane_exp_series((safe - k) * LANE_LN2) * lane_power_of_two(k)
    return intrinsics.select(x == x, result, x)
}

/**
 * Split positive normal f64 lanes into k and f, x = 2^k (1 + f), 1 + f from √2/2 to √2, and give ln(1 + f) - f's
 * companion: s = f / (2 + f), from which ln(1 + f) = 2 atanh(s).
 *
 * @tparam n How many lanes.
 * @param x The numbers: positive and normal.
 * @return k as a float, and s.
 */
lane_log_split :: fn[n: usize](x: vector[f64, n]) -> (vector[f64, n], vector[f64, n]) {
    bits :: bit_cast[vector[u64, n]](x)
    shifted :: bits - LANE_SQRT_HALF_BITS
    k :: cast[vector[f64, n]](bit_cast[vector[i64, n]](shifted) >> 52)
    significand :: bit_cast[vector[f64, n]](bits - (shifted & 0xfff0_0000_0000_0000))
    f :: significand - 1
    return k, f / (f + 2)
}

/**
 * 2 atanh(s) for |s| up to 3 - 2√2: ln(1 + f) for s = f / (2 + f), by its series to s^11, within 2^-34 of it
 * relatively.
 *
 * @tparam n How many lanes.
 * @param s The reduced arguments.
 * @return 2 atanh(s) in each lane.
 */
lane_log_series :: fn[n: usize](s: vector[f64, n]) -> vector[f64, n] {
    z :: s * s
    p := z * (1.0 / 11.0) + 1.0 / 9.0
    p = p * z + 1.0 / 7.0
    p = p * z + 1.0 / 5.0
    p = p * z + 1.0 / 3.0
    p = p * z + 1.0
    return 2 * s * p
}

/**
 * The same series to s^17, within 2^-48 relatively, for power, whose result's error is its argument's times the power.
 *
 * @tparam n How many lanes.
 * @param s The reduced arguments.
 * @return 2 atanh(s) in each lane.
 */
lane_log_series_long :: fn[n: usize](s: vector[f64, n]) -> vector[f64, n] {
    z :: s * s
    p := z * (1.0 / 17.0) + 1.0 / 15.0
    p = p * z + 1.0 / 13.0
    p = p * z + 1.0 / 11.0
    p = p * z + 1.0 / 9.0
    p = p * z + 1.0 / 7.0
    p = p * z + 1.0 / 5.0
    p = p * z + 1.0 / 3.0
    p = p * z + 1.0
    return 2 * s * p
}

/**
 * What a logarithm gives for lanes it has no finite value at: -infinity at ±0, NaN below 0 and for NaN, infinity for
 * infinity; and the other lanes' result as it is.
 *
 * @tparam n How many lanes.
 * @param x The arguments.
 * @param result What the kernel gave, right where x is positive and finite.
 * @return result, with those lanes replaced.
 */
lane_log_special :: fn[n: usize](x: vector[f64, n], result: vector[f64, n]) -> vector[f64, n] {
    infinity :: lanes_of[n](infinity_64())
    with_zero :: intrinsics.select(x == 0, -infinity, result)
    with_negative :: intrinsics.select(x < 0, lanes_of[n](nan_64()), with_zero)
    with_infinity :: intrinsics.select(x == infinity, infinity, with_negative)
    return intrinsics.select(x == x, with_infinity, x)
}

/**
 * Lanes a logarithm's kernel can split: positive and finite, the others as 1, which the special cases replace.
 *
 * @tparam n How many lanes.
 * @param x The arguments.
 * @return x where it's positive and finite, 1 elsewhere.
 */
lane_log_input :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    return intrinsics.select((x > 0) & (x < lanes_of[n](infinity_64())), x, lanes_of[n](1))
}

/**
 * sin r and cos r for |r| up to π/4, by fdlibm's polynomials cut to what f32 needs: within 2^-40 relatively.
 *
 * @tparam n How many lanes.
 * @param r The reduced angles.
 * @return sin r, and cos r.
 */
lane_sin_cos_kernel :: fn[n: usize](r: vector[f64, n]) -> (vector[f64, n], vector[f64, n]) {
    z :: r * r
    s := z * lanes_of[n](SIN_S6) + lanes_of[n](SIN_S5)
    s = s * z + lanes_of[n](SIN_S4)
    s = s * z + lanes_of[n](SIN_S3)
    s = s * z + lanes_of[n](SIN_S2)
    s = s * z + lanes_of[n](SIN_S1)
    c := z * lanes_of[n](COS_C6) + lanes_of[n](COS_C5)
    c = c * z + lanes_of[n](COS_C4)
    c = c * z + lanes_of[n](COS_C3)
    c = c * z + lanes_of[n](COS_C2)
    c = c * z + lanes_of[n](COS_C1)
    return r + r * z * s, 1 - 0.5 * z + z * z * c
}

/**
 * Reduce angles by π/2 for the trigonometric kernels: x - q π/2 with q whole, the subtraction to 106 bits of π/2.
 *
 * @tparam n How many lanes.
 * @param x The angles: within LANE_TRIG_LIMIT, and finite; others reduce to nonsense, and are redone.
 * @return The reduced angle, from -π/4 to π/4, and q modulo 4.
 */
lane_reduce :: fn[n: usize](x: vector[f64, n]) -> (vector[f64, n], vector[i64, n]) {
    q :: intrinsics.round_even(x * LANE_TWO_OVER_PI)
    r :: intrinsics.fused_multiply_add(q, lanes_of[n](-LANE_PI_OVER_2_HI), x)
    reduced :: intrinsics.fused_multiply_add(q, lanes_of[n](-LANE_PI_OVER_2_LO), r)
    return reduced, cast[vector[i64, n]](q) & 3
}

/**
 * Which lanes the trigonometric kernels reduce: finite and within LANE_TRIG_LIMIT.
 *
 * @tparam n How many lanes.
 * @param x The angles.
 * @return True for each lane they cover.
 */
lane_trig_covers :: fn[n: usize](x: vector[f64, n]) -> vector[bool, n] {
    return lane_magnitude(x) < LANE_TRIG_LIMIT
}

/**
 * atan x in f64 lanes, within 2^-34 relatively: |x| > 1 by π/2 - atan(1/x), then above tan(π/12) by π/6 + atan of
 * (x√3 - 1) / (x + √3), leaving at most tan(π/12), for its series to x^15.
 *
 * @tparam n How many lanes.
 * @param x The tangents, any: ±infinity gives ±π/2, NaN NaN.
 * @return atan x in each lane.
 */
lane_atan :: fn[n: usize](x: vector[f64, n]) -> vector[f64, n] {
    t := lane_magnitude(x)
    inverted :: t > 1
    t = intrinsics.select(inverted, 1 / t, t)
    shifted :: t > LANE_TAN_PI_OVER_12
    t = intrinsics.select(shifted, (t * LANE_SQRT_3 - 1) / (t + LANE_SQRT_3), t)
    z :: t * t
    p := z * (-1.0 / 15.0) + 1.0 / 13.0
    p = p * z - 1.0 / 11.0
    p = p * z + 1.0 / 9.0
    p = p * z - 1.0 / 7.0
    p = p * z + 1.0 / 5.0
    p = p * z - 1.0 / 3.0
    angle := t + t * z * p + intrinsics.select(shifted, lanes_of[n](LANE_PI_OVER_6), lanes_of[n](0))
    angle = intrinsics.select(inverted, LANE_PI_OVER_2 - angle, angle)
    return intrinsics.copy_sign(angle, x)
}

/**
 * Work some lanes out again with an exact scalar function, the ones a kernel doesn't cover.
 *
 * @tparam n How many lanes.
 * @param result What the kernel gave.
 * @param x The arguments.
 * @param redo Which lanes to work out again.
 * @param exact The function for them.
 * @return result, with those lanes exact's.
 */
redo_lanes :: fn[n: usize](result: vector[f32, n], x: vector[f32, n], redo: vector[bool, n], exact: (fn(x: f32) -> f32))
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

/**
 * The same for a function of two arguments.
 *
 * @tparam n How many lanes.
 * @param result What the kernel gave.
 * @param x The first arguments.
 * @param y The second.
 * @param redo Which lanes to work out again.
 * @param exact The function for them.
 * @return result, with those lanes exact's.
 */
redo_lanes_2 :: fn[n: usize](result: vector[f32, n], x: vector[f32, n], y: vector[f32, n], redo: vector[bool, n],
    exact: (fn(x: f32, y: f32) -> f32)) -> vector[f32, n] {

    if !intrinsics.any_true(redo) {
        return result
    }
    lanes := bit_cast[f32[n]](result)
    first :: bit_cast[f32[n]](x)
    second :: bit_cast[f32[n]](y)
    flags :: bit_cast[u8[n]](redo)
    for i in 0..<n {
        if flags[i] != 0 {
            lanes[i] = exact(first[i], second[i])
        }
    }
    return bit_cast[vector[f32, n]](lanes)
}

/** f32 lanes widened to f64. */
widened :: fn[n: usize](x: vector[f32, n]) -> vector[f64, n] {
    return cast[vector[f64, n]](x)
}

/** f64 lanes rounded to f32, once. */
narrowed :: fn[n: usize](x: vector[f64, n]) -> vector[f32, n] {
    return cast[vector[f32, n]](x)
}

/* The f32 functions on lanes, each within 1 ulp; each one's scalar is its lanes at n = 1 */

/** e^x on f32 lanes. */
exp_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    return narrowed(lane_exp(widened(x)))
}

/** 2^x on f32 lanes. */
exp2_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    return narrowed(lane_exp2(widened(x)))
}

/** e^x - 1 on f32 lanes: the series below 0.35, exp(x) - 1 above, where it loses under 2 bits of 30. */
exp_minus_one_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    w :: widened(x)
    p := w * (1.0 / 3628800.0) + 1.0 / 362880.0
    p = p * w + 1.0 / 40320.0
    p = p * w + 1.0 / 5040.0
    p = p * w + 1.0 / 720.0
    p = p * w + 1.0 / 120.0
    p = p * w + 1.0 / 24.0
    p = p * w + 1.0 / 6.0
    p = p * w + 0.5
    small :: w + w * w * p
    result :: intrinsics.select(lane_magnitude(w) < 0.35, small, lane_exp(w) - 1)
    return narrowed(result)
}

/** ln x on f32 lanes. */
log_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    w :: widened(x)
    k, s :: lane_log_split(lane_log_input(w))
    return narrowed(lane_log_special(w, k * LANE_LN2 + lane_log_series(s)))
}

/** log2 x on f32 lanes: exact for powers of two. */
log2_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    w :: widened(x)
    k, s :: lane_log_split(lane_log_input(w))
    return narrowed(lane_log_special(w, k + lane_log_series(s) * LANE_LOG2_E))
}

/** log10 x on f32 lanes. */
log10_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    w :: widened(x)
    k, s :: lane_log_split(lane_log_input(w))
    return narrowed(lane_log_special(w, k * LANE_LOG10_2 + lane_log_series(s) * LANE_LOG10_E))
}

/**
 * ln(1 + x) on f32 lanes: below 1/64 in magnitude, its own series, where 1 + x in f64 would round away what x is;
 * above, ln of 1 + x, which f64 holds exactly for an f32 x that large.
 */
log_one_plus_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    w :: widened(x)
    one_plus :: w + 1
    k, s :: lane_log_split(lane_log_input(one_plus))
    result :: lane_log_special(one_plus, k * LANE_LN2 + lane_log_series(s))
    p := w * (1.0 / 7.0) - 1.0 / 6.0
    p = p * w + 1.0 / 5.0
    p = p * w - 1.0 / 4.0
    p = p * w + 1.0 / 3.0
    p = p * w - 0.5
    small :: w + w * w * p
    return narrowed(intrinsics.select(lane_magnitude(w) < 0.015625, small, result))
}

/** x^y on f32 lanes: 2^(y log2 x), log2 x to 2^-48; a lane with x not positive and finite, or y not finite, exactly. */
power_lanes_32 :: fn[n: usize](x: vector[f32, n], y: vector[f32, n]) -> vector[f32, n] {
    w :: widened(x)
    v :: widened(y)
    infinity :: lanes_of[n](infinity_64())
    covered :: (w > 0) & (w < infinity) & (lane_magnitude(v) < infinity)
    k, s :: lane_log_split(intrinsics.select(covered, w, lanes_of[n](1)))
    log2 :: k + lane_log_series_long(s) * LANE_LOG2_E
    result :: narrowed(lane_exp2(intrinsics.select(covered, v, lanes_of[n](0)) * log2))
    return redo_lanes_2(result, x, y, ~covered, power_exact_32)
}

/** sin x on f32 lanes; past LANE_TRIG_LIMIT, and infinite or NaN, exactly. */
sin_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    w :: widened(x)
    covers :: lane_trig_covers(w)
    r, quadrant :: lane_reduce(intrinsics.select(covers, w, lanes_of[n](0)))
    s, c :: lane_sin_cos_kernel(r)
    swapped :: intrinsics.select((quadrant & 1) == 1, c, s)
    result :: narrowed(intrinsics.select((quadrant & 2) == 2, -swapped, swapped))
    return redo_lanes(result, x, ~covers, sin_exact_32)
}

/** cos x on f32 lanes; past LANE_TRIG_LIMIT, and infinite or NaN, exactly. */
cos_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    w :: widened(x)
    covers :: lane_trig_covers(w)
    r, quadrant :: lane_reduce(intrinsics.select(covers, w, lanes_of[n](0)))
    s, c :: lane_sin_cos_kernel(r)
    swapped :: intrinsics.select((quadrant & 1) == 1, s, c)
    negated :: ((quadrant + 1) & 2) == 2
    result :: narrowed(intrinsics.select(negated, -swapped, swapped))
    return redo_lanes(result, x, ~covers, cos_exact_32)
}

/** sin x and cos x on f32 lanes, reducing x once; each lane as sin_lanes_32 and cos_lanes_32 give it. */
sin_cos_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> (vector[f32, n], vector[f32, n]) {
    w :: widened(x)
    covers :: lane_trig_covers(w)
    r, quadrant :: lane_reduce(intrinsics.select(covers, w, lanes_of[n](0)))
    s, c :: lane_sin_cos_kernel(r)
    odd :: (quadrant & 1) == 1
    sine :: intrinsics.select(odd, c, s)
    cosine :: intrinsics.select(odd, s, c)
    sin_result :: narrowed(intrinsics.select((quadrant & 2) == 2, -sine, sine))
    cos_result :: narrowed(intrinsics.select(((quadrant + 1) & 2) == 2, -cosine, cosine))
    return redo_lanes(sin_result, x, ~covers, sin_exact_32), redo_lanes(cos_result, x, ~covers, cos_exact_32)
}

/** tan x on f32 lanes: sin over cos of the reduced angle, in f64; past LANE_TRIG_LIMIT, exactly. */
tan_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    w :: widened(x)
    covers :: lane_trig_covers(w)
    r, quadrant :: lane_reduce(intrinsics.select(covers, w, lanes_of[n](0)))
    s, c :: lane_sin_cos_kernel(r)
    odd :: (quadrant & 1) == 1
    result :: narrowed(intrinsics.select(odd, -c / s, s / c))
    return redo_lanes(result, x, ~covers, tan_exact_32)
}

/** atan x on f32 lanes. */
atan_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    return narrowed(lane_atan(widened(x)))
}

/** atan2(y, x) on f32 lanes: atan(y / x) and its quadrant; zeros, infinities and NaNs exactly. */
atan2_lanes_32 :: fn[n: usize](y: vector[f32, n], x: vector[f32, n]) -> vector[f32, n] {
    v :: widened(y)
    w :: widened(x)
    infinity :: lanes_of[n](infinity_64())
    covered :: (lane_magnitude(v) < infinity) & (lane_magnitude(w) < infinity) & (v != 0) & (w != 0)
    safe_x :: intrinsics.select(covered, w, lanes_of[n](1))
    angle :: lane_atan(intrinsics.select(covered, v, lanes_of[n](0)) / safe_x)
    turned :: angle + intrinsics.copy_sign(lanes_of[n](LANE_PI), v)
    result :: narrowed(intrinsics.select(safe_x < 0, turned, angle))
    return redo_lanes_2(result, y, x, ~covered, atan2_exact_32)
}

/** asin x on f32 lanes: atan(x / √(1 - x²)), the root of (1 - x)(1 + x), exact enough in f64. */
asin_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    w :: widened(x)
    root :: intrinsics.square_root((1 - w) * (1 + w))
    return narrowed(lane_atan(w / root))
}

/** acos x on f32 lanes: 2 atan(√((1 - x) / (1 + x))). */
acos_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    w :: widened(x)
    return narrowed(2 * lane_atan(intrinsics.square_root((1 - w) / (1 + w))))
}

/* A quadratic within 2^-4.7 of ∛m for m from 1 to 8, fitted to the relative error, for Halley's method to start from */
CUBE_ROOT_GUESS_0 :: 0.8016089816964066
CUBE_ROOT_GUESS_1 :: 0.24782040881609507
CUBE_ROOT_GUESS_2 :: -0.01272919718268901

/**
 * ∛x on f32 lanes: |x| = m × 2^(3q), m from 1 to 8, and ∛m from a quadratic guess by two steps of Halley's method,
 * each tripling its bits, to 2^-45; with x's sign. Zeros, infinities and NaN as they are.
 */
cube_root_lanes_32 :: fn[n: usize](x: vector[f32, n]) -> vector[f32, n] {
    w :: widened(x)
    magnitude :: lane_magnitude(w)
    infinity :: lanes_of[n](infinity_64())
    covered :: (magnitude > 0) & (magnitude < infinity)
    bits :: bit_cast[vector[u64, n]](intrinsics.select(covered, magnitude, lanes_of[n](1)))
    exponent :: cast[vector[f64, n]](bit_cast[vector[i64, n]]((bits >> 52) & 0x7ff)) - 1023
    q :: intrinsics.floor(exponent * (1.0 / 3.0))
    m :: bit_cast[vector[f64, n]]((bits & 0x000f_ffff_ffff_ffff) | 0x3ff0_0000_0000_0000) * lane_power_of_two(exponent - 3 * q)
    y := (m * CUBE_ROOT_GUESS_2 + CUBE_ROOT_GUESS_1) * m + CUBE_ROOT_GUESS_0
    cube := y * y * y
    y = y * (cube + 2 * m) / (2 * cube + m)
    cube = y * y * y
    y = y * (cube + 2 * m) / (2 * cube + m)
    root :: y * lane_power_of_two(q)
    return narrowed(intrinsics.select(covered, intrinsics.copy_sign(root, w), w))
}

/** √(x² + y²) on f32 lanes: exact squares in f64, rounded once each way; infinite if either is, even with a NaN. */
hypotenuse_lanes_32 :: fn[n: usize](x: vector[f32, n], y: vector[f32, n]) -> vector[f32, n] {
    w :: widened(x)
    v :: widened(y)
    infinity :: lanes_of[n](infinity_64())
    result :: intrinsics.square_root(w * w + v * v)
    either :: (lane_magnitude(w) == infinity) | (lane_magnitude(v) == infinity)
    return narrowed(intrinsics.select(either, infinity, result))
}

/* The exact scalar paths, through f64, for the lanes the kernels don't cover */

sin_exact_32 :: fn(x: f32) -> f32 {
    return cast[f32](sin_64(cast[f64](x)))
}

cos_exact_32 :: fn(x: f32) -> f32 {
    return cast[f32](cos_64(cast[f64](x)))
}

tan_exact_32 :: fn(x: f32) -> f32 {
    return cast[f32](tan_64(cast[f64](x)))
}

power_exact_32 :: fn(x: f32, y: f32) -> f32 {
    return cast[f32](power_64(cast[f64](x), cast[f64](y)))
}

atan2_exact_32 :: fn(y: f32, x: f32) -> f32 {
    return cast[f32](atan2_64(cast[f64](y), cast[f64](x)))
}
