package math

import intrinsics from "base"
import runtime from "base"

/*
 * The public functions, each on an f32 or an f64: F is the type, worked out from the argument. An f64 is worked on as
 * it is; an f32 is widened to f64, worked on there, and the result rounded to f32 once.
 */

/** π. */
PI :: 3.14159265358979323846264338327950288419716939937510
/** 2π, a whole turn. */
TAU :: 6.28318530717958647692528676655900576839433879875021
/** e, the base of natural logarithms. */
E :: 2.71828182845904523536028747135266249775724709369996
/** ln 2. */
LN_2 :: 0.69314718055994530941723212145817656807550013436026
/** ln 10. */
LN_10 :: 2.30258509299404568401799145468436420760110148862877
/** log2 e, 1 / ln 2. */
LOG2_E :: 1.44269504088896340735992468100189213742664595415299
/** log10 e, 1 / ln 10. */
LOG10_E :: 0.43429448190325182765112891891660508229439700580366
/** √2. */
SQRT_2 :: 1.41421356237309504880168872420969807856967187537694
/** 1 / √2, √2 / 2. */
SQRT_HALF :: 0.70710678118654752440084436210484903928483593768847

/**
 * Apply an f64 function to an f32 or f64.
 *
 * @tparam F f32 or f64.
 * @param x The argument.
 * @param function The f64 function.
 * @return function(x) for an f64; for an f32, function of x widened, rounded to f32.
 */
in_f64 :: fn[F](x: F, function: (fn(x: f64) -> f64)) -> F {
    #if size_of(F) == 4 {
        return cast[f32](function(cast[f64](x)))
    }
    #else {
        return function(x)
    }
}

/**
 * Apply an f64 function of two arguments to f32s or f64s.
 *
 * @tparam F f32 or f64.
 * @param x The first argument.
 * @param y The second.
 * @param function The f64 function.
 * @return function(x, y) for f64s; for f32s, function of them widened, rounded to f32.
 */
in_f64_2 :: fn[F](x: F, y: F, function: (fn(x: f64, y: f64) -> f64)) -> F {
    #if size_of(F) == 4 {
        return cast[f32](function(cast[f64](x), cast[f64](y)))
    }
    #else {
        return function(x, y)
    }
}

/**
 * e^x.
 *
 * @tparam F f32 or f64.
 * @param x The power.
 * @return e^x, within 1 ulp; infinity where it overflows, 0 where it underflows and for -infinity, NaN for NaN.
 */
exp :: fn[F](x: F) -> F {
    return in_f64(x, exp_64)
}

/**
 * 2^x.
 *
 * @tparam F f32 or f64.
 * @param x The power.
 * @return 2^x, within 1 ulp and exact for whole x; infinity where it overflows, 0 where it underflows and for
 *     -infinity, NaN for NaN.
 */
exp2 :: fn[F](x: F) -> F {
    return in_f64(x, exp2_64)
}

/**
 * e^x - 1, accurate for x near 0, where exp(x) - 1 loses what x is.
 *
 * @tparam F f32 or f64.
 * @param x The power.
 * @return e^x - 1, within 1 ulp; infinity where it overflows, -1 for -infinity and where e^x rounds to 0, NaN for NaN.
 */
exp_minus_one :: fn[F](x: F) -> F {
    return in_f64(x, exp_minus_one_64)
}

/**
 * The natural logarithm, ln x.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return ln x, within 1 ulp; -infinity for ±0, NaN below 0 and for NaN, infinity for infinity.
 */
log :: fn[F](x: F) -> F {
    return in_f64(x, log_64)
}

/**
 * The base-2 logarithm.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return log2 x, within 1 ulp and exact for powers of two; -infinity for ±0, NaN below 0 and for NaN, infinity for
 *     infinity.
 */
log2 :: fn[F](x: F) -> F {
    return in_f64(x, log2_64)
}

/**
 * The base-10 logarithm.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return log10 x, within 1 ulp; -infinity for ±0, NaN below 0 and for NaN, infinity for infinity.
 */
log10 :: fn[F](x: F) -> F {
    return in_f64(x, log10_64)
}

/**
 * ln(1 + x), accurate for x near 0, where log(1 + x) loses what x is.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return ln(1 + x), within 1 ulp; -infinity at -1, NaN below -1 and for NaN, infinity for infinity.
 */
log_one_plus :: fn[F](x: F) -> F {
    return in_f64(x, log_one_plus_64)
}

/**
 * x to the power y.
 *
 * @tparam F f32 or f64.
 * @param x The base.
 * @param y The power.
 * @return x^y, within 1 ulp, as C's pow gives it: 1 for y = ±0 or x = 1, even NaN's; NaN otherwise if either is NaN,
 *     and for a negative x with a y that isn't whole; ±infinity or ±0 where it overflows or underflows, and for x = ±0
 *     or ±infinity, negative only for a negative x to an odd whole power.
 */
power :: fn[F](x: F, y: F) -> F {
    return in_f64_2(x, y, power_64)
}

/**
 * sin x.
 *
 * @tparam F f32 or f64.
 * @param x The angle, in radians, any size: it's reduced by π/2 exactly.
 * @return sin x, within 1 ulp; x for ±0, NaN for infinities and NaN.
 */
sin :: fn[F](x: F) -> F {
    return in_f64(x, sin_64)
}

/**
 * cos x.
 *
 * @tparam F f32 or f64.
 * @param x The angle, in radians, any size: it's reduced by π/2 exactly.
 * @return cos x, within 1 ulp; NaN for infinities and NaN.
 */
cos :: fn[F](x: F) -> F {
    return in_f64(x, cos_64)
}

/**
 * tan x.
 *
 * @tparam F f32 or f64.
 * @param x The angle, in radians, any size: it's reduced by π/2 exactly.
 * @return tan x, within 1 ulp; x for ±0, NaN for infinities and NaN.
 */
tan :: fn[F](x: F) -> F {
    return in_f64(x, tan_64)
}

/**
 * sin x and cos x together, reducing x once.
 *
 * @tparam F f32 or f64.
 * @param x The angle, in radians.
 * @return sin x and cos x, as sin and cos give them.
 */
sin_cos :: fn[F](x: F) -> (F, F) {
    #if size_of(F) == 4 {
        s, c :: sin_cos_64(cast[f64](x))
        return cast[f32](s), cast[f32](c)
    }
    #else {
        return sin_cos_64(x)
    }
}

/**
 * The arcsine.
 *
 * @tparam F f32 or f64.
 * @param x The sine, from -1 to 1.
 * @return The angle from -π/2 to π/2 whose sine is x, within 1 ulp; NaN beyond ±1 and for NaN.
 */
asin :: fn[F](x: F) -> F {
    return in_f64(x, asin_64)
}

/**
 * The arccosine.
 *
 * @tparam F f32 or f64.
 * @param x The cosine, from -1 to 1.
 * @return The angle from 0 to π whose cosine is x, within 1 ulp; NaN beyond ±1 and for NaN.
 */
acos :: fn[F](x: F) -> F {
    return in_f64(x, acos_64)
}

/**
 * The arctangent.
 *
 * @tparam F f32 or f64.
 * @param x The tangent.
 * @return The angle from -π/2 to π/2 whose tangent is x, within 1 ulp; ±π/2 for ±infinity, NaN for NaN.
 */
atan :: fn[F](x: F) -> F {
    return in_f64(x, atan_64)
}

/**
 * The angle of the point (x, y) from the positive x axis, as C's atan2.
 *
 * @tparam F f32 or f64.
 * @param y The point's y.
 * @param x The point's x.
 * @return The angle from -π to π, within 1 ulp: positive above the x axis, ±π on its negative side as y is ±0, ±π/2
 *     on the y axis, and multiples of π/4 for two infinities; NaN if either is NaN.
 */
atan2 :: fn[F](y: F, x: F) -> F {
    return in_f64_2(y, x, atan2_64)
}

/**
 * The hyperbolic sine.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return sinh x, within 1 ulp; ±infinity where it overflows and for ±infinity, NaN for NaN.
 */
sinh :: fn[F](x: F) -> F {
    return in_f64(x, sinh_64)
}

/**
 * The hyperbolic cosine.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return cosh x, within 1 ulp; infinity where it overflows and for ±infinity, NaN for NaN.
 */
cosh :: fn[F](x: F) -> F {
    return in_f64(x, cosh_64)
}

/**
 * The hyperbolic tangent.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return tanh x, within 1 ulp, from -1 to 1; ±1 for ±infinity, NaN for NaN.
 */
tanh :: fn[F](x: F) -> F {
    return in_f64(x, tanh_64)
}

/**
 * The inverse hyperbolic sine.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return asinh x, within 1 ulp; ±infinity for ±infinity, NaN for NaN.
 */
asinh :: fn[F](x: F) -> F {
    return in_f64(x, asinh_64)
}

/**
 * The inverse hyperbolic cosine.
 *
 * @tparam F f32 or f64.
 * @param x The number, at least 1.
 * @return acosh x, at least 0, within 1 ulp; infinity for infinity, NaN below 1 and for NaN.
 */
acosh :: fn[F](x: F) -> F {
    return in_f64(x, acosh_64)
}

/**
 * The inverse hyperbolic tangent.
 *
 * @tparam F f32 or f64.
 * @param x The number, from -1 to 1.
 * @return atanh x, within 1.5 ulp; ±infinity at ±1, NaN beyond them and for NaN.
 */
atanh :: fn[F](x: F) -> F {
    return in_f64(x, atanh_64)
}

/**
 * The real cube root.
 *
 * @tparam F f32 or f64.
 * @param x The number, any sign.
 * @return ∛x, of x's sign, within 1 ulp; x for ±0, ±infinity and NaN.
 */
cube_root :: fn[F](x: F) -> F {
    return in_f64(x, cube_root_64)
}

/**
 * √(x² + y²), without overflowing or underflowing where the result doesn't.
 *
 * @tparam F f32 or f64.
 * @param x One side.
 * @param y The other.
 * @return The hypotenuse, within 1 ulp; infinity if either is infinite, even if the other is NaN; NaN otherwise if
 *     either is NaN.
 */
hypotenuse :: fn[F](x: F, y: F) -> F {
    return in_f64_2(x, y, hypotenuse_64)
}

/**
 * x - n × y, n the quotient x / y truncated toward 0: C's fmod, and what % would be on floats. Exact.
 *
 * @tparam F f32 or f64.
 * @param x The dividend.
 * @param y The divisor.
 * @return The remainder, of x's sign and smaller than |y|; x for a finite x and infinite y; NaN if y is 0, x is
 *     infinite, or either is NaN.
 */
truncated_remainder :: fn[F](x: F, y: F) -> F {
    return in_f64_2(x, y, truncated_remainder_64)
}

/**
 * x - n × y, n the quotient x / y rounded to nearest, halfway to even: IEEE 754's remainder. Exact.
 *
 * @tparam F f32 or f64.
 * @param x The dividend.
 * @param y The divisor.
 * @return The remainder, at most |y| / 2 in magnitude, a zero of x's sign when it's 0; x for a finite x and infinite y;
 *     NaN if y is 0, x is infinite, or either is NaN.
 */
remainder :: fn[F](x: F, y: F) -> F {
    return in_f64_2(x, y, remainder_64)
}

/**
 * The error function, 2/√π ∫₀ˣ e^(-t²) dt.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return erf x, from -1 to 1, within 1 ulp; ±1 for ±infinity, NaN for NaN.
 */
erf :: fn[F](x: F) -> F {
    return in_f64(x, erf_64)
}

/**
 * The complementary error function, 1 - erf x, accurate where erf x is near 1.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return erfc x, from 0 to 2, within 1 ulp, and 2 far in its tail, from about 6; 0 for infinity, 2 for -infinity,
 *     NaN for NaN.
 */
erfc :: fn[F](x: F) -> F {
    return in_f64(x, erfc_64)
}

/**
 * The inverse error function: the x whose erf is y.
 *
 * @tparam F f32 or f64.
 * @param y The value of erf, from -1 to 1.
 * @return x with erf x = y, within 2 ulp; ±infinity at ±1, NaN beyond and for NaN.
 */
erf_inverse :: fn[F](y: F) -> F {
    return in_f64(y, erf_inverse_64)
}

/**
 * The gamma function, Γ(x), which is (x - 1)! for whole x.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return Γ(x), within 6 ulp, exact for whole numbers up to 23; ±infinity at ±0 and where it overflows, NaN at the
 *     negative whole numbers and -infinity, ±0 where it underflows, NaN for NaN.
 */
gamma :: fn[F](x: F) -> F {
    return in_f64(x, gamma_64)
}

/**
 * ln |Γ(x)|, which doesn't overflow where Γ does.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return ln |Γ(x)|, within 1 ulp where it's at least 1 in magnitude, and within ulp(1) of it where it's below, near
 *     its zeros at 1 and 2 and between the negative whole numbers; infinity at 0, the negative whole numbers and
 *     ±infinity; NaN for NaN.
 */
log_gamma :: fn[F](x: F) -> F {
    return in_f64(x, log_gamma_64)
}

/**
 * ln |Γ(x)| and the sign of Γ(x).
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return ln |Γ(x)|, as log_gamma gives it, and 1 or -1, Γ(x)'s sign: -1 from -2k - 1 to -2k for whole k ≥ 0, and for
 *     -0.
 */
log_gamma_signed :: fn[F](x: F) -> (F, i32) {
    #if size_of(F) == 4 {
        r, sign :: log_gamma_signed_64(cast[f64](x))
        return cast[f32](r), sign
    }
    #else {
        return log_gamma_signed_64(x)
    }
}

/**
 * Whether a float is NaN.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return True for any NaN, quiet or signalling, of either sign.
 */
is_nan :: fn[F](x: F) -> bool {
    return x != x
}

/**
 * Whether a float is infinite.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return True for ±infinity; false for NaN and every finite number.
 */
is_infinite :: fn[F](x: F) -> bool {
    return x == x && x - x != x - x
}

/**
 * Whether a float is finite.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return True unless it's infinite or NaN.
 */
is_finite :: fn[F](x: F) -> bool {
    return x - x == x - x
}

/**
 * Whether a float is normal: finite, not zero, and not subnormal, so it has all its precision.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return True for a normal number.
 */
is_normal :: fn[F](x: F) -> bool {
    return is_finite(x) && abs(x) >= least_normal[F]()
}

/**
 * Whether a float is subnormal: not zero, but below the least normal number, with less precision.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return True for a subnormal number.
 */
is_subnormal :: fn[F](x: F) -> bool {
    return x != 0 && abs(x) < least_normal[F]()
}

/**
 * Whether a float's sign bit is set, which tells -0 from +0 and a NaN's sign, where x < 0 doesn't.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return True for negative numbers, -0, -infinity and NaNs with the bit set.
 */
sign_bit :: fn[F](x: F) -> bool {
    #if size_of(F) == 4 {
        return (bit_cast[u32](x) >> 31) != 0
    }
    #else {
        return (bit_cast[u64](x) >> 63) != 0
    }
}

/**
 * Give positive infinity.
 *
 * @tparam F f32 or f64.
 * @return Infinity, of type F.
 */
infinity :: fn[F]() -> F {
    #if size_of(F) == 4 {
        return bit_cast[f32](cast[u32](0x7f80_0000))
    }
    #else {
        return infinity_64()
    }
}

/**
 * Give a quiet NaN.
 *
 * @tparam F f32 or f64.
 * @return A NaN, positive, of type F.
 */
nan :: fn[F]() -> F {
    #if size_of(F) == 4 {
        return bit_cast[f32](cast[u32](0x7fc0_0000))
    }
    #else {
        return nan_64()
    }
}

/**
 * Give the largest finite float.
 *
 * @tparam F f32 or f64.
 * @return (2 - 2^-23) × 2^127 for f32, (2 - 2^-52) × 2^1023 for f64.
 */
largest :: fn[F]() -> F {
    #if size_of(F) == 4 {
        return bit_cast[f32](cast[u32](0x7f7f_ffff))
    }
    #else {
        return bit_cast[f64](cast[u64](0x7fef_ffff_ffff_ffff))
    }
}

/**
 * Give the least positive normal float.
 *
 * @tparam F f32 or f64.
 * @return 2^-126 for f32, 2^-1022 for f64.
 */
least_normal :: fn[F]() -> F {
    #if size_of(F) == 4 {
        return bit_cast[f32](cast[u32](0x0080_0000))
    }
    #else {
        return bit_cast[f64](cast[u64](0x0010_0000_0000_0000))
    }
}

/**
 * Give the gap between 1 and the next float above it, machine epsilon.
 *
 * @tparam F f32 or f64.
 * @return 2^-23 for f32, 2^-52 for f64.
 */
epsilon :: fn[F]() -> F {
    #if size_of(F) == 4 {
        return bit_cast[f32](cast[u32](0x3400_0000))
    }
    #else {
        return bit_cast[f64](cast[u64](0x3cb0_0000_0000_0000))
    }
}

/**
 * Give the least float above x.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return The next float toward +infinity: the least subnormal for ±0, -largest for -infinity; infinity for infinity
 *     and the largest float, x for NaN.
 */
next_up :: fn[F](x: F) -> F {
    if x != x || x == infinity[F]() {
        return x
    }
    #if size_of(F) == 4 {
        if x == 0 {
            return bit_cast[f32](cast[u32](1))
        }
        bits :: bit_cast[u32](x)
        return bit_cast[f32](if (bits >> 31) == 0 { bits + 1 } else { bits - 1 })
    }
    #else {
        if x == 0 {
            return bit_cast[f64](cast[u64](1))
        }
        bits :: bit_cast[u64](x)
        return bit_cast[f64](if (bits >> 63) == 0 { bits + 1 } else { bits - 1 })
    }
}

/**
 * Give the greatest float below x.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return The next float toward -infinity: minus the least subnormal for ±0, largest for infinity; -infinity for
 *     -infinity and -largest, x for NaN.
 */
next_down :: fn[F](x: F) -> F {
    return -next_up(-x)
}

/**
 * Give the unit in the last place of x: the gap between |x| and the next float away from 0, or below it for the
 * largest.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return The gap, a power of two: the least subnormal for 0 and subnormals; infinity for ±infinity, NaN for NaN.
 */
ulp :: fn[F](x: F) -> F {
    magnitude :: abs(x)
    if x != x || magnitude == infinity[F]() {
        return magnitude
    }
    if magnitude == largest[F]() {
        return magnitude - next_down(magnitude)
    }
    return next_up(magnitude) - magnitude
}

/**
 * Split a float into a fraction from 1/2 to 1 and a power of two: C's frexp.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @return f and e with x = f × 2^e, |f| from 1/2 to below 1, of x's sign; for ±0, ±infinity and NaN, x itself and 0.
 */
fraction_and_exponent :: fn[F](x: F) -> (F, i32) {
    wide :: cast[f64](x)
    if wide == 0 || wide != wide || abs(wide) == infinity_64() {
        return x, 0
    }
    scaled := wide
    shift : i32 = 0
    if abs(wide) < least_normal[f64]() {
        scaled *= TWO_TO_54
        shift = -54
    }
    bits :: bit_cast[u64](scaled)
    exponent :: cast[i32]((bits >> 52) & 0x7ff) - 1022
    fraction :: bit_cast[f64]((bits & 0x800f_ffff_ffff_ffff) | 0x3fe0_0000_0000_0000)
    return cast[F](fraction), exponent + shift
}

/**
 * Multiply a float by a power of two, rounding once: C's ldexp and scalbn.
 *
 * @tparam F f32 or f64.
 * @param x The number.
 * @param power The power of two, any i32.
 * @return x × 2^power, rounded once; ±infinity where it overflows, ±0 where it underflows; x for ±0, ±infinity and
 *     NaN.
 */
scale_by_power_of_two :: fn[F](x: F, power: i32) -> F {
    #if size_of(F) == 4 {
        // Exact in f64 for any power an f32 result needs, so it's rounded once, to f32
        clamped : i32 = if power > 400 { 400 } else if power < -400 { -400 } else { power }
        return cast[f32](runtime.scale_by_power_of_two(cast[f64](x), clamped))
    }
    #else {
        return runtime.scale_by_power_of_two(x, power)
    }
}

/**
 * Read a float from decimal text, correctly rounded: the float nearest the number the text says, ties to even, as
 * IEEE 754 rounds.
 *
 * @tparam F f32 or f64, given explicitly: parse[f64]("2.5").
 * @param text The text: an optional sign, digits with an optional point, at least one digit, and an optional exponent,
 *     e or E and an optionally signed whole number, like "-12.5e3", ".5" or "7."; or inf, infinity or nan, in any case,
 *     with an optional sign. Any number of digits is read exactly. Nothing else, and nothing before or after it.
 * @return The float: ±infinity past the largest, a zero of the text's sign below half the least subnormal; none if the
 *     text isn't such a number.
 */
parse :: fn[F](text: string) -> F? {
    #if size_of(F) == 4 {
        return parse_32(text)
    }
    #else {
        return parse_64(text)
    }
}
