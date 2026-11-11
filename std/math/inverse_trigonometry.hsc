package math

import intrinsics from "base"

/*
 * asin, acos, atan and atan2 in f64 (fdlibm's e_asin.c, e_acos.c, s_atan.c and e_atan2.c). The constants' hex is their
 * bits, high word then low.
 */

/** π/2 rounded to f64. */
PI_OVER_2_HI : f64 : 1.57079632679489655800 // 0x3ff921fb_54442d18
/** π/2 - PI_OVER_2_HI. */
PI_OVER_2_LO : f64 : 6.12323399573676603587e-17 // 0x3c91a626_33145c07
/** π rounded to f64. */
PI_64 : f64 : 3.14159265358979311600 // 0x400921fb_54442d18
/** π - PI_64. */
PI_LO : f64 : 1.2246467991473531772e-16 // 0x3ca1a626_33145c07

/* asin's and acos's rational function, R(x²) = P(x²) / Q(x²) */
ASIN_P0 : f64 : 1.66666666666666657415e-01 // 0x3fc55555_55555555
ASIN_P1 : f64 : -3.25565818622400915405e-01 // 0xbfd4d612_03eb6f7d
ASIN_P2 : f64 : 2.01212532134862925881e-01 // 0x3fc9c155_0e884455
ASIN_P3 : f64 : -4.00555345006794114027e-02 // 0xbfa48228_b5688f3b
ASIN_P4 : f64 : 7.91534994289814532176e-04 // 0x3f49efe0_7501b288
ASIN_P5 : f64 : 3.47933107596021167570e-05 // 0x3f023de1_0dfdf709
ASIN_Q1 : f64 : -2.40339491173441421878 // 0xc0033a27_1c8a2d4b
ASIN_Q2 : f64 : 2.02094576023350569471 // 0x40002ae5_9c598ac8
ASIN_Q3 : f64 : -6.88283971605453293030e-01 // 0xbfe6066c_1b8d0159
ASIN_Q4 : f64 : 7.70381505559019352791e-02 // 0x3fb3b8c5_b12e9282

/* atan's reference points' values, top and rest: atan(0.5), atan(1), atan(1.5), atan(infinity) */
ATAN_HI_0 : f64 : 4.63647609000806093515e-01 // 0x3fddac67_0561bb4f
ATAN_HI_1 : f64 : 7.85398163397448278999e-01 // 0x3fe921fb_54442d18
ATAN_HI_2 : f64 : 9.82793723247329054082e-01 // 0x3fef730b_d281f69b
ATAN_HI_3 : f64 : 1.57079632679489655800 // 0x3ff921fb_54442d18
ATAN_LO_0 : f64 : 2.26987774529616870924e-17 // 0x3c7a2b7f_222f65e2
ATAN_LO_1 : f64 : 3.06161699786838301793e-17 // 0x3c81a626_33145c07
ATAN_LO_2 : f64 : 1.39033110312309984516e-17 // 0x3c700788_7af0cbbd
ATAN_LO_3 : f64 : 6.12323399573676603587e-17 // 0x3c91a626_33145c07

/* atan's polynomial */
ATAN_T0 : f64 : 3.33333333333329318027e-01 // 0x3fd55555_5555550d
ATAN_T1 : f64 : -1.99999999998764832476e-01 // 0xbfc99999_9998ebc4
ATAN_T2 : f64 : 1.42857142725034663711e-01 // 0x3fc24924_920083ff
ATAN_T3 : f64 : -1.11111104054623557880e-01 // 0xbfbc71c6_fe231671
ATAN_T4 : f64 : 9.09088713343650656196e-02 // 0x3fb745cd_c54c206e
ATAN_T5 : f64 : -7.69187620504482999495e-02 // 0xbfb3b0f2_af749a6d
ATAN_T6 : f64 : 6.66107313738753120669e-02 // 0x3fb10d66_a0d03d51
ATAN_T7 : f64 : -5.83357013379057348645e-02 // 0xbfadde2d_52defd9a
ATAN_T8 : f64 : 4.97687799461593236017e-02 // 0x3fa97b4b_24760deb
ATAN_T9 : f64 : -3.65315727442169155270e-02 // 0xbfa2b444_2c6a6c2f
ATAN_T10 : f64 : 1.62858201153657823623e-02 // 0x3f90ad3a_e322da11

/**
 * asin's and acos's R(z) = P(z) / Q(z).
 *
 * @param z The square of the reduced argument.
 * @return R(z).
 */
asin_rational_64 :: fn(z: f64) -> f64 {
    p :: z * (ASIN_P0 + z * (ASIN_P1 + z * (ASIN_P2 + z * (ASIN_P3 + z * (ASIN_P4 + z * ASIN_P5)))))
    q :: 1 + z * (ASIN_Q1 + z * (ASIN_Q2 + z * (ASIN_Q3 + z * ASIN_Q4)))
    return p / q
}

/**
 * asin x in f64.
 *
 * @param x The sine, from -1 to 1.
 * @return The angle from -π/2 to π/2 whose sine x is, within 1 ulp; NaN beyond ±1 and for NaN.
 */
//SPEC: fdlibm e_asin.c
asin_64 :: fn(x: f64) -> f64 {
    hx :: high_word(x)
    ix :: hx & 0x7fff_ffff
    if ix >= 0x3ff0_0000 {
        if ((ix - 0x3ff0_0000) | cast[i32](low_word(x))) == 0 {
            return x * PI_OVER_2_HI + x * PI_OVER_2_LO
        }
        return nan_64()
    }
    if ix < 0x3fe0_0000 {
        // Under 2^-26, asin x rounds to x
        if ix < 0x3e50_0000 {
            return x
        }
        return x + x * asin_rational_64(x * x)
    }
    // From a half to 1: asin x = π/2 - 2 asin(√((1 - x) / 2))
    w := 1 - abs(x)
    t := w * 0.5
    r :: asin_rational_64(t)
    s :: intrinsics.square_root(t)
    if ix >= 0x3fef_3333 {
        // Past 0.975
        t = PI_OVER_2_HI - (2.0 * (s + s * r) - PI_OVER_2_LO)
    }
    else {
        w = with_low_word(s, 0)
        c :: (t - w * w) / (s + w)
        p :: 2.0 * s * r - (PI_OVER_2_LO - 2.0 * c)
        q :: ATAN_HI_1 - 2.0 * w
        t = ATAN_HI_1 - (p - q)
    }
    return if hx > 0 { t } else { -t }
}

/**
 * acos x in f64.
 *
 * @param x The cosine, from -1 to 1.
 * @return The angle from 0 to π whose cosine x is, within 1 ulp; NaN beyond ±1 and for NaN.
 */
//SPEC: fdlibm e_acos.c
acos_64 :: fn(x: f64) -> f64 {
    hx :: high_word(x)
    ix :: hx & 0x7fff_ffff
    if ix >= 0x3ff0_0000 {
        if ((ix - 0x3ff0_0000) | cast[i32](low_word(x))) == 0 {
            return if hx > 0 { 0.0 } else { PI_64 + 2.0 * PI_OVER_2_LO }
        }
        return nan_64()
    }
    if ix < 0x3fe0_0000 {
        // Under 2^-57, acos x rounds to π/2
        if ix <= 0x3c60_0000 {
            return PI_OVER_2_HI + PI_OVER_2_LO
        }
        return PI_OVER_2_HI - (x - (PI_OVER_2_LO - x * asin_rational_64(x * x)))
    }
    if hx < 0 {
        // Below -0.5: π - 2 asin(√((1 + x) / 2))
        z :: (1 + x) * 0.5
        s :: intrinsics.square_root(z)
        w :: asin_rational_64(z) * s - PI_OVER_2_LO
        return PI_64 - 2.0 * (s + w)
    }
    // Above 0.5: 2 asin(√((1 - x) / 2)), the root in two parts
    z :: (1 - x) * 0.5
    s :: intrinsics.square_root(z)
    df :: with_low_word(s, 0)
    c :: (z - df * df) / (s + df)
    w :: asin_rational_64(z) * s + c
    return 2.0 * (df + w)
}

/**
 * atan x in f64.
 *
 * @param x_in The tangent.
 * @return The angle from -π/2 to π/2 whose tangent x is, within 1 ulp; ±π/2 for ±infinity, NaN for NaN.
 */
//SPEC: fdlibm s_atan.c
atan_64 :: fn(x_in: f64) -> f64 {
    x := x_in
    hx :: high_word(x)
    ix :: hx & 0x7fff_ffff
    // At least 2^66: ±π/2
    if ix >= 0x4410_0000 {
        if x != x {
            return x + x
        }
        return if hx > 0 { ATAN_HI_3 + ATAN_LO_3 } else { -ATAN_HI_3 - ATAN_LO_3 }
    }
    // Which reference point x is reduced about: atan x = atan c + atan((x - c) / (1 + xc))
    id : i32 = -1
    if ix < 0x3fdc_0000 {
        // Under 2^-27, atan x rounds to x
        if ix < 0x3e40_0000 {
            return x
        }
    }
    else {
        x = abs(x)
        if ix < 0x3ff3_0000 {
            if ix < 0x3fe6_0000 {
                id = 0
                x = (2.0 * x - 1) / (2.0 + x)
            }
            else {
                id = 1
                x = (x - 1) / (x + 1)
            }
        }
        else if ix < 0x4003_8000 {
            id = 2
            x = (x - 1.5) / (1 + 1.5 * x)
        }
        else {
            id = 3
            x = -1.0 / x
        }
    }
    z :: x * x
    w :: z * z
    s1 :: z * (ATAN_T0 + w * (ATAN_T2 + w * (ATAN_T4 + w * (ATAN_T6 + w * (ATAN_T8 + w * ATAN_T10)))))
    s2 :: w * (ATAN_T1 + w * (ATAN_T3 + w * (ATAN_T5 + w * (ATAN_T7 + w * ATAN_T9))))
    if id < 0 {
        return x - x * (s1 + s2)
    }
    hi :: if id == 0 { ATAN_HI_0 } else if id == 1 { ATAN_HI_1 } else if id == 2 { ATAN_HI_2 } else { ATAN_HI_3 }
    lo :: if id == 0 { ATAN_LO_0 } else if id == 1 { ATAN_LO_1 } else if id == 2 { ATAN_LO_2 } else { ATAN_LO_3 }
    result :: hi - ((x * (s1 + s2) - lo) - x)
    return if hx < 0 { -result } else { result }
}

/**
 * atan2(y, x) in f64: the angle of the point (x, y) from the positive x axis.
 *
 * @param y The point's y.
 * @param x The point's x.
 * @return The angle from -π to π, within 1 ulp, with the signs of zeros and infinities as C's atan2 takes them: ±0
 *     for (+x, ±0), ±π for (-x, ±0), ±π/2 for x = 0, ±π/4 and ±3π/4 for two infinities; NaN if either is NaN.
 */
//SPEC: fdlibm e_atan2.c
atan2_64 :: fn(y: f64, x: f64) -> f64 {
    if x != x || y != y {
        return x + y
    }
    hx :: high_word(x)
    ix :: hx & 0x7fff_ffff
    lx :: low_word(x)
    hy :: high_word(y)
    iy :: hy & 0x7fff_ffff
    ly :: low_word(y)
    if hx == 0x3ff0_0000 && lx == 0 {
        return atan_64(y)
    }
    // y's sign, and x's times 2
    m := ((hy >> 31) & 1) | ((hx >> 30) & 2)
    // y = ±0
    if (cast[u32](iy) | ly) == 0 {
        match m {
            case 0 => return y
            case 1 => return y
            case 2 => return PI_64
            case _ => return -PI_64
        }
    }
    // x = ±0
    if (cast[u32](ix) | lx) == 0 {
        return if hy < 0 { -PI_OVER_2_HI } else { PI_OVER_2_HI }
    }
    if ix == 0x7ff0_0000 {
        if iy == 0x7ff0_0000 {
            match m {
                case 0 => return PI_OVER_4
                case 1 => return -PI_OVER_4
                case 2 => return 3.0 * PI_OVER_4
                case _ => return -3.0 * PI_OVER_4
            }
        }
        match m {
            case 0 => return 0.0
            case 1 => return -0.0
            case 2 => return PI_64
            case _ => return -PI_64
        }
    }
    if iy == 0x7ff0_0000 {
        return if hy < 0 { -PI_OVER_2_HI } else { PI_OVER_2_HI }
    }
    // y / x's exponent
    k :: (iy - ix) >> 20
    z := 0.0
    if k > 60 {
        // |y / x| over 2^60
        z = PI_OVER_2_HI + 0.5 * PI_LO
        m &= 1
    }
    else if hx < 0 && k < -60 {
        // Under 2^-60, toward π
        z = 0.0
    }
    else {
        z = atan_64(abs(y / x))
    }
    match m {
        case 0 => return z
        case 1 => return -z
        case 2 => return PI_64 - (z - PI_LO)
        case _ => return (z - PI_LO) - PI_64
    }
}
