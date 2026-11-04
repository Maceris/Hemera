package strings

/*
 * Numbers and booleans from text: the whole text, with no spaces (trim them first), or none if
 * it isn't one or doesn't fit.
 *
 *     strings.parse_unsigned("ff", 16)   // 255
 *     strings.parse_signed("-12")        // -12
 *     strings.parse_bool("true")         // true
 */

/**
 * Find the value of a digit in a base.
 *
 * @param character The digit: 0 to 9, then letters, either case, for 10 to 35.
 * @param base The base, 2 to 36; a larger one accepts no more than 36 does.
 * @return The digit's value, below base; null if it isn't a digit, or isn't one in base.
 */
digit_value :: fn(character: char, base: u64) -> u64? {
    value : u64 = 36
    if character >= '0' && character <= '9' {
        value = cast[u64](character) - cast[u64]('0')
    }
    else if character >= 'a' && character <= 'z' {
        value = cast[u64](character) - cast[u64]('a') + 10
    }
    else if character >= 'A' && character <= 'Z' {
        value = cast[u64](character) - cast[u64]('A') + 10
    }
    if value >= base {
        return null
    }
    return value
}

/** The largest u64, which parse_unsigned checks against so a value that doesn't fit is none rather than wrapped. */
MAX_U64 : u64 : 0xffff_ffff_ffff_ffff

/**
 * Parse an unsigned integer: digits in a base, with no sign.
 *
 * @param text The whole text, all digits: no sign, spaces, prefix like 0x, or separators like _.
 * @param base The base, 2 to 36; 16 takes digits 0 to 9 and a to f, either case.
 * @return The value; null if text is empty, has anything but digits of base, is larger than MAX_U64, or base is
 *     outside 2 to 36.
 */
parse_unsigned :: fn(text: string, base: u64 = 10) -> u64? {
    if text.count == 0 || base < 2 || base > 36 {
        return null
    }
    result : u64 = 0
    for character in text {
        match digit_value(character, base) {
            case Some(digit) => {
                if result > (MAX_U64 - digit) / base {
                    return null
                }
                result = result * base + digit
            }
            case None => return null
        }
    }
    return result
}

/**
 * Parse a signed integer: digits in a base, after a - or + if there is one.
 *
 * @param text The whole text: an optional - or +, then digits, with no spaces or prefix.
 * @param base The base, 2 to 36.
 * @return The value, from the most negative i64 to the largest; null if text has no digits, anything but digits of
 *     base after the sign, a value that doesn't fit an i64, or base is outside 2 to 36.
 */
parse_signed :: fn(text: string, base: u64 = 10) -> i64? {
    negative :: starts_with(text, "-")
    digits := text
    if negative || starts_with(text, "+") {
        digits = slice(text, 1, text.count)
    }
    match parse_unsigned(digits, base) {
        case Some(magnitude) => {
            // Up to 2^63 when negative, for the most negative value
            limit : u64 = 0x7fff_ffff_ffff_ffff
            if negative {
                if magnitude > limit + 1 {
                    return null
                }
                return cast[i64](0 - magnitude)
            }
            if magnitude > limit {
                return null
            }
            return cast[i64](magnitude)
        }
        case None => return null
    }
}

/**
 * Parse a boolean.
 *
 * @param text The whole text, which must be "true" or "false" exactly: lowercase, no spaces.
 * @return true or false; null for any other text.
 */
parse_bool :: fn(text: string) -> bool? {
    if equal(text, "true") {
        return true
    }
    if equal(text, "false") {
        return false
    }
    return null
}
