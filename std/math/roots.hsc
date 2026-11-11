package math

import intrinsics from "base"

/*
 * Cube roots and hypotenuses in f64 (fdlibm's s_cbrt.c, as FreeBSD has it, and musl's hypot.c). The constants' hex is
 * their bits, high word then low.
 */

/** (1023 - 1023/3 - 0.03306235651) × 2^20: a first guess at the root's high word, from x's. */
CUBE_ROOT_B1 : u32 : 715094163
/** The same for a subnormal x scaled up by 2^54. */
CUBE_ROOT_B2 : u32 : 696219795
/* A polynomial for 1 / ∛r, on r near 1 */
CUBE_ROOT_P0 : f64 : 1.87595182427177009643 // 0x3ffe03e6_0f61e692
CUBE_ROOT_P1 : f64 : -1.88497979543377169875 // 0xbffe28e0_92f02420
CUBE_ROOT_P2 : f64 : 1.621429720105354466140 // 0x3ff9f160_4a49d6c2
CUBE_ROOT_P3 : f64 : -0.758397934778766047437 // 0xbfe844cb_bee751d9
CUBE_ROOT_P4 : f64 : 0.145996192886612446982 // 0x3fc2b000_d4e4edd7

/**
 * ∛x in f64.
 *
 * @param x The number, any sign.
 * @return The real cube root, within 1 ulp, of x's sign; x for ±0, ±infinity and NaN.
 */
//SPEC: fdlibm s_cbrt.c, as FreeBSD has it
cube_root_64 :: fn(x: f64) -> f64 {
    hx := cast[u32](high_word(x))
    sign :: hx & 0x8000_0000
    hx = hx ~ sign
    if hx >= 0x7ff0_0000 {
        return x + x
    }
    // A first guess, to about 5 bits, from the exponent divided by 3
    t := 0.0
    if hx < 0x0010_0000 {
        if (hx | low_word(x)) == 0 {
            return x
        }
        t = from_words(0x4350_0000, 0) * x
        high :: cast[u32](high_word(t)) & 0x7fff_ffff
        t = from_words(cast[i32](sign | (high / 3 + CUBE_ROOT_B2)), 0)
    }
    else {
        t = from_words(cast[i32](sign | (hx / 3 + CUBE_ROOT_B1)), 0)
    }
    // To 23 bits by the polynomial
    r := (t * t) * (t / x)
    t = t * ((CUBE_ROOT_P0 + r * (CUBE_ROOT_P1 + r * CUBE_ROOT_P2)) + ((r * r) * r) * (CUBE_ROOT_P3 + r * CUBE_ROOT_P4))
    // Rounded away from 0 to 23 bits, so t × t is exact
    t = bit_cast[f64]((bit_cast[u64](t) + 0x8000_0000) & 0xffff_ffff_c000_0000)
    // One Newton step, to 53 bits
    s :: t * t
    r = x / s
    w :: t + t
    r = (r - t) / (w + r)
    return t + t * r
}

/** 2^27 + 1, which splits an f64 in two halves whose products are exact. */
HYPOTENUSE_SPLIT : f64 : 134217729.0

/**
 * x² as hi + lo, exactly.
 *
 * @param x The number, small enough that x² doesn't overflow nor its tail underflow.
 * @return hi, x² rounded, and lo, the rest.
 */
//SPEC: musl src/math/hypot.c sq
square_exactly_64 :: fn(x: f64) -> (f64, f64) {
    xc :: x * HYPOTENUSE_SPLIT
    xh :: x - xc + xc
    xl :: x - xh
    hi :: x * x
    lo :: xh * xh - hi + 2 * xh * xl + xl * xl
    return hi, lo
}

/**
 * √(x² + y²) in f64, without overflowing or underflowing where the result doesn't.
 *
 * @param x_in One side.
 * @param y_in The other.
 * @return The hypotenuse, within 1 ulp; infinity if either is infinite, even with a NaN; NaN otherwise if either is
 *     NaN.
 */
//SPEC: musl src/math/hypot.c
hypotenuse_64 :: fn(x_in: f64, y_in: f64) -> f64 {
    ux := bit_cast[u64](x_in) & 0x7fff_ffff_ffff_ffff
    uy := bit_cast[u64](y_in) & 0x7fff_ffff_ffff_ffff
    // |x| at least |y|
    if ux < uy {
        swapped :: ux
        ux = uy
        uy = swapped
    }
    ex :: cast[i32](ux >> 52)
    ey :: cast[i32](uy >> 52)
    x := bit_cast[f64](ux)
    y := bit_cast[f64](uy)
    if ey == 0x7ff {
        return y
    }
    if ex == 0x7ff || uy == 0 {
        return x
    }
    // y too small to matter
    if ex - ey > 64 {
        return x + y
    }
    // Scaled so the squares neither overflow nor lose their tails
    z := 1.0
    if ex > 0x3ff + 510 {
        z = power_of_two_64(700)
        x *= power_of_two_64(-700)
        y *= power_of_two_64(-700)
    }
    else if ey < 0x3ff - 450 {
        z = power_of_two_64(-700)
        x *= power_of_two_64(700)
        y *= power_of_two_64(700)
    }
    hx, lx :: square_exactly_64(x)
    hy, ly :: square_exactly_64(y)
    return z * intrinsics.square_root(ly + lx + hy + hx)
}
