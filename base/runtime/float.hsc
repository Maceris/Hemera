package runtime

import intrinsics from "base"

/*
 * Fused multiply-add in software, for targets without the instruction: intrinsics.fused_multiply_add calls these, lane
 * by lane, on an x86 CPU without FMA. Exact, as the instruction is: x × y + z rounded once, to nearest, ties to even.
 */

/** Where fused_multiply_split's exponents start saying a number is infinite or NaN; zeros' are above it. */
FUSED_SPECIAL : i32 : 0x7ff - 0x3ff - 52 - 1

/**
 * Give an f64 whose bits are given.
 *
 * @param bits The bits, sign first, as IEEE 754's binary64 lays them out.
 * @return The float they make.
 */
float_of_bits #no_context :: fn(bits: u64) -> f64 {
    return bit_cast[f64](bits)
}

/**
 * Split an f64 for fused_multiply_add_f64 into a significand, an exponent and a sign, so that it's the significand ×
 * 2^exponent.
 *
 * @param x The number. A subnormal is scaled up to split as a normal one does.
 * @return The significand: for a finite x not zero, its 53 bits, the implicit 1 among them, shifted up one, so bit 53
 *     is set and bit 0 clear. The exponent: FUSED_SPECIAL for an infinity or NaN, above it for a zero, below it
 *     otherwise. And whether the sign bit is set.
 */
//SPEC: musl src/math/fma.c normalize
fused_multiply_split #no_context :: fn(x: f64) -> (u64, i32, bool) {
    bits := bit_cast[u64](x)
    sign :: (bits >> 63) != 0
    exponent := cast[i32]((bits >> 52) & 0x7ff)
    if exponent == 0 {
        bits = bit_cast[u64](x * float_of_bits(0x43e0_0000_0000_0000))
        exponent = cast[i32]((bits >> 52) & 0x7ff)
        exponent = if exponent != 0 { exponent - 63 } else { 0x800 }
    }
    significand :: ((bits & 0x000f_ffff_ffff_ffff) | 0x0010_0000_0000_0000) << 1
    return significand, exponent - (0x3ff + 52 + 1), sign
}

/**
 * Give 1 when any bit of bits is set, for the bit that says bits shifted out weren't all zero.
 *
 * @param bits The bits.
 * @return 1 if bits isn't 0, 0 if it is.
 */
fused_sticky #no_context :: fn(bits: u64) -> u64 {
    return if bits != 0 { 1 } else { 0 }
}

/**
 * Multiply an f64 by a power of two, rounding once.
 *
 * @param x The number.
 * @param power The power of two, any i32: past the range of f64's exponents, the result overflows to infinity or
 *     underflows to zero, keeping x's sign.
 * @return x × 2^power, rounded to nearest; NaN for NaN, and infinity or zero as given.
 */
//SPEC: musl src/math/scalbn.c
scale_by_power_of_two #no_context :: fn(x: f64, power: i32) -> f64 {
    y := x
    n := power
    if n > 1023 {
        y *= float_of_bits(0x7fe0_0000_0000_0000)
        n -= 1023
        if n > 1023 {
            y *= float_of_bits(0x7fe0_0000_0000_0000)
            n -= 1023
            if n > 1023 {
                n = 1023
            }
        }
    }
    else if n < -1022 {
        // 2^-1022 × 2^53, so the last step's n is below -53 and a subnormal is rounded once
        y *= float_of_bits(0x0360_0000_0000_0000)
        n += 1022 - 53
        if n < -1022 {
            y *= float_of_bits(0x0360_0000_0000_0000)
            n += 1022 - 53
            if n < -1022 {
                n = -1022
            }
        }
    }
    return y * float_of_bits(cast[u64](0x3ff + n) << 52)
}

/**
 * Multiply two f64s and add a third, rounding once, without the instruction.
 *
 * @param x The first factor.
 * @param y The second factor.
 * @param z What's added to the product.
 * @return The f64 nearest x × y + z, ties to even; NaN and infinities as x * y + z gives them.
 */
//SPEC: musl src/math/fma.c
fused_multiply_add_f64 #no_context :: fn(x: f64, y: f64, z: f64) -> f64 {
    x_significand, x_exponent, x_sign :: fused_multiply_split(x)
    y_significand, y_exponent, y_sign :: fused_multiply_split(y)
    z_significand, z_exponent, z_sign :: fused_multiply_split(z)
    if x_exponent >= FUSED_SPECIAL || y_exponent >= FUSED_SPECIAL {
        return x * y + z
    }
    if z_exponent >= FUSED_SPECIAL {
        /*
         * z is 0, so the sum is the product, rounded once, never 0 as x and y aren't: not x * y + z, which gives +0
         * for a product that underflows to -0 (musl does); or z is infinite or NaN
         */
        if z_exponent > FUSED_SPECIAL {
            return x * y
        }
        return z
    }
    // The product, exact in 128 bits: its top 20 or 21 bits and bottom 2 are zero
    product :: cast[u128](x_significand) * cast[u128](y_significand)
    high := cast[u64](product >> 64)
    low := cast[u64](product)
    z_high : u64 = 0
    z_low : u64 = 0
    // Exponents lined up: z shifted up by some, the product down by the rest, bits shifted out kept as a sticky bit
    exponent := x_exponent + y_exponent
    apart := z_exponent - exponent
    if apart > 0 {
        if apart < 64 {
            z_low = z_significand << cast[u32](apart)
            z_high = z_significand >> cast[u32](64 - apart)
        }
        else {
            z_high = z_significand
            exponent = z_exponent - 64
            apart -= 64
            if apart == 0 {
            }
            else if apart < 64 {
                low = high << cast[u32](64 - apart) | low >> cast[u32](apart) | fused_sticky(low << cast[u32](64 - apart))
                high = high >> cast[u32](apart)
            }
            else {
                low = 1
                high = 0
            }
        }
    }
    else {
        apart = 0 - apart
        if apart == 0 {
            z_low = z_significand
        }
        else if apart < 64 {
            z_low = z_significand >> cast[u32](apart) | fused_sticky(z_significand << cast[u32](64 - apart))
        }
        else {
            z_low = 1
        }
    }
    // Added, or taken away and negated if that went below zero
    sign := x_sign != y_sign
    nonzero := true
    if sign == z_sign {
        low += z_low
        high += z_high + (if low < z_low { cast[u64](1) } else { 0 })
    }
    else {
        before :: low
        low -= z_low
        high = high - z_high - (if before < low { cast[u64](1) } else { 0 })
        if (high >> 63) != 0 {
            low = 0 - low
            high = 0 - high - fused_sticky(low)
            sign = !sign
        }
        nonzero = high != 0
    }
    // The top 63 bits of the sum in high, its last bit sticky
    shift : i32 = 0
    if nonzero {
        exponent += 64
        // At least 1, as the sum's top bit is clear
        shift = cast[i32](intrinsics.leading_zeros(high)) - 1
        high = high << cast[u32](shift) | low >> cast[u32](64 - shift) | fused_sticky(low << cast[u32](shift))
    }
    else if low != 0 {
        shift = cast[i32](intrinsics.leading_zeros(low)) - 1
        if shift < 0 {
            high = low >> 1 | (low & 1)
        }
        else {
            high = low << cast[u32](shift)
        }
    }
    else {
        // Exactly zero, whose sign x * y + z gives
        return x * y + z
    }
    exponent -= shift
    // Converted to f64, between 2^62 and 2^63, rounding once
    whole := cast[i64](high)
    if sign {
        whole = 0 - whole
    }
    result := cast[f64](whole)
    if exponent < -1022 - 62 {
        // Subnormal before rounding
        if exponent == -1022 - 63 {
            top := float_of_bits(0x43e0_0000_0000_0000)
            if sign {
                top = -top
            }
            if result == top {
                // Rounded up to the least normal number
                least :: float_of_bits(0x0010_0000_0000_0000)
                return if sign { -least } else { least }
            }
            // A bit is lost when scaled: another top bit added, so the conversion is the one rounding
            if (high << 53) != 0 {
                whole = cast[i64](high >> 1 | (high & 1) | (cast[u64](1) << 62))
                if sign {
                    whole = 0 - whole
                }
                result = cast[f64](whole)
                result = 2 * result - top
            }
        }
        else {
            // Rounded once when scaled: the bits below what a subnormal keeps made sticky
            whole = cast[i64]((high >> 10 | fused_sticky(high << 54)) << 10)
            if sign {
                whole = 0 - whole
            }
            result = cast[f64](whole)
        }
    }
    return scale_by_power_of_two(result, exponent)
}

/**
 * Multiply two f32s and add a third, rounding once, without the instruction: in f64, where the product is exact, and
 * the sum moved off a halfway point between two f32s it isn't exactly on, so rounding it to f32 rounds as the exact sum
 * would.
 *
 * @param x The first factor.
 * @param y The second factor.
 * @param z What's added to the product.
 * @return The f32 nearest x × y + z, ties to even; NaN and infinities as x * y + z gives them.
 */
//SPEC: musl src/math/fmaf.c
fused_multiply_add_f32 #no_context :: fn(x: f32, y: f32, z: f32) -> f32 {
    product :: cast[f64](x) * cast[f64](y)
    wide_z :: cast[f64](z)
    sum :: product + wide_z
    bits := bit_cast[u64](sum)
    // Not halfway between two f32s, or a NaN, or exact: one rounding to f32 is right
    if (bits & 0x1fff_ffff) != 0x1000_0000 || ((bits >> 52) & 0x7ff) == 0x7ff || (sum - product == wide_z && sum - wide_z == product) {
        return cast[f32](sum)
    }
    // Halfway but inexact: a step toward what was lost
    negative :: (bits >> 63) != 0
    lost :: if negative == (wide_z > product) { product - sum + wide_z } else { wide_z - sum + product }
    if negative == (lost < 0) {
        bits += 1
    }
    else {
        bits -= 1
    }
    return cast[f32](bit_cast[f64](bits))
}
