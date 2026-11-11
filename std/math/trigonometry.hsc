package math

import intrinsics from "base"
import runtime from "base"

/*
 * sin, cos and tan in f64 (fdlibm's s_sin.c, s_cos.c, s_tan.c, k_sin.c, k_cos.c, k_tan.c, e_rem_pio2.c and
 * k_rem_pio2.c): the argument reduced by π/2 to within π/4 of 0, exactly enough at any size, then a polynomial. The
 * constants' hex is their bits, high word then low.
 */

/* sin's polynomial on [-π/4, π/4] */
SIN_S1 : f64 : -1.66666666666666324348e-01 // 0xbfc55555_55555549
SIN_S2 : f64 : 8.33333333332248946124e-03 // 0x3f811111_1110f8a6
SIN_S3 : f64 : -1.98412698298579493134e-04 // 0xbf2a01a0_19c161d5
SIN_S4 : f64 : 2.75573137070700676789e-06 // 0x3ec71de3_57b1fe7d
SIN_S5 : f64 : -2.50507602534068634195e-08 // 0xbe5ae5e6_8a2b9ceb
SIN_S6 : f64 : 1.58969099521155010221e-10 // 0x3de5d93a_5acfd57c

/* cos's */
COS_C1 : f64 : 4.16666666666666019037e-02 // 0x3fa55555_5555554c
COS_C2 : f64 : -1.38888888888741095749e-03 // 0xbf56c16c_16c15177
COS_C3 : f64 : 2.48015872894767294178e-05 // 0x3efa01a0_19cb1590
COS_C4 : f64 : -2.75573143513906633035e-07 // 0xbe927e4f_809c52ad
COS_C5 : f64 : 2.08757232129817482790e-09 // 0x3e21ee9e_bdb4b1c4
COS_C6 : f64 : -1.13596475577881948265e-11 // 0xbda8fae9_be8838d4

/* tan's, T[0] to T[12] */
TAN_T0 : f64 : 3.33333333333334091986e-01 // 0x3fd55555_55555563
TAN_T1 : f64 : 1.33333333333201242699e-01 // 0x3fc11111_1110fe7a
TAN_T2 : f64 : 5.39682539762260521377e-02 // 0x3faba1ba_1bb341fe
TAN_T3 : f64 : 2.18694882948595424599e-02 // 0x3f9664f4_8406d637
TAN_T4 : f64 : 8.86323982359930005737e-03 // 0x3f8226e3_e96e8493
TAN_T5 : f64 : 3.59207910759131235356e-03 // 0x3f6d6d22_c9560328
TAN_T6 : f64 : 1.45620945432529025516e-03 // 0x3f57dbc8_fee08315
TAN_T7 : f64 : 5.88041240820264096874e-04 // 0x3f4344d8_f2f26501
TAN_T8 : f64 : 2.46463134818469906812e-04 // 0x3f3026f7_1a8d1068
TAN_T9 : f64 : 7.81794442939557092300e-05 // 0x3f147e88_a03792a6
TAN_T10 : f64 : 7.14072491382608190305e-05 // 0x3f12b80f_32f0a7e9
TAN_T11 : f64 : -1.85586374855275456654e-05 // 0xbef375cb_db605373
TAN_T12 : f64 : 2.59073051863633712884e-05 // 0x3efb2a70_74bf7ad4
/** π/4. */
PI_OVER_4 : f64 : 7.85398163397448278999e-01 // 0x3fe921fb_54442d18
/** π/4 - PI_OVER_4. */
PI_OVER_4_LO : f64 : 3.06161699786838301793e-17 // 0x3c81a626_33145c07

/** 1.5 × 2^52: adding and taking it away rounds to a whole number. */
TO_WHOLE : f64 : 6755399441055744.0 // 0x43380000_00000000
/** 2 / π. */
INVERSE_PI_OVER_2 : f64 : 6.36619772367581382433e-01 // 0x3fe45f30_6dc9c883
/* π/2 in three pieces of 33 bits, each with the rest of π/2 after it */
PI_OVER_2_1 : f64 : 1.57079632673412561417 // 0x3ff921fb_54400000
PI_OVER_2_1_TAIL : f64 : 6.07710050650619224932e-11 // 0x3dd0b461_1a626331
PI_OVER_2_2 : f64 : 6.07710050630396597660e-11 // 0x3dd0b461_1a600000
PI_OVER_2_2_TAIL : f64 : 2.02226624879595063154e-21 // 0x3ba3198a_2e037073
PI_OVER_2_3 : f64 : 2.02226624871116645580e-21 // 0x3ba3198a_2e000000
PI_OVER_2_3_TAIL : f64 : 8.47842766036889956997e-32 // 0x397b839a_252049c1

/** 2/π's bits, 24 at a time, from the top: as many as reducing an f64 needs. */
TWO_OVER_PI_WORDS :: i32.[
    0xa2f983, 0x6e4e44, 0x1529fc, 0x2757d1, 0xf534dd, 0xc0db62, 0x95993c, 0x439041, 0xfe5163, 0xabdebb, 0xc561b7,
    0x246e3a, 0x424dd2, 0xe00649, 0x2eea09, 0xd1921c, 0xfe1deb, 0x1cb129, 0xa73ee8, 0x8235f5, 0x2ebb44, 0x84e99c,
    0x7026b4, 0x5f7e41, 0x3991d6, 0x398353, 0x39f49c, 0x845f8b, 0xbdf928, 0x3b1ff8, 0x97ffde, 0x05980f, 0xef2f11,
    0x8b5a0a, 0x6d1f6d, 0x367ecf, 0x27cb09, 0xb74f46, 0x3f669e, 0x5fea2d, 0x7527ba, 0xc7ebe5, 0xf17b3d, 0x0739f7,
    0x8a5292, 0xea6bfb, 0x5fb11f, 0x8d5d08, 0x560330, 0x46fc7b, 0x6babf0, 0xcfbc20, 0x9af436, 0x1da9e3, 0x91615e,
    0xe61b08, 0x659985, 0x5f14a0, 0x68408d, 0xffd880, 0x4d7327, 0x310606, 0x1556ca, 0x73a8c9, 0x60e27b, 0xc08c6b,
]

/** π/2 in pieces of 24 bits, each the rest of π/2 after those before it. */
PI_OVER_2_PIECES :: f64.[
    1.57079625129699707031, // 0x3ff921fb_40000000
    7.54978941586159635335e-08, // 0x3e74442d_00000000
    5.39030252995776476554e-15, // 0x3cf84698_80000000
    3.28200341580791294123e-22, // 0x3b78cc51_60000000
    1.27065575308067607349e-29, // 0x39f01b83_80000000
    1.22933308981111328932e-36, // 0x387a2520_40000000
    2.73370053816464559624e-44, // 0x36e38222_80000000
    2.16741683877804819444e-51, // 0x3569f31d_00000000
]

/**
 * sin x on [-π/4, π/4], given as x + y with y the part of the reduced argument x couldn't hold.
 *
 * @param x The argument's top part.
 * @param y Its tail.
 * @param has_tail Whether y is to be used; false when it's 0.
 * @return sin(x + y), within 1 ulp.
 */
//SPEC: fdlibm k_sin.c
sin_kernel_64 :: fn(x: f64, y: f64, has_tail: bool) -> f64 {
    z :: x * x
    w :: z * z
    r :: SIN_S2 + z * (SIN_S3 + z * SIN_S4) + z * w * (SIN_S5 + z * SIN_S6)
    v :: z * x
    if !has_tail {
        return x + v * (SIN_S1 + z * r)
    }
    return x - ((z * (0.5 * y - v * r) - y) - v * SIN_S1)
}

/**
 * cos x on [-π/4, π/4], given as x + y.
 *
 * @param x The argument's top part.
 * @param y Its tail.
 * @return cos(x + y), within 1 ulp.
 */
//SPEC: fdlibm k_cos.c
cos_kernel_64 :: fn(x: f64, y: f64) -> f64 {
    z :: x * x
    w := z * z
    r :: z * (COS_C1 + z * (COS_C2 + z * COS_C3)) + w * w * (COS_C4 + z * (COS_C5 + z * COS_C6))
    half_z :: 0.5 * z
    w = 1 - half_z
    return w + (((1 - w) - half_z) + (z * r - x * y))
}

/**
 * tan x, or -1 / tan x, on [-π/4, π/4], given as x + y.
 *
 * @param x_in The argument's top part.
 * @param y_in Its tail.
 * @param odd Whether -1 / tan is wanted, as for an odd count of π/2 reduced by.
 * @return tan(x + y), or -1 / tan(x + y), within 1 ulp.
 */
//SPEC: fdlibm k_tan.c, as musl's __tan
tan_kernel_64 :: fn(x_in: f64, y_in: f64, odd: bool) -> f64 {
    x := x_in
    y := y_in
    hx :: high_word(x)
    // At least 0.6744: tan(π/4 - x) is worked out instead, as it's nearer 0
    big :: (hx & 0x7fff_ffff) >= 0x3fe5_9428
    negative :: hx < 0
    if big {
        if negative {
            x = -x
            y = -y
        }
        x = (PI_OVER_4 - x) + (PI_OVER_4_LO - y)
        y = 0.0
    }
    z := x * x
    w := z * z
    // x^5 × (T1 + x²T2 + ...), the odd and even terms apart
    r := TAN_T1 + w * (TAN_T3 + w * (TAN_T5 + w * (TAN_T7 + w * (TAN_T9 + w * TAN_T11))))
    v := z * (TAN_T2 + w * (TAN_T4 + w * (TAN_T6 + w * (TAN_T8 + w * (TAN_T10 + w * TAN_T12)))))
    s := z * x
    r = y + z * (s * (r + v) + y) + s * TAN_T0
    w = x + r
    if big {
        s = if odd { -1.0 } else { 1.0 }
        v = s - 2.0 * (x + (r - w * w / (w + s)))
        return if negative { -v } else { v }
    }
    if !odd {
        return w
    }
    // -1 / (x + r), accurately: w0 + v = x + r, and a0 its reciprocal's top bits
    w0 :: with_low_word(w, 0)
    v = r - (w0 - x)
    a :: -1.0 / w
    a0 :: with_low_word(a, 0)
    return a0 + a * (1.0 + a0 * w0 + a0 * v)
}

/**
 * Reduce x by π/2 for a large x: x - n π/2, from 2/π's bits, as many as x's size needs, so nothing's lost however big.
 *
 * @param x x's 24-bit pieces, x / 2^e0 = x[0] + x[1] / 2^24 + x[2] / 2^48, whole numbers below 2^24; x[3] is unused.
 * @param pieces How many pieces there are, 1 to 3, the last not 0.
 * @param e0 x's exponent less 23: x[0]'s place.
 * @return n modulo 8, and x - n π/2 as y0 + y1, between -π/4 and π/4.
 */
//SPEC: fdlibm k_rem_pio2.c, prec 1
reduce_large_64 :: fn(x: f64[4], pieces: i32, e0: i32) -> (i32, f64, f64) {
    jk :: 4
    jp :: jk
    jx :: pieces - 1
    jv := (e0 - 3) / 24
    if jv < 0 {
        jv = 0
    }
    q0 := e0 - 24 * (jv + 1)
    /*
     * Indexes are masked to the arrays' 32, which they never reach: jz is at most jk plus the few terms recomputing
     * adds, as the source's arrays of 20 say
     */
    f : f64[32]
    q : f64[32]
    fq : f64[32]
    iq : i32[32]
    // f[0] to f[jx + jk], 2/π's words from jv - jx on, zero before the first
    j := jv - jx
    m :: jx + jk
    i : i32 = 0
    loop {
        f[cast[usize](i) & 31] = two_over_pi_word(j)
        i += 1
        j += 1
    }
    while i <= m
    // q[0] to q[jk]
    i = 0
    loop {
        sum := 0.0
        k : i32 = 0
        loop {
            sum += x[cast[usize](k) & 3] * f[cast[usize](jx + i - k) & 31]
            k += 1
        }
        while k <= jx
        q[cast[usize](i) & 31] = sum
        i += 1
    }
    while i <= jk
    jz : i32 = jk
    n : i32 = 0
    ih : i32 = 0
    z := 0.0
    loop {
        // q[] distilled into iq[], 24 bits each, from the end
        i = 0
        j = jz
        z = q[cast[usize](jz) & 31]
        loop {
            fw :: cast[f64](cast[i32](TWO_TO_MINUS_24 * z))
            iq[cast[usize](i) & 31] = cast[i32](z - TWO_TO_24 * fw)
            z = q[cast[usize](j - 1) & 31] + fw
            i += 1
            j -= 1
        }
        while j > 0
        // n, the whole part of z modulo 8
        z = runtime.scale_by_power_of_two(z, q0)
        z -= 8.0 * intrinsics.floor(z * 0.125)
        n = cast[i32](z)
        z -= cast[f64](n)
        ih = 0
        if q0 > 0 {
            top :: jz - 1
            i = iq[cast[usize](top) & 31] >> cast[u32](24 - q0)
            n += i
            iq[cast[usize](top) & 31] -= i << cast[u32](24 - q0)
            ih = iq[cast[usize](top) & 31] >> cast[u32](23 - q0)
        }
        else if q0 == 0 {
            ih = iq[cast[usize](jz - 1) & 31] >> 23
        }
        else if z >= 0.5 {
            ih = 2
        }
        // Past a half: 1 - q, and n one more
        if ih > 0 {
            n += 1
            carry : i32 = 0
            i = 0
            loop {
                word :: iq[cast[usize](i) & 31]
                if carry == 0 {
                    if word != 0 {
                        carry = 1
                        iq[cast[usize](i) & 31] = 0x100_0000 - word
                    }
                }
                else {
                    iq[cast[usize](i) & 31] = 0xff_ffff - word
                }
                i += 1
            }
            while i < jz
            if q0 == 1 {
                iq[cast[usize](jz - 1) & 31] &= 0x7f_ffff
            }
            else if q0 == 2 {
                iq[cast[usize](jz - 1) & 31] &= 0x3f_ffff
            }
            if ih == 2 {
                z = 1.0 - z
                if carry != 0 {
                    z -= runtime.scale_by_power_of_two(1.0, q0)
                }
            }
        }
        // Everything cancelled: more of 2/π's terms are needed
        if z != 0 {
            break
        }
        any : i32 = 0
        i = jz - 1
        loop {
            any |= iq[cast[usize](i) & 31]
            i -= 1
        }
        while i >= jk
        if any != 0 {
            break
        }
        more : i32 = 1
        loop {
            more += 1
        }
        while iq[cast[usize](jk - more) & 31] == 0
        i = jz + 1
        loop {
            f[cast[usize](jx + i) & 31] = two_over_pi_word(jv + i)
            sum := 0.0
            k : i32 = 0
            loop {
                sum += x[cast[usize](k) & 3] * f[cast[usize](jx + i - k) & 31]
                k += 1
            }
            while k <= jx
            q[cast[usize](i) & 31] = sum
            i += 1
        }
        while i <= jz + more
        jz += more
    }
    // Zero terms chopped off the end, or z split into 24-bit pieces
    if z == 0 {
        jz -= 1
        q0 -= 24
        loop {
            jz -= 1
            q0 -= 24
        }
        while iq[cast[usize](jz) & 31] == 0
    }
    else {
        z = runtime.scale_by_power_of_two(z, -q0)
        if z >= TWO_TO_24 {
            fw :: cast[f64](cast[i32](TWO_TO_MINUS_24 * z))
            iq[cast[usize](jz) & 31] = cast[i32](z - TWO_TO_24 * fw)
            jz += 1
            q0 += 24
            iq[cast[usize](jz) & 31] = cast[i32](fw)
        }
        else {
            iq[cast[usize](jz) & 31] = cast[i32](z)
        }
    }
    // The pieces as floats
    fw := runtime.scale_by_power_of_two(1.0, q0)
    i = jz
    loop {
        q[cast[usize](i) & 31] = fw * cast[f64](iq[cast[usize](i) & 31])
        fw *= TWO_TO_MINUS_24
        i -= 1
    }
    while i >= 0
    // π/2 times them
    i = jz
    loop {
        sum := 0.0
        k : i32 = 0
        loop {
            sum += PI_OVER_2_PIECES[cast[usize](k) & 7] * q[cast[usize](i + k) & 31]
            k += 1
        }
        while k <= jp && k <= jz - i
        fq[cast[usize](jz - i) & 31] = sum
        i -= 1
    }
    while i >= 0
    // Summed into y0 + y1
    sum := 0.0
    i = jz
    loop {
        sum += fq[cast[usize](i) & 31]
        i -= 1
    }
    while i >= 0
    y0 :: if ih == 0 { sum } else { -sum }
    sum = fq[0] - sum
    i = 1
    loop {
        sum += fq[cast[usize](i) & 31]
        i += 1
    }
    while i <= jz
    y1 :: if ih == 0 { sum } else { -sum }
    return n & 7, y0, y1
}

/** 2^24. */
TWO_TO_24 : f64 : 16777216.0
/** 2^-24. */
TWO_TO_MINUS_24 : f64 : 5.9604644775390625e-08

/**
 * Give one of 2/π's 24-bit words as a float.
 *
 * @param index Which: 0 is the first; below 0, or past the table, gives 0.
 * @return The word.
 */
two_over_pi_word :: fn(index: i32) -> f64 {
    if index < 0 || index >= cast[i32](TWO_OVER_PI_WORDS.count) {
        return 0
    }
    return cast[f64](TWO_OVER_PI_WORDS[cast[usize](index)])
}

/**
 * Reduce x by π/2: x - n π/2, between -π/4 and π/4, as y0 + y1.
 *
 * @param x The argument, finite.
 * @return n, and y0 and y1. For infinity or NaN, n is 0 and y0 and y1 NaN.
 */
//SPEC: fdlibm e_rem_pio2.c, as FreeBSD and musl have it
reduce_64 :: fn(x: f64) -> (i32, f64, f64) {
    negative :: (bit_cast[u64](x) >> 63) != 0
    ix :: high_word(x) & 0x7fff_ffff
    medium := false
    // Up to 5π/4: by π/2 or π
    if ix <= 0x400f_6a7a {
        if (ix & 0xf_ffff) == 0x9_21fb {
            // Near π/2 or π, where the cancellation needs more of π/2
            medium = true
        }
        else {
            multiple :: if ix <= 0x4002_d97c { 1.0 } else { 2.0 }
            n : i32 = if ix <= 0x4002_d97c { 1 } else { 2 }
            if !negative {
                z :: x - multiple * PI_OVER_2_1
                y0 :: z - multiple * PI_OVER_2_1_TAIL
                return n, y0, (z - y0) - multiple * PI_OVER_2_1_TAIL
            }
            z :: x + multiple * PI_OVER_2_1
            y0 :: z + multiple * PI_OVER_2_1_TAIL
            return -n, y0, (z - y0) + multiple * PI_OVER_2_1_TAIL
        }
    }
    // Up to 9π/4: by 3π/2 or 2π
    else if ix <= 0x401c_463b {
        if ix == 0x4012_d97c || ix == 0x4019_21fb {
            medium = true
        }
        else {
            multiple :: if ix <= 0x4015_fdbc { 3.0 } else { 4.0 }
            n : i32 = if ix <= 0x4015_fdbc { 3 } else { 4 }
            if !negative {
                z :: x - multiple * PI_OVER_2_1
                y0 :: z - multiple * PI_OVER_2_1_TAIL
                return n, y0, (z - y0) - multiple * PI_OVER_2_1_TAIL
            }
            z :: x + multiple * PI_OVER_2_1
            y0 :: z + multiple * PI_OVER_2_1_TAIL
            return -n, y0, (z - y0) + multiple * PI_OVER_2_1_TAIL
        }
    }
    // Up to 2^20 π/2: n from x × 2/π, and π/2 in pieces enough for the cancellation
    if medium || ix < 0x4139_21fb {
        count := (x * INVERSE_PI_OVER_2 + TO_WHOLE) - TO_WHOLE
        n := cast[i32](count)
        r := x - count * PI_OVER_2_1
        w := count * PI_OVER_2_1_TAIL
        if r - w < -PI_OVER_4 {
            n -= 1
            count -= 1
            r = x - count * PI_OVER_2_1
            w = count * PI_OVER_2_1_TAIL
        }
        else if r - w > PI_OVER_4 {
            n += 1
            count += 1
            r = x - count * PI_OVER_2_1
            w = count * PI_OVER_2_1_TAIL
        }
        y0 := r - w
        ey := cast[i32]((bit_cast[u64](y0) >> 52) & 0x7ff)
        ex :: ix >> 20
        if ex - ey > 16 {
            // A second round, good to 118 bits
            t := r
            w = count * PI_OVER_2_2
            r = t - w
            w = count * PI_OVER_2_2_TAIL - ((t - r) - w)
            y0 = r - w
            ey = cast[i32]((bit_cast[u64](y0) >> 52) & 0x7ff)
            if ex - ey > 49 {
                // A third, good to 151 bits
                t = r
                w = count * PI_OVER_2_3
                r = t - w
                w = count * PI_OVER_2_3_TAIL - ((t - r) - w)
                y0 = r - w
            }
        }
        return n, y0, (r - y0) - w
    }
    if ix >= 0x7ff0_0000 {
        nan :: x - x
        return 0, nan, nan
    }
    // |x| in 24-bit pieces, |x| / 2^e0 = pieces[0] + pieces[1] / 2^24 + pieces[2] / 2^48
    z := bit_cast[f64]((bit_cast[u64](x) & 0x000f_ffff_ffff_ffff) | (cast[u64](0x3ff + 23) << 52))
    pieces : f64[4]
    pieces[0] = cast[f64](cast[i32](z))
    z = (z - pieces[0]) * TWO_TO_24
    pieces[1] = cast[f64](cast[i32](z))
    z = (z - pieces[1]) * TWO_TO_24
    pieces[2] = z
    count : i32 = 3
    loop {
        count -= 1
    }
    while count > 1 && pieces[cast[usize](count - 1) & 3] == 0
    n, y0, y1 :: reduce_large_64(pieces, count, (ix >> 20) - (0x3ff + 23))
    if negative {
        return -n, -y0, -y1
    }
    return n, y0, y1
}

/**
 * sin x in f64.
 *
 * @param x The angle, in radians.
 * @return sin x, within 1 ulp; x for ±0, NaN for infinities and NaN.
 */
//SPEC: fdlibm s_sin.c
sin_64 :: fn(x: f64) -> f64 {
    ix :: high_word(x) & 0x7fff_ffff
    if ix <= 0x3fe9_21fb {
        // Under 2^-26, sin x rounds to x
        if ix < 0x3e50_0000 {
            return x
        }
        return sin_kernel_64(x, 0, false)
    }
    if ix >= 0x7ff0_0000 {
        return x - x
    }
    n, y0, y1 :: reduce_64(x)
    quadrant :: n & 3
    match quadrant {
        case 0 => return sin_kernel_64(y0, y1, true)
        case 1 => return cos_kernel_64(y0, y1)
        case 2 => return -sin_kernel_64(y0, y1, true)
        case _ => return -cos_kernel_64(y0, y1)
    }
}

/**
 * cos x in f64.
 *
 * @param x The angle, in radians.
 * @return cos x, within 1 ulp; NaN for infinities and NaN.
 */
//SPEC: fdlibm s_cos.c
cos_64 :: fn(x: f64) -> f64 {
    ix :: high_word(x) & 0x7fff_ffff
    if ix <= 0x3fe9_21fb {
        // Under 2^-27 √2, cos x rounds to 1
        if ix < 0x3e46_a09e {
            return 1
        }
        return cos_kernel_64(x, 0)
    }
    if ix >= 0x7ff0_0000 {
        return x - x
    }
    n, y0, y1 :: reduce_64(x)
    quadrant :: n & 3
    match quadrant {
        case 0 => return cos_kernel_64(y0, y1)
        case 1 => return -sin_kernel_64(y0, y1, true)
        case 2 => return -cos_kernel_64(y0, y1)
        case _ => return sin_kernel_64(y0, y1, true)
    }
}

/**
 * sin x and cos x together in f64, reducing x once.
 *
 * @param x The angle, in radians.
 * @return sin x and cos x, each as sin_64 and cos_64 give it.
 */
sin_cos_64 :: fn(x: f64) -> (f64, f64) {
    ix :: high_word(x) & 0x7fff_ffff
    if ix <= 0x3fe9_21fb {
        if ix < 0x3e46_a09e {
            s :: if ix < 0x3e50_0000 { x } else { sin_kernel_64(x, 0, false) }
            return s, 1.0
        }
        return sin_kernel_64(x, 0, false), cos_kernel_64(x, 0)
    }
    if ix >= 0x7ff0_0000 {
        return x - x, x - x
    }
    n, y0, y1 :: reduce_64(x)
    s :: sin_kernel_64(y0, y1, true)
    c :: cos_kernel_64(y0, y1)
    quadrant :: n & 3
    match quadrant {
        case 0 => return s, c
        case 1 => return c, -s
        case 2 => return -s, -c
        case _ => return -c, s
    }
}

/**
 * tan x in f64.
 *
 * @param x The angle, in radians.
 * @return tan x, within 1 ulp; x for ±0, NaN for infinities and NaN.
 */
//SPEC: fdlibm s_tan.c
tan_64 :: fn(x: f64) -> f64 {
    ix :: high_word(x) & 0x7fff_ffff
    if ix <= 0x3fe9_21fb {
        // Under 2^-27, tan x rounds to x
        if ix < 0x3e40_0000 {
            return x
        }
        return tan_kernel_64(x, 0, false)
    }
    if ix >= 0x7ff0_0000 {
        return x - x
    }
    n, y0, y1 :: reduce_64(x)
    return tan_kernel_64(y0, y1, (n & 1) != 0)
}
