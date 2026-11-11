package math

/*
 * Remainders in f64, which are exact: x - n × y for the n truncated (musl's fmod.c) or rounded to even (fdlibm's
 * e_remainder.c).
 */

/**
 * x - n × y, n the quotient x / y truncated toward 0, exactly: C's fmod.
 *
 * @param x The dividend.
 * @param y The divisor.
 * @return The remainder, of x's sign and smaller than |y|; x for a finite x and infinite y; NaN if y is 0, x is
 *     infinite, or either is NaN.
 */
//SPEC: musl src/math/fmod.c
truncated_remainder_64 :: fn(x: f64, y: f64) -> f64 {
    ux := bit_cast[u64](x)
    uy := bit_cast[u64](y)
    ex := cast[i32]((ux >> 52) & 0x7ff)
    ey := cast[i32]((uy >> 52) & 0x7ff)
    sign :: ux >> 63
    if (uy << 1) == 0 || y != y || ex == 0x7ff {
        return (x * y) / (x * y)
    }
    if (ux << 1) <= (uy << 1) {
        if (ux << 1) == (uy << 1) {
            return 0 * x
        }
        return x
    }
    // Significands with their leading 1, subnormals shifted up to have one
    if ex == 0 {
        i := ux << 12
        loop {
            ex -= 1
            i <<= 1
        }
        while (i >> 63) == 0
        ux <<= cast[u32](-ex + 1)
    }
    else {
        ux &= 0x000f_ffff_ffff_ffff
        ux |= 0x0010_0000_0000_0000
    }
    if ey == 0 {
        i := uy << 12
        loop {
            ey -= 1
            i <<= 1
        }
        while (i >> 63) == 0
        uy <<= cast[u32](-ey + 1)
    }
    else {
        uy &= 0x000f_ffff_ffff_ffff
        uy |= 0x0010_0000_0000_0000
    }
    // Long division, a bit at a time
    loop {
        i :: ux - uy
        if (i >> 63) == 0 {
            if i == 0 {
                return 0 * x
            }
            ux = i
        }
        ux <<= 1
        ex -= 1
    }
    while ex > ey
    i :: ux - uy
    if (i >> 63) == 0 {
        if i == 0 {
            return 0 * x
        }
        ux = i
    }
    loop {
        ux <<= 1
        ex -= 1
    }
    while (ux >> 52) == 0
    // Back to a float, subnormal if it's small
    if ex > 0 {
        ux -= 0x0010_0000_0000_0000
        ux |= cast[u64](ex) << 52
    }
    else {
        ux >>= cast[u32](-ex + 1)
    }
    ux |= sign << 63
    return bit_cast[f64](ux)
}

/**
 * x - n × y, n the quotient x / y rounded to nearest, halfway to even, exactly: IEEE 754's remainder.
 *
 * @param x_in The dividend.
 * @param y The divisor.
 * @return The remainder, at most |y| / 2 in magnitude, and -0 or +0 as x's sign when it's 0; x for a finite x and
 *     infinite y; NaN if y is 0, x is infinite, or either is NaN.
 */
//SPEC: fdlibm e_remainder.c
remainder_64 :: fn(x_in: f64, y: f64) -> f64 {
    x := x_in
    negative :: (bit_cast[u64](x) >> 63) != 0
    p := abs(y)
    if p == 0 || x != x || y != y || abs(x) == infinity_64() {
        return (x * y) / (x * y)
    }
    if p == infinity_64() {
        return x
    }
    // Now |x| < 2p
    if high_word(p) <= 0x7fdf_ffff {
        x = truncated_remainder_64(x, p + p)
    }
    if abs(x) == p {
        return 0 * x
    }
    x = abs(x)
    if high_word(p) < 0x0020_0000 {
        if x + x > p {
            x -= p
            if x + x >= p {
                x -= p
            }
        }
    }
    else {
        half :: 0.5 * p
        if x > half {
            x -= p
            if x >= half {
                x -= p
            }
        }
    }
    if x == 0 {
        x = 0
    }
    return if negative { -x } else { x }
}
