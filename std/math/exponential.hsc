package math

import intrinsics from "base"

/*
 * e^x, 2^x and e^x - 1, in f64 (fdlibm's e_exp.c and s_expm1.c). The constants' hex is their bits, high word then low,
 * as fdlibm gives them.
 */

/** ln 2's top bits, so k × LN2_HI is exact for the k exp reduces by. */
LN2_HI : f64 : 6.93147180369123816490e-01 // 0x3fe62e42_fee00000
/** ln 2 - LN2_HI. */
LN2_LO : f64 : 1.90821492927058770002e-10 // 0x3dea39ef_35793c76
/** 1 / ln 2. */
INVERSE_LN2 : f64 : 1.44269504088896338700 // 0x3ff71547_652b82fe
/** Past this, e^x overflows: ln of the largest f64. */
EXP_OVERFLOW : f64 : 7.09782712893383973096e02 // 0x40862e42_fefa39ef
/** Below this, e^x underflows to 0. */
EXP_UNDERFLOW : f64 : -7.45133219101941108420e02 // 0xc0874910_d52d3051
/** 2^-1000, to scale results that would be subnormal. */
TWO_TO_MINUS_1000 : f64 : 9.33263618503218878990e-302 // 0x01700000_00000000

/* The polynomial for e^r's remainder on [-ln 2 / 2, ln 2 / 2] */
EXP_P1 : f64 : 1.66666666666666019037e-01 // 0x3fc55555_5555553e
EXP_P2 : f64 : -2.77777777770155933842e-03 // 0xbf66c16c_16bebd93
EXP_P3 : f64 : 6.61375632143793436117e-05 // 0x3f11566a_af25de2c
EXP_P4 : f64 : -1.65339022054652515390e-06 // 0xbebbbd41_c5d26bf1
EXP_P5 : f64 : 4.13813679705723846039e-08 // 0x3e663769_72bea4d0

/* expm1's polynomial, in x²/2 */
EXPM1_Q1 : f64 : -3.33333333333331316428e-02 // 0xbfa11111_111110f4
EXPM1_Q2 : f64 : 1.58730158725481460165e-03 // 0x3f5a01a0_19fe5585
EXPM1_Q3 : f64 : -7.93650757867487942473e-05 // 0xbf14ce19_9eaadbb7
EXPM1_Q4 : f64 : 4.00821782732936239552e-06 // 0x3ed0cfca_86e65239
EXPM1_Q5 : f64 : -2.01099218183624371326e-07 // 0xbe8afdb7_6e09c32d

/**
 * Give 2^k as an f64, for k from -1022 to 1023.
 *
 * @param k The power, in that range.
 * @return 2^k, exactly.
 */
power_of_two_64 :: fn(k: i32) -> f64 {
    return from_words(cast[i32](cast[u32](0x3ff + k) << 20), 0)
}

/**
 * e^(hi - lo) × 2^k, for hi - lo within ln 2 / 2 of 0: exp's polynomial and reconstruction, which exp and exp2 share.
 *
 * @param hi The reduced argument's top part.
 * @param lo What's to be taken from hi, its error.
 * @param k The power of two to scale by, from -1074 to 1024.
 * @return The result, within 1 ulp.
 */
//SPEC: fdlibm e_exp.c
exp_reduced_64 :: fn(hi: f64, lo: f64, k: i32) -> f64 {
    x :: hi - lo
    t :: x * x
    c :: x - t * (EXP_P1 + t * (EXP_P2 + t * (EXP_P3 + t * (EXP_P4 + t * EXP_P5))))
    if k == 0 {
        return 1 - ((x * c) / (c - 2.0) - x)
    }
    y :: 1 - ((lo - (x * c) / (2.0 - c)) - hi)
    if k >= -1021 {
        if k == 1024 {
            return y * 2.0 * power_of_two_64(1023)
        }
        return y * power_of_two_64(k)
    }
    return y * power_of_two_64(k + 1000) * TWO_TO_MINUS_1000
}

/**
 * e^x in f64.
 *
 * @param x The power.
 * @return e^x, within 1 ulp; infinity past EXP_OVERFLOW, 0 below EXP_UNDERFLOW, 0 for -infinity, NaN for NaN.
 */
//SPEC: fdlibm e_exp.c
exp_64 :: fn(x: f64) -> f64 {
    hx := cast[u32](high_word(x))
    sign :: cast[i32](hx >> 31)
    hx &= 0x7fff_ffff
    // Too big or small, or not finite
    if hx >= 0x4086_2e42 {
        if hx >= 0x7ff0_0000 {
            if ((hx & 0xf_ffff) | low_word(x)) != 0 {
                return x + x
            }
            return if sign == 0 { x } else { 0.0 }
        }
        if x > EXP_OVERFLOW {
            return infinity_64()
        }
        if x < EXP_UNDERFLOW {
            return 0
        }
    }
    // x = k ln 2 + hi - lo, |hi - lo| at most ln 2 / 2
    if hx > 0x3fd6_2e42 {
        if hx < 0x3ff0_a2b2 {
            if sign == 0 {
                return exp_reduced_64(x - LN2_HI, LN2_LO, 1)
            }
            return exp_reduced_64(x + LN2_HI, -LN2_LO, -1)
        }
        k :: cast[i32](INVERSE_LN2 * x + (if sign == 0 { 0.5 } else { -0.5 }))
        t :: cast[f64](k)
        return exp_reduced_64(x - t * LN2_HI, t * LN2_LO, k)
    }
    // Under 2^-28: 1 + x is e^x rounded
    if hx < 0x3e30_0000 {
        return 1 + x
    }
    return exp_reduced_64(x, 0, 0)
}

/**
 * 2^x in f64: x = k + f, f within a half of 0, and 2^f = e^(f ln 2), with f ln 2 in two parts so exp's reduction loses
 * nothing.
 *
 * @param x The power.
 * @return 2^x, within 1 ulp; infinity from 1024, 0 at -1075 and below, NaN for NaN.
 */
exp2_64 :: fn(x: f64) -> f64 {
    if x != x {
        return x + x
    }
    if x >= 1024 {
        return infinity_64()
    }
    if x < -1075 {
        return 0
    }
    whole :: intrinsics.round_even(x)
    fraction :: x - whole
    // f × ln 2 = hi - lo exactly enough: hi rounded, what rounding lost and ln 2's tail in lo
    hi :: fraction * LN2
    lo :: -(intrinsics.fused_multiply_add(fraction, LN2, -hi) + fraction * LN2_TAIL)
    return exp_reduced_64(hi, lo, cast[i32](whole))
}

/** ln 2 rounded to f64. */
LN2 : f64 : 6.93147180559945286227e-01 // 0x3fe62e42_fefa39ef
/** ln 2 - LN2. */
LN2_TAIL : f64 : 2.319046813846299558e-17 // 0x3c7abc9e_3b39803f

/**
 * e^x - 1 in f64, accurate where x is near 0, where exp(x) - 1 would lose it.
 *
 * @param x_in The power.
 * @return e^x - 1, within 1 ulp; infinity past EXP_OVERFLOW, -1 below -56 ln 2, x itself under 2^-54, NaN for NaN.
 */
//SPEC: fdlibm s_expm1.c
exp_minus_one_64 :: fn(x_in: f64) -> f64 {
    x := x_in
    hx := cast[u32](high_word(x))
    negative :: (hx & 0x8000_0000) != 0
    hx &= 0x7fff_ffff
    // Huge or not finite
    if hx >= 0x4043_687a {
        if hx >= 0x4086_2e42 {
            if hx >= 0x7ff0_0000 {
                if ((hx & 0xf_ffff) | low_word(x)) != 0 {
                    return x + x
                }
                return if !negative { x } else { -1.0 }
            }
            if x > EXP_OVERFLOW {
                return infinity_64()
            }
        }
        if negative {
            return -1
        }
    }
    // x = k ln 2 + x', c what rounding x' lost
    k : i32 = 0
    c := 0.0
    if hx > 0x3fd6_2e42 {
        hi := 0.0
        lo := 0.0
        if hx < 0x3ff0_a2b2 {
            if !negative {
                hi = x - LN2_HI
                lo = LN2_LO
                k = 1
            }
            else {
                hi = x + LN2_HI
                lo = -LN2_LO
                k = -1
            }
        }
        else {
            k = cast[i32](INVERSE_LN2 * x + (if !negative { 0.5 } else { -0.5 }))
            t :: cast[f64](k)
            hi = x - t * LN2_HI
            lo = t * LN2_LO
        }
        x = hi - lo
        c = (hi - x) - lo
    }
    else if hx < 0x3c90_0000 {
        return x
    }
    half_x :: 0.5 * x
    half_x_squared :: x * half_x
    r1 :: 1 + half_x_squared * (EXPM1_Q1 + half_x_squared * (EXPM1_Q2 + half_x_squared * (EXPM1_Q3 + half_x_squared
        * (EXPM1_Q4 + half_x_squared * EXPM1_Q5))))
    t := 3.0 - r1 * half_x
    e := half_x_squared * ((r1 - t) / (6.0 - x * t))
    if k == 0 {
        return x - (x * e - half_x_squared)
    }
    e = (x * (e - c) - c)
    e -= half_x_squared
    if k == -1 {
        return 0.5 * (x - e) - 0.5
    }
    if k == 1 {
        if x < -0.25 {
            return -2.0 * (e - (x + 0.5))
        }
        return 1 + 2.0 * (x - e)
    }
    if k <= -2 || k > 56 {
        y := 1 - (e - x)
        if k == 1024 {
            y = y * 2.0 * power_of_two_64(1023)
        }
        else {
            y = y * power_of_two_64(k)
        }
        return y - 1
    }
    if k < 20 {
        // 1 - 2^-k
        t = from_words(cast[i32](0x3ff0_0000 - (cast[u32](0x20_0000) >> cast[u32](k))), 0)
        return (t - (e - x)) * power_of_two_64(k)
    }
    // 2^-k
    t = from_words(cast[i32](cast[u32](0x3ff - k) << 20), 0)
    y := x - (e + t)
    y += 1
    return y * power_of_two_64(k)
}
