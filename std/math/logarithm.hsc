package math

/*
 * Logarithms in f64: ln x, log2 x, log10 x and ln(1 + x) (fdlibm's e_log.c, e_log2.c, e_log10.c, s_log1p.c and
 * k_log.h). The constants' hex is their bits, high word then low.
 */

/** 2^54, to scale subnormals up. */
TWO_TO_54 : f64 : 1.80143985094819840000e16 // 0x43500000_00000000

/* The polynomial for ln((1 + s) / (1 - s)) - 2s, in s² */
LOG_LG1 : f64 : 6.666666666666735130e-01 // 0x3fe55555_55555593
LOG_LG2 : f64 : 3.999999999940941908e-01 // 0x3fd99999_9997fa04
LOG_LG3 : f64 : 2.857142874366239149e-01 // 0x3fd24924_94229359
LOG_LG4 : f64 : 2.222219843214978396e-01 // 0x3fcc71c5_1d8e78af
LOG_LG5 : f64 : 1.818357216161805012e-01 // 0x3fc74664_96cb03de
LOG_LG6 : f64 : 1.531383769920937332e-01 // 0x3fc39a09_d078c69f
LOG_LG7 : f64 : 1.479819860511658591e-01 // 0x3fc2f112_df3e5244

/** 1 / ln 2's top bits. */
INVERSE_LN2_HI : f64 : 1.44269504072144627571 // 0x3ff71547_65200000
/** 1 / ln 2 - INVERSE_LN2_HI. */
INVERSE_LN2_LO : f64 : 1.67517131648865118353e-10 // 0x3de705fc_2eefa200
/** 1 / ln 10's top bits. */
INVERSE_LN10_HI : f64 : 4.34294481878168880939e-01 // 0x3fdbcb7b_15200000
/** 1 / ln 10 - INVERSE_LN10_HI. */
INVERSE_LN10_LO : f64 : 2.50829467116452752298e-11 // 0x3dbb9438_ca9aadd5
/** log10 2's top bits. */
LOG10_2_HI : f64 : 3.01029995663611771306e-01 // 0x3fd34413_509f6000
/** log10 2 - LOG10_2_HI. */
LOG10_2_LO : f64 : 3.69423907715893078616e-13 // 0x3d59fef3_11f12b36

/**
 * ln(1 + f) - f + f²/2, for 1 + f from √2/2 to √2: the part log2 and log10 add their own way.
 *
 * @param f The fraction.
 * @return The remainder.
 */
//SPEC: fdlibm k_log.h k_log1p
log_one_plus_kernel_64 :: fn(f: f64) -> f64 {
    s :: f / (2.0 + f)
    z :: s * s
    w :: z * z
    t1 :: w * (LOG_LG2 + w * (LOG_LG4 + w * LOG_LG6))
    t2 :: z * (LOG_LG1 + w * (LOG_LG3 + w * (LOG_LG5 + w * LOG_LG7)))
    r :: t2 + t1
    half_f_squared :: 0.5 * f * f
    return s * (half_f_squared + r)
}

/**
 * Split x, positive and finite, into k and f with x = 2^k × (1 + f), 1 + f from √2/2 to √2: what log2 and log10
 * start with.
 *
 * @param x_in The number: positive, finite and not 0.
 * @return k and f.
 */
log_split_64 :: fn(x_in: f64) -> (i32, f64) {
    x := x_in
    hx := high_word(x)
    k : i32 = 0
    if hx < 0x0010_0000 {
        k -= 54
        x *= TWO_TO_54
        hx = high_word(x)
    }
    k += (hx >> 20) - 1023
    hx &= 0x000f_ffff
    i :: (hx + 0x9_5f64) & 0x10_0000
    // x or x / 2, from √2/2 to √2
    x = with_high_word(x, hx | (i ~ 0x3ff0_0000))
    k += i >> 20
    return k, x - 1.0
}

/**
 * Give what a logarithm is of a number it has no finite value for: -infinity for ±0, NaN below 0 or for NaN, and
 * infinity for infinity.
 *
 * @param x The number.
 * @return The value, if x is one of those; none for a positive finite x.
 */
log_special_64 :: fn(x: f64) -> f64? {
    hx :: high_word(x)
    if hx < 0x0010_0000 {
        if ((hx & 0x7fff_ffff) | cast[i32](low_word(x))) == 0 {
            return -infinity_64()
        }
        if hx < 0 {
            return nan_64()
        }
    }
    if hx >= 0x7ff0_0000 {
        return x + x
    }
    return null
}

/**
 * ln x in f64.
 *
 * @param x_in The number.
 * @return ln x, within 1 ulp; -infinity for ±0, NaN below 0 and for NaN, infinity for infinity.
 */
//SPEC: fdlibm e_log.c
log_64 :: fn(x_in: f64) -> f64 {
    x := x_in
    hx := high_word(x)
    k : i32 = 0
    if hx < 0x0010_0000 {
        if ((hx & 0x7fff_ffff) | cast[i32](low_word(x))) == 0 {
            return -infinity_64()
        }
        if hx < 0 {
            return nan_64()
        }
        k -= 54
        x *= TWO_TO_54
        hx = high_word(x)
    }
    if hx >= 0x7ff0_0000 {
        return x + x
    }
    k += (hx >> 20) - 1023
    hx &= 0x000f_ffff
    i := (hx + 0x9_5f64) & 0x10_0000
    // x or x / 2, from √2/2 to √2
    x = with_high_word(x, hx | (i ~ 0x3ff0_0000))
    k += i >> 20
    f :: x - 1.0
    // |f| under 2^-20
    if (0x000f_ffff & (2 + hx)) < 3 {
        if f == 0 {
            if k == 0 {
                return 0
            }
            dk :: cast[f64](k)
            return dk * LN2_HI + dk * LN2_LO
        }
        r :: f * f * (0.5 - 0.33333333333333333 * f)
        if k == 0 {
            return f - r
        }
        dk :: cast[f64](k)
        return dk * LN2_HI - ((r - dk * LN2_LO) - f)
    }
    s :: f / (2.0 + f)
    dk :: cast[f64](k)
    z :: s * s
    i = hx - 0x6_147a
    w :: z * z
    j :: 0x6_b851 - hx
    t1 :: w * (LOG_LG2 + w * (LOG_LG4 + w * LOG_LG6))
    t2 :: z * (LOG_LG1 + w * (LOG_LG3 + w * (LOG_LG5 + w * LOG_LG7)))
    i |= j
    r :: t2 + t1
    if i > 0 {
        half_f_squared :: 0.5 * f * f
        if k == 0 {
            return f - (half_f_squared - s * (half_f_squared + r))
        }
        return dk * LN2_HI - ((half_f_squared - (s * (half_f_squared + r) + dk * LN2_LO)) - f)
    }
    if k == 0 {
        return f - s * (f - r)
    }
    return dk * LN2_HI - ((s * (f - r) - dk * LN2_LO) - f)
}

/**
 * log2 x in f64.
 *
 * @param x The number.
 * @return log2 x, within 1 ulp, exact for powers of two; -infinity for ±0, NaN below 0 and for NaN, infinity for
 *     infinity.
 */
//SPEC: fdlibm e_log2.c
log2_64 :: fn(x: f64) -> f64 {
    special :: log_special_64(x)
    if special is_some {
        return special or_else x
    }
    if x == 1 {
        return 0
    }
    k, f :: log_split_64(x)
    y :: cast[f64](k)
    half_f_squared :: 0.5 * f * f
    r :: log_one_plus_kernel_64(f)
    // f - f²/2 in two parts, the top one short so its products below are exact
    hi :: with_low_word(f - half_f_squared, 0)
    lo :: (f - hi) - half_f_squared + r
    value_hi := hi * INVERSE_LN2_HI
    value_lo := (lo + hi) * INVERSE_LN2_LO + lo * INVERSE_LN2_HI
    w :: y + value_hi
    value_lo += (y - w) + value_hi
    value_hi = w
    return value_lo + value_hi
}

/**
 * log10 x in f64.
 *
 * @param x The number.
 * @return log10 x, within 1 ulp; -infinity for ±0, NaN below 0 and for NaN, infinity for infinity.
 */
//SPEC: fdlibm e_log10.c
log10_64 :: fn(x: f64) -> f64 {
    special :: log_special_64(x)
    if special is_some {
        return special or_else x
    }
    if x == 1 {
        return 0
    }
    k, f :: log_split_64(x)
    y :: cast[f64](k)
    half_f_squared :: 0.5 * f * f
    r :: log_one_plus_kernel_64(f)
    hi :: with_low_word(f - half_f_squared, 0)
    lo :: (f - hi) - half_f_squared + r
    value_hi := hi * INVERSE_LN10_HI
    y2 :: y * LOG10_2_HI
    value_lo := y * LOG10_2_LO + (lo + hi) * INVERSE_LN10_LO + lo * INVERSE_LN10_HI
    w :: y2 + value_hi
    value_lo += (y2 - w) + value_hi
    value_hi = w
    return value_lo + value_hi
}

/**
 * ln(1 + x) in f64, accurate where x is near 0, where log(1 + x) would lose it.
 *
 * @param x The number.
 * @return ln(1 + x), within 1 ulp; -infinity at -1, NaN below -1 and for NaN, infinity for infinity, x itself under
 *     2^-54.
 */
//SPEC: fdlibm s_log1p.c
log_one_plus_64 :: fn(x: f64) -> f64 {
    hx :: high_word(x)
    ax :: hx & 0x7fff_ffff
    k : i32 = 1
    f := 0.0
    c := 0.0
    hu : i32 = 0
    // 1 + x below √2
    if hx < 0x3fda_827a {
        if ax >= 0x3ff0_0000 {
            if x == -1.0 {
                return -infinity_64()
            }
            return nan_64()
        }
        // Under 2^-29
        if ax < 0x3e20_0000 {
            if ax < 0x3c90_0000 {
                return x
            }
            return x - x * x * 0.5
        }
        // √2/2 <= 1 + x < √2: no reduction
        if hx > 0 || hx <= cast[i32](cast[u32](0xbfd2_bec4)) {
            k = 0
            f = x
            hu = 1
        }
    }
    if hx >= 0x7ff0_0000 {
        return x + x
    }
    if k != 0 {
        u := 0.0
        if hx < 0x4340_0000 {
            u = 1.0 + x
            hu = high_word(u)
            k = (hu >> 20) - 1023
            // What 1 + x lost, as a fraction of u
            c = if k > 0 { 1.0 - (u - x) } else { x - (u - 1.0) }
            c /= u
        }
        else {
            u = x
            hu = high_word(u)
            k = (hu >> 20) - 1023
            c = 0
        }
        hu &= 0x000f_ffff
        if hu < 0x6_a09e {
            u = with_high_word(u, hu | 0x3ff0_0000)
        }
        else {
            k += 1
            u = with_high_word(u, hu | 0x3fe0_0000)
            hu = (0x0010_0000 - hu) >> 2
        }
        f = u - 1.0
    }
    half_f_squared :: 0.5 * f * f
    dk :: cast[f64](k)
    // |f| under 2^-20
    if hu == 0 {
        if f == 0 {
            if k == 0 {
                return 0
            }
            return dk * LN2_HI + (c + dk * LN2_LO)
        }
        r :: half_f_squared * (1.0 - 0.66666666666666666 * f)
        if k == 0 {
            return f - r
        }
        return dk * LN2_HI - ((r - (dk * LN2_LO + c)) - f)
    }
    s :: f / (2.0 + f)
    z :: s * s
    r :: z * (LOG_LG1 + z * (LOG_LG2 + z * (LOG_LG3 + z * (LOG_LG4 + z * (LOG_LG5 + z * (LOG_LG6 + z * LOG_LG7))))))
    if k == 0 {
        return f - (half_f_squared - s * (half_f_squared + r))
    }
    return dk * LN2_HI - ((half_f_squared - (s * (half_f_squared + r) + (dk * LN2_LO + c))) - f)
}
