package math

import intrinsics from "base"

/*
 * Decimal text to floats, correctly rounded: to nearest, ties to even, as IEEE 754 says. Three ways, the first that's
 * sure: Clinger's, where the digits and the power of ten are both exact in the float; Eisel and Lemire's, multiplying
 * by a power of ten in 128 bits, which settles nearly every other number; and an exact one for the rest, shifting a
 * decimal by powers of two, as Go's strconv does.
 */

/** 10^0 to 10^22, which f64 holds exactly. */
EXACT_POWERS_OF_TEN :: f64.[1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16,
    1e17, 1e18, 1e19, 1e20, 1e21, 1e22]

/** What scan_decimal read: up to 19 significant digits, and the power of ten they're scaled by. */
ScannedDecimal :: struct {
    /** The first 19 significant digits, as a whole number. */
    mantissa : u64,
    /** The power of ten the mantissa is scaled by. */
    exponent : i32,
    negative : bool,
    /** Whether a nonzero digit came after the 19th, so the mantissa is short of the number. */
    truncated : bool,
}

/**
 * Read a decimal number: an optional sign, digits with an optional point, at least one digit, and an optional exponent,
 * e or E, an optional sign and digits. Nothing else, and nothing after it.
 *
 * @param text The text.
 * @return What it says, or none if it isn't such a number.
 */
//SPEC: Go src/strconv/atof.go readFloat
scan_decimal :: fn(text: string) -> ScannedDecimal? {
    scanned : ScannedDecimal
    at : usize = 0
    if at < text.count && (text[at] == '+' || text[at] == '-') {
        scanned.negative = text[at] == '-'
        at += 1
    }
    saw_point := false
    saw_digits := false
    // Significant digits, those in the mantissa, and where the point is
    digits : i32 = 0
    mantissa_digits : i32 = 0
    point : i32 = 0
    loop {
        if at >= text.count {
            break
        }
        c :: text[at]
        if c == '.' {
            if saw_point {
                return null
            }
            saw_point = true
            point = digits
            at += 1
            continue
        }
        if c < '0' || c > '9' {
            break
        }
        saw_digits = true
        at += 1
        // Leading zeros only move the point
        if c == '0' && digits == 0 {
            point -= 1
            continue
        }
        digits += 1
        if mantissa_digits < 19 {
            scanned.mantissa = scanned.mantissa * 10 + cast[u64](cast[u8](c) - cast[u8]('0'))
            mantissa_digits += 1
        }
        else if c != '0' {
            scanned.truncated = true
        }
    }
    if !saw_digits {
        return null
    }
    if !saw_point {
        point = digits
    }
    if at < text.count && (text[at] == 'e' || text[at] == 'E') {
        at += 1
        sign : i32 = 1
        if at < text.count && (text[at] == '+' || text[at] == '-') {
            if text[at] == '-' {
                sign = -1
            }
            at += 1
        }
        if at >= text.count || text[at] < '0' || text[at] > '9' {
            return null
        }
        e : i32 = 0
        loop {
            if at >= text.count || text[at] < '0' || text[at] > '9' {
                break
            }
            // Past 10000, the number is 0 or infinite whatever its digits
            if e < 10000 {
                e = e * 10 + cast[i32](cast[u8](text[at]) - cast[u8]('0'))
            }
            at += 1
        }
        point += e * sign
    }
    if at != text.count {
        return null
    }
    if scanned.mantissa != 0 {
        scanned.exponent = point - mantissa_digits
    }
    return scanned
}

/**
 * Tell whether text is infinity or NaN, in any case: inf, infinity or nan, with an optional sign.
 *
 * @param text The text.
 * @return 1 for infinity, -1 for -infinity, 2 for NaN; 0 if it's neither.
 */
special_text :: fn(text: string) -> i32 {
    at : usize = 0
    negative := false
    if at < text.count && (text[at] == '+' || text[at] == '-') {
        negative = text[at] == '-'
        at += 1
    }
    rest :: text[at..<text.count]
    if equal_ignoring_case(rest, "inf") || equal_ignoring_case(rest, "infinity") {
        return if negative { -1 } else { 1 }
    }
    if equal_ignoring_case(rest, "nan") {
        return 2
    }
    return 0
}

/**
 * Tell whether ASCII text is a lowercase word, ignoring the text's case.
 *
 * @param text The text.
 * @param word The word, in lowercase.
 * @return True if they're the same but for case.
 */
equal_ignoring_case :: fn(text: string, word: string) -> bool {
    if text.count != word.count {
        return false
    }
    for c, i in text {
        lower :: if c >= 'A' && c <= 'Z' { cast[char](cast[u8](c) + 32) } else { c }
        if lower != word[i] {
            return false
        }
    }
    return true
}

/**
 * mantissa × 10^exponent rounded to f64, Eisel and Lemire's way: the mantissa times a 128-bit power of ten, which says
 * the result, unless it's too near a halfway point to tell.
 *
 * @param mantissa The digits, not 0.
 * @param exponent The power of ten.
 * @param negative Whether it's negative.
 * @return The f64's bits; none if it can't be told this way, or it's subnormal or overflows.
 */
//SPEC: Go src/strconv/eisel_lemire.go eiselLemire64, after Lemire's "Number Parsing at a Gigabyte per Second" (2021)
eisel_lemire_64 :: fn(mantissa: u64, exponent: i32, negative: bool) -> u64? {
    return eisel_lemire(mantissa, exponent, negative, 52, 1023)
}

/**
 * The same as eisel_lemire_64, for f32.
 *
 * @param mantissa The digits, not 0.
 * @param exponent The power of ten.
 * @param negative Whether it's negative.
 * @return The f32's bits, in the low 32; none if it can't be told this way, or it's subnormal or overflows.
 */
//SPEC: Go src/strconv/eisel_lemire.go eiselLemire32
eisel_lemire_32 :: fn(mantissa: u64, exponent: i32, negative: bool) -> u64? {
    return eisel_lemire(mantissa, exponent, negative, 23, 127)
}

/**
 * Eisel and Lemire's rounding, for a float with fraction_bits bits of fraction and an exponent bias.
 *
 * @param mantissa_in The digits, not 0.
 * @param exponent The power of ten.
 * @param negative Whether it's negative.
 * @param fraction_bits 52 for f64, 23 for f32.
 * @param bias 1023 for f64, 127 for f32.
 * @return The float's bits, or none.
 */
eisel_lemire :: fn(mantissa_in: u64, exponent: i32, negative: bool, fraction_bits: u32, bias: i64) -> u64? {
    if exponent < POWERS_OF_TEN_LOWEST || exponent > POWERS_OF_TEN_HIGHEST {
        return null
    }
    index :: cast[usize](exponent - POWERS_OF_TEN_LOWEST) * 2
    if index + 1 >= POWERS_OF_TEN.count {
        return null
    }
    // Normalized, so its top bit is set
    zeros :: intrinsics.leading_zeros(mantissa_in)
    mantissa :: mantissa_in << zeros
    // floor(log2(10) × exponent) + 64 + bias, less the shift
    exponent_bits :: (217706 * cast[i64](exponent)) >> 16
    result_exponent := cast[u64](exponent_bits + 64 + bias) - zeros
    product := cast[u128](mantissa) * cast[u128](POWERS_OF_TEN[index])
    high := cast[u64](product >> 64)
    low := cast[u64](product)
    // What the bits below the result's are, which must not be all ones to know it rounds as it looks
    below_bits :: 61 - fraction_bits
    below_mask :: (cast[u64](1) << below_bits) - 1
    if (high & below_mask) == below_mask && low + mantissa < mantissa {
        // The power's lower 64 bits too
        lower := cast[u128](mantissa) * cast[u128](POWERS_OF_TEN[index + 1])
        lower_high :: cast[u64](lower >> 64)
        lower_low :: cast[u64](lower)
        merged_high := high
        merged_low :: low + lower_high
        if merged_low < low {
            merged_high += 1
        }
        if (merged_high & below_mask) == below_mask && merged_low + 1 == 0 && lower_low + mantissa < mantissa {
            return null
        }
        high = merged_high
        low = merged_low
    }
    // To fraction_bits + 2 bits
    top :: high >> 63
    result_mantissa := high >> (top + cast[u64](below_bits))
    result_exponent -= 1 ~ top
    // Exactly halfway: can't be told
    if low == 0 && (high & below_mask) == 0 && (result_mantissa & 3) == 1 {
        return null
    }
    // Rounded to fraction_bits + 1, ties to even
    result_mantissa += result_mantissa & 1
    result_mantissa >>= 1
    if (result_mantissa >> (fraction_bits + 1)) > 0 {
        result_mantissa >>= 1
        result_exponent += 1
    }
    // Subnormal or past the largest
    exponent_limit :: (cast[u64](1) << (if fraction_bits == 52 { cast[u32](11) } else { cast[u32](8) })) - 1
    if result_exponent - 1 >= exponent_limit - 1 {
        return null
    }
    bits := (result_exponent << fraction_bits) | (result_mantissa & ((cast[u64](1) << fraction_bits) - 1))
    if negative {
        exponent_width :: if fraction_bits == 52 { cast[u32](11) } else { cast[u32](8) }
        bits |= cast[u64](1) << (fraction_bits + exponent_width)
    }
    return bits
}

/** How many digits the exact path keeps: past them, a digit only says the number's a little more. */
DECIMAL_DIGITS :: 800

/** A decimal number for the exact path: digits, most significant first, and where the point is among them. */
SlowDecimal :: struct {
    /** The digits' values, 0 to 9. */
    digits : u8[DECIMAL_DIGITS],
    /** How many there are. */
    count : i32,
    /** Where the point is: the number is 0.d1d2d3... × 10^point. */
    point : i32,
    negative : bool,
    /** Whether nonzero digits were dropped past DECIMAL_DIGITS. */
    truncated : bool,
}

/**
 * Give one of a decimal's digits.
 *
 * @param decimal The decimal.
 * @param index Which, from 0; past the digits, 0.
 * @return Its value, 0 to 9.
 */
digit_of :: fn(decimal: ptr[SlowDecimal], index: i32) -> u64 {
    if index < 0 || index >= decimal.count || cast[usize](index) >= decimal.digits.count {
        return 0
    }
    return cast[u64](decimal.digits[cast[usize](index)])
}

/**
 * Set one of a decimal's digits.
 *
 * @param decimal The decimal.
 * @param index Which, from 0; outside the room for them, nothing's set.
 * @param value Its value, 0 to 9.
 */
set_digit :: fn(decimal: ptr[mut SlowDecimal], index: i32, value: u64) {
    if index >= 0 && cast[usize](index) < decimal.digits.count {
        decimal.digits[cast[usize](index)] = cast[u8](value)
    }
}

/**
 * Drop a decimal's trailing zeros.
 *
 * @param decimal The decimal.
 */
trim_decimal :: fn(decimal: ptr[mut SlowDecimal]) {
    loop {
        if decimal.count <= 0 || digit_of(decimal, decimal.count - 1) != 0 {
            break
        }
        decimal.count -= 1
    }
    if decimal.count == 0 {
        decimal.point = 0
    }
}

/**
 * Read text scan_decimal has said is a decimal number into a SlowDecimal.
 *
 * @param decimal Where it goes.
 * @param text The text.
 */
//SPEC: Go src/strconv/atof.go decimal.set
set_decimal :: fn(decimal: ptr[mut SlowDecimal], text: string) {
    decimal.count = 0
    decimal.point = 0
    decimal.negative = false
    decimal.truncated = false
    at : usize = 0
    if at < text.count && (text[at] == '+' || text[at] == '-') {
        decimal.negative = text[at] == '-'
        at += 1
    }
    saw_point := false
    loop {
        if at >= text.count {
            break
        }
        c :: text[at]
        if c == '.' {
            saw_point = true
            decimal.point = decimal.count
            at += 1
            continue
        }
        if c < '0' || c > '9' {
            break
        }
        at += 1
        if c == '0' && decimal.count == 0 {
            decimal.point -= 1
            continue
        }
        if decimal.count < DECIMAL_DIGITS {
            set_digit(decimal, decimal.count, cast[u64](cast[u8](c) - cast[u8]('0')))
            decimal.count += 1
        }
        else if c != '0' {
            decimal.truncated = true
        }
    }
    if !saw_point {
        decimal.point = decimal.count
    }
    if at < text.count && (text[at] == 'e' || text[at] == 'E') {
        at += 1
        sign : i32 = 1
        if at < text.count && (text[at] == '+' || text[at] == '-') {
            if text[at] == '-' {
                sign = -1
            }
            at += 1
        }
        e : i32 = 0
        loop {
            if at >= text.count || text[at] < '0' || text[at] > '9' {
                break
            }
            if e < 10000 {
                e = e * 10 + cast[i32](cast[u8](text[at]) - cast[u8]('0'))
            }
            at += 1
        }
        decimal.point += e * sign
    }
    trim_decimal(decimal)
}

/**
 * Divide a decimal by 2^k, keeping DECIMAL_DIGITS digits.
 *
 * @param decimal The decimal.
 * @param k The power, 1 to 60.
 */
//SPEC: Go src/strconv/decimal.go rightShift
shift_decimal_right :: fn(decimal: ptr[mut SlowDecimal], k: u32) {
    read : i32 = 0
    written : i32 = 0
    n : u64 = 0
    // Enough leading digits to have something to shift
    loop {
        if (n >> k) != 0 {
            break
        }
        if read >= decimal.count {
            if n == 0 {
                decimal.count = 0
                return void
            }
            loop {
                if (n >> k) != 0 {
                    break
                }
                n *= 10
                read += 1
            }
            break
        }
        n = n * 10 + digit_of(decimal, read)
        read += 1
    }
    decimal.point -= read - 1
    mask :: (cast[u64](1) << k) - 1
    loop {
        if read >= decimal.count {
            break
        }
        c :: digit_of(decimal, read)
        set_digit(decimal, written, n >> k)
        written += 1
        n = (n & mask) * 10 + c
        read += 1
    }
    loop {
        if n == 0 {
            break
        }
        digit :: n >> k
        n &= mask
        if written < DECIMAL_DIGITS {
            set_digit(decimal, written, digit)
            written += 1
        }
        else if digit > 0 {
            decimal.truncated = true
        }
        n *= 10
    }
    decimal.count = written
    trim_decimal(decimal)
}

/**
 * Multiply a decimal by 2^k, keeping DECIMAL_DIGITS digits.
 *
 * @param decimal The decimal.
 * @param k The power, 1 to 60.
 */
shift_decimal_left :: fn(decimal: ptr[mut SlowDecimal], k: u32) {
    // The product's digits, least significant first: at most 19 more than there were
    product : u8[DECIMAL_DIGITS + 20]
    made : i32 = 0
    carry : u64 = 0
    read := decimal.count - 1
    loop {
        if read < 0 {
            break
        }
        n :: (digit_of(decimal, read) << k) + carry
        at :: cast[usize](made)
        if at < product.count {
            product[at] = cast[u8](n % 10)
        }
        made += 1
        carry = n / 10
        read -= 1
    }
    loop {
        if carry == 0 {
            break
        }
        at :: cast[usize](made)
        if at < product.count {
            product[at] = cast[u8](carry % 10)
        }
        made += 1
        carry /= 10
    }
    decimal.point += made - decimal.count
    // Back, most significant first, as many as fit
    kept :: if made < DECIMAL_DIGITS { made } else { DECIMAL_DIGITS }
    for i in 0..<made {
        from :: made - 1 - i
        digit :: if from >= 0 && cast[usize](from) < product.count { cast[u64](product[cast[usize](from)]) } else { 0 }
        if i < kept {
            set_digit(decimal, i, digit)
        }
        else if digit != 0 {
            decimal.truncated = true
        }
    }
    decimal.count = kept
    trim_decimal(decimal)
}

/**
 * Multiply or divide a decimal by a power of two.
 *
 * @param decimal The decimal.
 * @param k The power: positive multiplies, negative divides.
 */
shift_decimal :: fn(decimal: ptr[mut SlowDecimal], k: i32) {
    if decimal.count == 0 {
        return void
    }
    by := k
    loop {
        if by <= 60 {
            break
        }
        shift_decimal_left(decimal, 60)
        by -= 60
    }
    loop {
        if by >= -60 {
            break
        }
        shift_decimal_right(decimal, 60)
        by += 60
    }
    if by > 0 {
        shift_decimal_left(decimal, cast[u32](by))
    }
    else if by < 0 {
        shift_decimal_right(decimal, cast[u32](-by))
    }
}

/**
 * Give a decimal's whole part, rounded to nearest, ties to even, as Go's RoundedInteger does.
 *
 * @param decimal The decimal, below 2^64.
 * @return The whole number.
 */
//SPEC: Go src/strconv/decimal.go RoundedInteger and shouldRoundUp
rounded_whole :: fn(decimal: ptr[SlowDecimal]) -> u64 {
    if decimal.point > 20 {
        return 0xffff_ffff_ffff_ffff
    }
    n : u64 = 0
    i : i32 = 0
    loop {
        if i >= decimal.point || i >= decimal.count {
            break
        }
        n = n * 10 + digit_of(decimal, i)
        i += 1
    }
    loop {
        if i >= decimal.point {
            break
        }
        n *= 10
        i += 1
    }
    at :: decimal.point
    if at >= 0 && at < decimal.count {
        if digit_of(decimal, at) == 5 && at + 1 == decimal.count {
            // Exactly half, unless digits were dropped past it
            if decimal.truncated || (at > 0 && (digit_of(decimal, at - 1) % 2) != 0) {
                n += 1
            }
        }
        else if digit_of(decimal, at) >= 5 {
            n += 1
        }
    }
    return n
}

/** How far to shift a decimal by, by how many digits its point is from where it should be. */
SHIFTS_BY_DIGITS :: i32.[1, 3, 6, 9, 13, 16, 19, 23, 26]

/**
 * Round a decimal to a float's bits, exactly.
 *
 * @param decimal The decimal; it's changed.
 * @param fraction_bits 52 for f64, 23 for f32.
 * @param exponent_bits 11 for f64, 8 for f32.
 * @param bias -1023 for f64, -127 for f32.
 * @return The float's bits, in the low 32 for f32: infinity's where it overflows.
 */
//SPEC: Go src/strconv/atof.go decimal.floatBits
decimal_to_bits :: fn(decimal: ptr[mut SlowDecimal], fraction_bits: u32, exponent_bits: u32, bias: i32) -> u64 {
    mantissa : u64 = 0
    exponent : i32 = 0
    infinite :: (cast[i32](1) << exponent_bits) - 1 + bias
    if decimal.count == 0 || decimal.point < -330 {
        exponent = bias
    }
    else if decimal.point > 310 {
        exponent = infinite
    }
    else {
        // Into [0.5, 1)
        loop {
            if decimal.point <= 0 {
                break
            }
            n : i32 = if decimal.point >= 9 { 27 } else { SHIFTS_BY_DIGITS[cast[usize](decimal.point) % 9] }
            shift_decimal(decimal, -n)
            exponent += n
        }
        loop {
            if !(decimal.point < 0 || (decimal.point == 0 && digit_of(decimal, 0) < 5)) {
                break
            }
            n : i32 = if -decimal.point >= 9 { 27 } else { SHIFTS_BY_DIGITS[cast[usize](-decimal.point) % 9] }
            shift_decimal(decimal, n)
            exponent -= n
        }
        // [0.5, 1) to a float's [1, 2)
        exponent -= 1
        // Below the least exponent: subnormal, shifted to it
        if exponent < bias + 1 {
            n :: bias + 1 - exponent
            shift_decimal(decimal, -n)
            exponent += n
        }
        if exponent - bias >= (cast[i32](1) << exponent_bits) - 1 {
            exponent = infinite
        }
        else {
            shift_decimal(decimal, cast[i32](1 + fraction_bits))
            mantissa = rounded_whole(decimal)
            // Rounding up may have carried into another bit
            if mantissa == cast[u64](2) << fraction_bits {
                mantissa >>= 1
                exponent += 1
            }
            if exponent - bias >= (cast[i32](1) << exponent_bits) - 1 {
                exponent = infinite
                mantissa = 0
            }
            else if (mantissa & (cast[u64](1) << fraction_bits)) == 0 {
                exponent = bias
            }
        }
    }
    if exponent == infinite {
        mantissa = 0
    }
    bits := mantissa & ((cast[u64](1) << fraction_bits) - 1)
    bits |= cast[u64]((exponent - bias) & ((cast[i32](1) << exponent_bits) - 1)) << fraction_bits
    if decimal.negative {
        bits |= cast[u64](1) << (fraction_bits + exponent_bits)
    }
    return bits
}

/**
 * Read an f64 from decimal text, correctly rounded.
 *
 * @param text The text: an optional sign, digits with an optional point, and an optional exponent, e or E and an
 *     optionally signed whole number, like "-12.5e3"; or inf, infinity or nan, in any case, with an optional sign.
 * @return The f64 nearest the number, ties to even: ±infinity past the largest, ±0 below the least subnormal's half;
 *     none if the text isn't such a number, with nothing before or after it.
 */
parse_64 :: fn(text: string) -> f64? {
    special :: special_text(text)
    if special == 1 {
        return infinity_64()
    }
    if special == -1 {
        return -infinity_64()
    }
    if special == 2 {
        return nan_64()
    }
    scanned :: scan_decimal(text) or_return null
    if scanned.mantissa == 0 {
        return if scanned.negative { -0.0 } else { 0.0 }
    }
    if !scanned.truncated {
        // Clinger's: the mantissa and the power both exact, so one operation rounds once
        if (scanned.mantissa >> 53) == 0 {
            f := cast[f64](scanned.mantissa)
            if scanned.negative {
                f = -f
            }
            e := scanned.exponent
            if e == 0 {
                return f
            }
            if e > 0 && e <= 15 + 22 {
                // Some of the power into the mantissa first, while it stays exact
                if e > 22 {
                    f *= EXACT_POWERS_OF_TEN[cast[usize](e - 22) & 15]
                    e = 22
                }
                if f <= 1e15 && f >= -1e15 {
                    return f * EXACT_POWERS_OF_TEN[cast[usize](e) % 23]
                }
            }
            else if e < 0 && e >= -22 {
                return f / EXACT_POWERS_OF_TEN[cast[usize](-e) % 23]
            }
        }
        bits :: eisel_lemire_64(scanned.mantissa, scanned.exponent, scanned.negative)
        if bits is_some {
            return bit_cast[f64](bits or_else 0)
        }
    }
    else {
        // The mantissa is short of the number: if it and one more round the same, so does the number
        low :: eisel_lemire_64(scanned.mantissa, scanned.exponent, scanned.negative)
        high :: eisel_lemire_64(scanned.mantissa + 1, scanned.exponent, scanned.negative)
        if (low is_some) && low == high {
            return bit_cast[f64](low or_else 0)
        }
    }
    decimal : SlowDecimal
    set_decimal(&decimal, text)
    return bit_cast[f64](decimal_to_bits(&decimal, 52, 11, -1023))
}

/** 10^0 to 10^10, which f32 holds exactly. */
EXACT_POWERS_OF_TEN_32 :: f32.[1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10]

/**
 * Read an f32 from decimal text, correctly rounded: rounded once, to f32, not through f64.
 *
 * @param text The text, as parse_64 takes it.
 * @return The f32 nearest the number, ties to even: ±infinity past the largest, ±0 below the least subnormal's half;
 *     none if the text isn't such a number.
 */
parse_32 :: fn(text: string) -> f32? {
    special :: special_text(text)
    if special == 1 {
        return bit_cast[f32](cast[u32](0x7f80_0000))
    }
    if special == -1 {
        return bit_cast[f32](cast[u32](0xff80_0000))
    }
    if special == 2 {
        return bit_cast[f32](cast[u32](0x7fc0_0000))
    }
    scanned :: scan_decimal(text) or_return null
    if scanned.mantissa == 0 {
        return bit_cast[f32](if scanned.negative { cast[u32](0x8000_0000) } else { cast[u32](0) })
    }
    if !scanned.truncated {
        if (scanned.mantissa >> 24) == 0 {
            f := cast[f32](scanned.mantissa)
            if scanned.negative {
                f = -f
            }
            e := scanned.exponent
            if e == 0 {
                return f
            }
            if e > 0 && e <= 7 + 10 {
                if e > 10 {
                    f *= EXACT_POWERS_OF_TEN_32[cast[usize](e - 10) & 7]
                    e = 10
                }
                if f <= 1e7 && f >= -1e7 {
                    return f * EXACT_POWERS_OF_TEN_32[cast[usize](e) % 11]
                }
            }
            else if e < 0 && e >= -10 {
                return f / EXACT_POWERS_OF_TEN_32[cast[usize](-e) % 11]
            }
        }
        bits :: eisel_lemire_32(scanned.mantissa, scanned.exponent, scanned.negative)
        if bits is_some {
            return bit_cast[f32](cast[u32](bits or_else 0))
        }
    }
    else {
        low :: eisel_lemire_32(scanned.mantissa, scanned.exponent, scanned.negative)
        high :: eisel_lemire_32(scanned.mantissa + 1, scanned.exponent, scanned.negative)
        if (low is_some) && low == high {
            return bit_cast[f32](cast[u32](low or_else 0))
        }
    }
    decimal : SlowDecimal
    set_decimal(&decimal, text)
    return bit_cast[f32](cast[u32](decimal_to_bits(&decimal, 23, 8, -127)))
}
