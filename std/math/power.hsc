package math

import intrinsics from "base"
import runtime from "base"

/*
 * x^y in f64 (fdlibm's e_pow.c): log2 x in extra precision, times y, and 2 to that. The constants' hex is their bits,
 * high word then low.
 */

/* log2(1.5)'s top bits and the rest */
POW_DP_H : f64 : 5.84962487220764160156e-01 // 0x3fe2b803_40000000
POW_DP_L : f64 : 1.35003920212974897128e-08 // 0x3e4cfdeb_43cfd006
/** 2^53. */
TWO_TO_53 : f64 : 9007199254740992.0 // 0x43400000_00000000

/* The polynomial for log((1 + s) / (1 - s)) */
POW_L1 : f64 : 5.99999999999994648725e-01 // 0x3fe33333_33333303
POW_L2 : f64 : 4.28571428578550184252e-01 // 0x3fdb6db6_db6fabff
POW_L3 : f64 : 3.33333329818377432918e-01 // 0x3fd55555_518f264d
POW_L4 : f64 : 2.72728123808534006489e-01 // 0x3fd17460_a91d4101
POW_L5 : f64 : 2.30660745775561754067e-01 // 0x3fcd864a_93c9db65
POW_L6 : f64 : 2.06975017800338417784e-01 // 0x3fca7e28_4a454eef
/** ln 2's top 21 bits, rounded up. */
POW_LG2_H : f64 : 6.93147182464599609375e-01 // 0x3fe62e43_00000000
/** ln 2 - POW_LG2_H. */
POW_LG2_L : f64 : -1.90465429995776804525e-09 // 0xbe205c61_0ca86c39
/** What says 2^z overflows though z rounds to 1024: -(1024 - log2(the largest f64 + half an ulp)). */
POW_OVERFLOW_TAIL : f64 : 8.0085662595372944372e-17
/** 2 / (3 ln 2). */
POW_CP : f64 : 9.61796693925975554329e-01 // 0x3feec709_dc3a03fd
/** POW_CP's top bits. */
POW_CP_H : f64 : 9.61796700954437255859e-01 // 0x3feec709_e0000000
/** POW_CP - POW_CP_H. */
POW_CP_L : f64 : -7.02846165095275826516e-09 // 0xbe3e2fe0_145b01f5
/** 1 / ln 2's top 24 bits. */
POW_INVERSE_LN2_H : f64 : 1.44269502162933349609 // 0x3ff71547_60000000
/** 1 / ln 2 - POW_INVERSE_LN2_H. */
POW_INVERSE_LN2_L : f64 : 1.92596299112661746887e-08 // 0x3e54ae0b_f85ddf44

/**
 * Overflow or underflow to infinity or 0, with a sign.
 *
 * @param negative Whether the result is negative.
 * @param overflow Whether it overflows; otherwise it underflows.
 * @return ±infinity or ±0.
 */
pow_out_of_range_64 :: fn(negative: bool, overflow: bool) -> f64 {
    magnitude :: if overflow { infinity_64() } else { 0.0 }
    return if negative { -magnitude } else { magnitude }
}

/**
 * x^y in f64.
 *
 * @param x The base.
 * @param y The power.
 * @return x^y, within 1 ulp, as C's pow says: 1 for y = 0 or x = 1, NaN otherwise if either is NaN, NaN for a
 *     negative x and a y that isn't whole, infinity or 0 where it overflows or underflows, with odd whole powers of a
 *     negative x negative.
 */
//SPEC: fdlibm e_pow.c
power_64 :: fn(x: f64, y: f64) -> f64 {
    hx :: high_word(x)
    lx :: low_word(x)
    hy :: high_word(y)
    ly :: low_word(y)
    ix := hx & 0x7fff_ffff
    iy :: hy & 0x7fff_ffff
    // y = ±0, and x = 1
    if (cast[u32](iy) | ly) == 0 {
        return 1
    }
    if hx == 0x3ff0_0000 && lx == 0 {
        return 1
    }
    if x != x || y != y {
        return x + y
    }
    // For a negative x, whether y is an even whole number (2), odd (1), or not whole (0)
    whole_y : i32 = 0
    if hx < 0 {
        if iy >= 0x4340_0000 {
            whole_y = 2
        }
        else if iy >= 0x3ff0_0000 {
            k :: (iy >> 20) - 0x3ff
            if k > 20 {
                j :: ly >> cast[u32](52 - k)
                if (j << cast[u32](52 - k)) == ly {
                    whole_y = 2 - cast[i32](j & 1)
                }
            }
            else if ly == 0 {
                j :: iy >> cast[u32](20 - k)
                if (j << cast[u32](20 - k)) == iy {
                    whole_y = 2 - (j & 1)
                }
            }
        }
    }
    // y = ±infinity, ±1, 2 or 1/2
    if ly == 0 {
        if iy == 0x7ff0_0000 {
            if ((ix - 0x3ff0_0000) | cast[i32](lx)) == 0 {
                return 1
            }
            if ix >= 0x3ff0_0000 {
                return if hy >= 0 { y } else { 0.0 }
            }
            return if hy < 0 { -y } else { 0.0 }
        }
        if iy == 0x3ff0_0000 {
            return if hy < 0 { 1 / x } else { x }
        }
        if hy == 0x4000_0000 {
            return x * x
        }
        if hy == 0x3fe0_0000 && hx >= 0 {
            return intrinsics.square_root(x)
        }
    }
    ax := abs(x)
    // x = ±0, ±infinity or ±1
    if lx == 0 && (ix == 0x7ff0_0000 || ix == 0 || ix == 0x3ff0_0000) {
        z := ax
        if hy < 0 {
            z = 1 / z
        }
        if hx < 0 {
            if ((ix - 0x3ff0_0000) | whole_y) == 0 {
                return nan_64()
            }
            if whole_y == 1 {
                z = -z
            }
        }
        return z
    }
    // A negative x to a power that isn't whole
    if hx < 0 && whole_y == 0 {
        return nan_64()
    }
    // The result's sign: negative for a negative x to an odd power
    negative :: hx < 0 && whole_y == 1
    t1 := 0.0
    t2 := 0.0
    // |y| over 2^31
    if iy > 0x41e0_0000 {
        // Over 2^64: certainly overflows or underflows, unless x is 1
        if iy > 0x43f0_0000 {
            if ix <= 0x3fef_ffff {
                return pow_out_of_range_64(false, hy < 0)
            }
            if ix >= 0x3ff0_0000 {
                return pow_out_of_range_64(false, hy > 0)
            }
        }
        if ix < 0x3fef_ffff {
            return pow_out_of_range_64(negative, hy < 0)
        }
        if ix > 0x3ff0_0000 {
            return pow_out_of_range_64(negative, hy > 0)
        }
        // |1 - x| at most 2^-20: log2 x from its series
        t :: ax - 1
        w :: (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25))
        u :: POW_INVERSE_LN2_H * t
        v :: t * POW_INVERSE_LN2_L - w * INVERSE_LN2
        t1 = with_low_word(u + v, 0)
        t2 = v - (t1 - u)
    }
    else {
        n : i32 = 0
        // Subnormal x, scaled up
        if ix < 0x0010_0000 {
            ax *= TWO_TO_53
            n -= 53
            ix = high_word(ax)
        }
        n += (ix >> 20) - 0x3ff
        j :: ix & 0x000f_ffff
        // ax from 1 to 2, and whether it's nearer 1.5 than 1 or 2
        ix = j | 0x3ff0_0000
        k : i32 = 0
        if j <= 0x3_988e {
            k = 0
        }
        else if j < 0xb_b67a {
            k = 1
        }
        else {
            k = 0
            n += 1
            ix -= 0x0010_0000
        }
        ax = with_high_word(ax, ix)
        bp :: if k == 0 { 1.0 } else { 1.5 }
        dp_h :: if k == 0 { 0.0 } else { POW_DP_H }
        dp_l :: if k == 0 { 0.0 } else { POW_DP_L }
        // s = s_h + s_l = (x - 1) / (x + 1) or (x - 1.5) / (x + 1.5)
        u := ax - bp
        v := 1 / (ax + bp)
        ss :: u * v
        s_h :: with_low_word(ss, 0)
        // t_h = ax + bp, high
        t_h := from_words(((ix >> 1) | 0x2000_0000) + 0x0008_0000 + (k << 18), 0)
        t_l := ax - (t_h - bp)
        s_l :: v * ((u - s_h * t_h) - s_h * t_l)
        // log(ax)
        s2 := ss * ss
        r := s2 * s2 * (POW_L1 + s2 * (POW_L2 + s2 * (POW_L3 + s2 * (POW_L4 + s2 * (POW_L5 + s2 * POW_L6)))))
        r += s_l * (s_h + ss)
        s2 = s_h * s_h
        t_h = with_low_word(3.0 + s2 + r, 0)
        t_l = r - ((t_h - 3.0) - s2)
        // u + v = ss × (1 + ...)
        u = s_h * t_h
        v = s_l * t_h + t_l * ss
        // 2 / (3 log 2) × (ss + ...)
        p_h :: with_low_word(u + v, 0)
        p_l :: v - (p_h - u)
        z_h :: POW_CP_H * p_h
        z_l :: POW_CP_L * p_h + p_l * POW_CP + dp_l
        // log2(ax) = (ss + ...) × 2 / (3 log 2) = n + dp_h + z_h + z_l
        t :: cast[f64](n)
        t1 = with_low_word(((z_h + z_l) + dp_h) + t, 0)
        t2 = z_l - (((t1 - t) - dp_h) - z_h)
    }
    // y split into y1 + y2, so y1 × t1 is exact
    y1 :: with_low_word(y, 0)
    p_l := (y - y1) * t1 + y * t2
    p_h := y1 * t1
    z := p_l + p_h
    j := high_word(z)
    i := cast[i32](low_word(z))
    if j >= 0x4090_0000 {
        // z at least 1024
        if ((j - 0x4090_0000) | i) != 0 {
            return pow_out_of_range_64(negative, true)
        }
        if p_l + POW_OVERFLOW_TAIL > z - p_h {
            return pow_out_of_range_64(negative, true)
        }
    }
    else if (j & 0x7fff_ffff) >= 0x4090_cc00 {
        // z at most -1075
        if ((j - cast[i32](cast[u32](0xc090_cc00))) | i) != 0 {
            return pow_out_of_range_64(negative, false)
        }
        if p_l <= z - p_h {
            return pow_out_of_range_64(negative, false)
        }
    }
    // 2^(p_h + p_l): z = n + p_h, |p_h| at most a half
    i = j & 0x7fff_ffff
    k := (i >> 20) - 0x3ff
    n : i32 = 0
    if i > 0x3fe0_0000 {
        n = j + (cast[i32](0x0010_0000) >> cast[u32](k + 1))
        // The new k for n
        k = ((n & 0x7fff_ffff) >> 20) - 0x3ff
        t :: from_words(n & ~(cast[i32](0x000f_ffff) >> cast[u32](k)), 0)
        n = ((n & 0x000f_ffff) | 0x0010_0000) >> cast[u32](20 - k)
        if j < 0 {
            n = -n
        }
        p_h -= t
    }
    t := with_low_word(p_l + p_h, 0)
    u :: t * POW_LG2_H
    v :: (p_l - (t - p_h)) * LN2 + t * POW_LG2_L
    z = u + v
    w :: v - (z - u)
    t = z * z
    t1 = z - t * (EXP_P1 + t * (EXP_P2 + t * (EXP_P3 + t * (EXP_P4 + t * EXP_P5))))
    r :: (z * t1) / (t1 - 2.0) - (w + z * w)
    z = 1 - (r - z)
    j = high_word(z)
    j += cast[i32](cast[u32](n) << 20)
    if (j >> 20) <= 0 {
        // Subnormal
        z = runtime.scale_by_power_of_two(z, n)
    }
    else {
        z = with_high_word(z, j)
    }
    return if negative { -z } else { z }
}
