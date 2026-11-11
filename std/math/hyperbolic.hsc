package math

import intrinsics from "base"

/*
 * The hyperbolic functions and their inverses in f64, as musl has them: from exp, exp_minus_one and log_one_plus, so
 * no constants of their own but ln 2.
 */

/** 2043 ln 2, which e^x is taken by before scaling, so e^x / 2 doesn't overflow before it has to. */
EXPO2_SHIFT : f64 : 1416.0996898839683 // 0x40962066_151add8b

/**
 * e^x / 2 × sign, for x near where e^x overflows, without overflowing sooner: e^(x - 2043 ln 2) × 2^1021 × 2^1021.
 *
 * @param x The power, from ln of the largest f64 to about twice that.
 * @param sign 1 or -1.
 * @return sign × e^x / 2, within 1 ulp.
 */
//SPEC: musl src/math/__expo2.c
half_exp_large_64 :: fn(x: f64, sign: f64) -> f64 {
    scale :: power_of_two_64(1021)
    return exp_64(x - EXPO2_SHIFT) * (sign * scale) * scale
}

/**
 * sinh x in f64.
 *
 * @param x The number.
 * @return sinh x, within 1 ulp; x for ±0 and ±infinity, NaN for NaN.
 */
//SPEC: musl src/math/sinh.c
sinh_64 :: fn(x: f64) -> f64 {
    h :: if (bit_cast[u64](x) >> 63) != 0 { -0.5 } else { 0.5 }
    magnitude :: abs(x)
    w :: high_word(magnitude)
    // Below ln of the largest f64
    if w < 0x4086_2e42 {
        t :: exp_minus_one_64(magnitude)
        if w < 0x3ff0_0000 {
            if w < 0x3ff0_0000 - (26 << 20) {
                return x
            }
            return h * (2 * t - t * t / (t + 1))
        }
        return h * (t + t / (t + 1))
    }
    if x != x {
        return x
    }
    return half_exp_large_64(magnitude, 2 * h)
}

/**
 * cosh x in f64.
 *
 * @param x The number.
 * @return cosh x, within 1 ulp; infinity for ±infinity, NaN for NaN.
 */
//SPEC: musl src/math/cosh.c
cosh_64 :: fn(x: f64) -> f64 {
    magnitude :: abs(x)
    w :: high_word(magnitude)
    // Below ln 2
    if w < 0x3fe6_2e42 {
        if w < 0x3ff0_0000 - (26 << 20) {
            return 1
        }
        t :: exp_minus_one_64(magnitude)
        return 1 + t * t / (2 * (1 + t))
    }
    // Below ln of the largest f64
    if w < 0x4086_2e42 {
        t :: exp_64(magnitude)
        return 0.5 * (t + 1 / t)
    }
    if x != x {
        return x
    }
    return half_exp_large_64(magnitude, 1.0)
}

/**
 * tanh x in f64.
 *
 * @param x The number.
 * @return tanh x, within 1 ulp; ±1 for ±infinity and past 20, x for ±0, NaN for NaN.
 */
//SPEC: musl src/math/tanh.c
tanh_64 :: fn(x: f64) -> f64 {
    negative :: (bit_cast[u64](x) >> 63) != 0
    magnitude :: abs(x)
    w :: high_word(magnitude)
    t := 0.0
    if x != x {
        return x
    }
    if w > 0x3fe1_93ea {
        // Past ln(3) / 2
        if w > 0x4034_0000 {
            // Past 20, tanh rounds to 1
            t = 1.0
        }
        else {
            t = exp_minus_one_64(2 * magnitude)
            t = 1 - 2 / (t + 2)
        }
    }
    else if w > 0x3fd0_58ae {
        // Past ln(5/3) / 2
        t = exp_minus_one_64(2 * magnitude)
        t = t / (t + 2)
    }
    else if w >= 0x0010_0000 {
        t = exp_minus_one_64(-2 * magnitude)
        t = -t / (t + 2)
    }
    else {
        // Subnormal
        t = magnitude
    }
    return if negative { -t } else { t }
}

/**
 * asinh x in f64.
 *
 * @param x The number.
 * @return asinh x, within 1 ulp; x for ±0 and ±infinity, NaN for NaN.
 */
//SPEC: musl src/math/asinh.c
asinh_64 :: fn(x: f64) -> f64 {
    negative :: (bit_cast[u64](x) >> 63) != 0
    e :: cast[i32]((bit_cast[u64](x) >> 52) & 0x7ff)
    y := abs(x)
    if e >= 0x3ff + 26 {
        // Past 2^26, or infinite or NaN
        y = log_64(y) + LN2
    }
    else if e >= 0x3ff + 1 {
        // From 2
        y = log_64(2 * y + 1 / (intrinsics.square_root(y * y + 1) + y))
    }
    else if e >= 0x3ff - 26 {
        // From 2^-26
        y = log_one_plus_64(y + y * y / (intrinsics.square_root(y * y + 1) + 1))
    }
    return if negative { -y } else { y }
}

/**
 * acosh x in f64.
 *
 * @param x The number, at least 1.
 * @return acosh x, within 1 ulp; infinity for infinity, NaN below 1 and for NaN.
 */
//SPEC: musl src/math/acosh.c
acosh_64 :: fn(x: f64) -> f64 {
    e :: cast[i32]((bit_cast[u64](x) >> 52) & 0x7ff)
    if x < 1 {
        return nan_64()
    }
    if e < 0x3ff + 1 {
        // Below 2
        return log_one_plus_64(x - 1 + intrinsics.square_root((x - 1) * (x - 1) + 2 * (x - 1)))
    }
    if e < 0x3ff + 26 {
        // Below 2^26
        return log_64(2 * x - 1 / (x + intrinsics.square_root(x * x - 1)))
    }
    return log_64(x) + LN2
}

/**
 * atanh x in f64.
 *
 * @param x The number, from -1 to 1.
 * @return atanh x, within 1.5 ulp; ±infinity at ±1, NaN beyond and for NaN.
 */
//SPEC: musl src/math/atanh.c
atanh_64 :: fn(x: f64) -> f64 {
    negative :: (bit_cast[u64](x) >> 63) != 0
    e :: cast[i32]((bit_cast[u64](x) >> 52) & 0x7ff)
    y := abs(x)
    if e < 0x3ff - 1 {
        // Below a half; under 2^-32, atanh x rounds to x
        if e >= 0x3ff - 32 {
            y = 0.5 * log_one_plus_64(2 * y + 2 * y * y / (1 - y))
        }
    }
    else {
        y = 0.5 * log_one_plus_64(2 * (y / (1 - y)))
    }
    return if negative { -y } else { y }
}
