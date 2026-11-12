package fast

import math from "std"

/*
 * The public functions, each on an f32 or an f64 or a vector of either: F is the type, worked out from the argument.
 * Where a function has a kernel of its own here, a scalar runs it on one lane; otherwise it's std/math's.
 */

/**
 * e^x, fast.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The power.
 * @return e^x, within 3.5 ulp; infinity past ln of the largest float, 0 below ln of the least subnormal and for
 *     -infinity, NaN for NaN.
 */
exp :: fn[F](x: F) -> F {
    #if math.float_kind(F) == math.FLOAT_LANES_32 {
        return exp_lanes_32(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_32 {
        return exp_lanes_32(vector[f32, 1].{x})[0]
    }
    #else_if math.float_kind(F) == math.FLOAT_LANES_64 {
        return exp_lanes_64(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_64 {
        return exp_lanes_64(vector[f64, 1].{x})[0]
    }
    #else {
        return math.exp(x)
    }
}

/**
 * 2^x, fast.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The power.
 * @return 2^x, within 3.5 ulp; infinity from the largest exponent up, 0 below the least subnormal's and for -infinity,
 *     NaN for NaN.
 */
exp2 :: fn[F](x: F) -> F {
    #if math.float_kind(F) == math.FLOAT_LANES_32 {
        return exp2_lanes_32(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_32 {
        return exp2_lanes_32(vector[f32, 1].{x})[0]
    }
    #else_if math.float_kind(F) == math.FLOAT_LANES_64 {
        return exp2_lanes_64(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_64 {
        return exp2_lanes_64(vector[f64, 1].{x})[0]
    }
    #else {
        return math.exp2(x)
    }
}

/**
 * e^x - 1: std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The power.
 * @return e^x - 1 as math.exp_minus_one gives it, within 1 ulp.
 */
exp_minus_one :: fn[F](x: F) -> F {
    return math.exp_minus_one(x)
}

/**
 * ln x, fast.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number.
 * @return ln x, within 3.5 ulp; -infinity for ±0, NaN below 0 and for NaN, infinity for infinity.
 */
log :: fn[F](x: F) -> F {
    #if math.float_kind(F) == math.FLOAT_LANES_32 {
        return log_lanes_32(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_32 {
        return log_lanes_32(vector[f32, 1].{x})[0]
    }
    #else_if math.float_kind(F) == math.FLOAT_LANES_64 {
        return log_lanes_64(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_64 {
        return log_lanes_64(vector[f64, 1].{x})[0]
    }
    #else {
        return math.log(x)
    }
}

/**
 * log2 x, fast.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number.
 * @return log2 x, within 3.5 ulp; -infinity for ±0, NaN below 0 and for NaN, infinity for infinity.
 */
log2 :: fn[F](x: F) -> F {
    #if math.float_kind(F) == math.FLOAT_LANES_32 {
        return log2_lanes_32(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_32 {
        return log2_lanes_32(vector[f32, 1].{x})[0]
    }
    #else_if math.float_kind(F) == math.FLOAT_LANES_64 {
        return log2_lanes_64(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_64 {
        return log2_lanes_64(vector[f64, 1].{x})[0]
    }
    #else {
        return math.log2(x)
    }
}

/**
 * log10 x: std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number.
 * @return log10 x as math.log10 gives it, within 1 ulp.
 */
log10 :: fn[F](x: F) -> F {
    return math.log10(x)
}

/**
 * ln(1 + x): std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number.
 * @return ln(1 + x) as math.log_one_plus gives it, within 1 ulp.
 */
log_one_plus :: fn[F](x: F) -> F {
    return math.log_one_plus(x)
}

/**
 * sin x, fast.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The angle, in radians.
 * @return sin x, within 3.5 ulp; -0 for -0, NaN for infinities and NaN.
 */
sin :: fn[F](x: F) -> F {
    #if math.float_kind(F) == math.FLOAT_LANES_32 {
        return sin_lanes_32(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_32 {
        return sin_lanes_32(vector[f32, 1].{x})[0]
    }
    #else_if math.float_kind(F) == math.FLOAT_LANES_64 {
        return sin_lanes_64(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_64 {
        return sin_lanes_64(vector[f64, 1].{x})[0]
    }
    #else {
        return math.sin(x)
    }
}

/**
 * cos x, fast.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The angle, in radians.
 * @return cos x, within 3.5 ulp; NaN for infinities and NaN.
 */
cos :: fn[F](x: F) -> F {
    #if math.float_kind(F) == math.FLOAT_LANES_32 {
        return cos_lanes_32(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_32 {
        return cos_lanes_32(vector[f32, 1].{x})[0]
    }
    #else_if math.float_kind(F) == math.FLOAT_LANES_64 {
        return cos_lanes_64(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_64 {
        return cos_lanes_64(vector[f64, 1].{x})[0]
    }
    #else {
        return math.cos(x)
    }
}

/**
 * tan x, fast for f32, std/math's for f64.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The angle, in radians.
 * @return tan x, within 3.5 ulp for f32 and 1 ulp for f64; -0 for -0, NaN for infinities and NaN.
 */
tan :: fn[F](x: F) -> F {
    #if math.float_kind(F) == math.FLOAT_LANES_32 {
        return tan_lanes_32(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_32 {
        return tan_lanes_32(vector[f32, 1].{x})[0]
    }
    #else {
        return math.tan(x)
    }
}

/**
 * asin x, fast.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The sine, from -1 to 1.
 * @return The angle from -π/2 to π/2 whose sine x is, within 3.5 ulp; NaN beyond ±1 and for NaN.
 */
asin :: fn[F](x: F) -> F {
    #if math.float_kind(F) == math.FLOAT_LANES_32 {
        return asin_lanes_32(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_32 {
        return asin_lanes_32(vector[f32, 1].{x})[0]
    }
    #else_if math.float_kind(F) == math.FLOAT_LANES_64 {
        return asin_lanes_64(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_64 {
        return asin_lanes_64(vector[f64, 1].{x})[0]
    }
    #else {
        return math.asin(x)
    }
}

/**
 * acos x, fast.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The cosine, from -1 to 1.
 * @return The angle from 0 to π whose cosine x is, within 3.5 ulp; NaN beyond ±1 and for NaN.
 */
acos :: fn[F](x: F) -> F {
    #if math.float_kind(F) == math.FLOAT_LANES_32 {
        return acos_lanes_32(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_32 {
        return acos_lanes_32(vector[f32, 1].{x})[0]
    }
    #else_if math.float_kind(F) == math.FLOAT_LANES_64 {
        return acos_lanes_64(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_64 {
        return acos_lanes_64(vector[f64, 1].{x})[0]
    }
    #else {
        return math.acos(x)
    }
}

/**
 * atan x, fast.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The tangent.
 * @return The angle from -π/2 to π/2 whose tangent x is, within 3.5 ulp; ±π/2 for ±infinity, NaN for NaN.
 */
atan :: fn[F](x: F) -> F {
    #if math.float_kind(F) == math.FLOAT_LANES_32 {
        return atan_lanes_32(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_32 {
        return atan_lanes_32(vector[f32, 1].{x})[0]
    }
    #else_if math.float_kind(F) == math.FLOAT_LANES_64 {
        return atan_lanes_64(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_64 {
        return atan_lanes_64(vector[f64, 1].{x})[0]
    }
    #else {
        return math.atan(x)
    }
}

/**
 * sinh x: std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number.
 * @return sinh x as math.sinh gives it, within 1 ulp.
 */
sinh :: fn[F](x: F) -> F {
    return math.sinh(x)
}

/**
 * cosh x: std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number.
 * @return cosh x as math.cosh gives it, within 1 ulp.
 */
cosh :: fn[F](x: F) -> F {
    return math.cosh(x)
}

/**
 * tanh x: std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number.
 * @return tanh x as math.tanh gives it, within 1 ulp.
 */
tanh :: fn[F](x: F) -> F {
    return math.tanh(x)
}

/**
 * asinh x: std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number.
 * @return asinh x as math.asinh gives it, within 1 ulp.
 */
asinh :: fn[F](x: F) -> F {
    return math.asinh(x)
}

/**
 * acosh x: std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number, from 1 up.
 * @return acosh x as math.acosh gives it, within 1 ulp.
 */
acosh :: fn[F](x: F) -> F {
    return math.acosh(x)
}

/**
 * atanh x: std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number, from -1 to 1.
 * @return atanh x as math.atanh gives it, within 1.5 ulp.
 */
atanh :: fn[F](x: F) -> F {
    return math.atanh(x)
}

/**
 * ∛x, fast for f32, std/math's for f64.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number, any sign.
 * @return The real cube root, of x's sign, within 3.5 ulp for f32 and 1 ulp for f64; x for ±0, ±infinity and NaN.
 */
cube_root :: fn[F](x: F) -> F {
    #if math.float_kind(F) == math.FLOAT_LANES_32 {
        return cube_root_lanes_32(x)
    }
    #else_if math.float_kind(F) == math.FLOAT_32 {
        return cube_root_lanes_32(vector[f32, 1].{x})[0]
    }
    #else {
        return math.cube_root(x)
    }
}

/**
 * erf x: std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number.
 * @return erf x as math.erf gives it, within 1 ulp.
 */
erf :: fn[F](x: F) -> F {
    return math.erf(x)
}

/**
 * erfc x: std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number.
 * @return 1 - erf x as math.erfc gives it, within 2 ulp.
 */
erfc :: fn[F](x: F) -> F {
    return math.erfc(x)
}

/**
 * erf⁻¹ y: std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param y The value of erf, from -1 to 1.
 * @return The x whose erf y is, as math.erf_inverse gives it, within 2 ulp.
 */
erf_inverse :: fn[F](y: F) -> F {
    return math.erf_inverse(y)
}

/**
 * Γ(x): std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number.
 * @return Γ(x) as math.gamma gives it, within 6 ulp.
 */
gamma :: fn[F](x: F) -> F {
    return math.gamma(x)
}

/**
 * ln |Γ(x)|: std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The number.
 * @return ln |Γ(x)| as math.log_gamma gives it, within 1 ulp.
 */
log_gamma :: fn[F](x: F) -> F {
    return math.log_gamma(x)
}

/**
 * x^y: std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The base.
 * @param y The power.
 * @return x^y as math.power gives it, within 1 ulp and as C's pow says at its special cases.
 */
power :: fn[F](x: F, y: F) -> F {
    #if math.float_kind(F) == math.FLOAT_LANES_32 {
        return power_lanes_32(x, y)
    }
    #else_if math.float_kind(F) == math.FLOAT_32 {
        return power_lanes_32(vector[f32, 1].{x}, vector[f32, 1].{y})[0]
    }
    #else_if math.float_kind(F) == math.FLOAT_LANES_64 {
        return power_lanes_64(x, y)
    }
    #else_if math.float_kind(F) == math.FLOAT_64 {
        return power_lanes_64(vector[f64, 1].{x}, vector[f64, 1].{y})[0]
    }
    #else {
        return math.power(x, y)
    }
}

/**
 * The angle of the point (x, y), fast.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param y The point's y.
 * @param x The point's x.
 * @return The angle from -π to π from the positive x axis to (x, y), within 3.5 ulp; at zeros and infinities as C's
 *     atan2 says, NaN if either is NaN.
 */
atan2 :: fn[F](y: F, x: F) -> F {
    #if math.float_kind(F) == math.FLOAT_LANES_32 {
        return atan2_lanes_32(y, x)
    }
    #else_if math.float_kind(F) == math.FLOAT_32 {
        return atan2_lanes_32(vector[f32, 1].{y}, vector[f32, 1].{x})[0]
    }
    #else_if math.float_kind(F) == math.FLOAT_LANES_64 {
        return atan2_lanes_64(y, x)
    }
    #else_if math.float_kind(F) == math.FLOAT_64 {
        return atan2_lanes_64(vector[f64, 1].{y}, vector[f64, 1].{x})[0]
    }
    #else {
        return math.atan2(y, x)
    }
}

/**
 * √(x² + y²): std/math's.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x One side.
 * @param y The other.
 * @return The hypotenuse as math.hypotenuse gives it, within 1 ulp, without overflowing or underflowing where the
 *     result doesn't.
 */
hypotenuse :: fn[F](x: F, y: F) -> F {
    return math.hypotenuse(x, y)
}

/**
 * sin x and cos x together, fast.
 *
 * @tparam F f32 or f64, or a vector of either.
 * @param x The angle, in radians.
 * @return sin x and cos x, each as sin and cos give it.
 */
sin_cos :: fn[F](x: F) -> (F, F) {
    return sin(x), cos(x)
}
