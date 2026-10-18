package strings

/*
 * Numbers and booleans from text: the whole text, with no spaces (trim them first), or none if
 * it isn't one or doesn't fit.
 *
 *     strings.parse_unsigned("ff", 16)   // 255
 *     strings.parse_signed("-12")        // -12
 *     strings.parse_bool("true")         // true
 */

// The value of a digit in base (2 to 36, with letters either case past 9), or none.
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

MAX_U64 : u64 : 0xffff_ffff_ffff_ffff

// Digits in base (2 to 36), with no sign.
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

// Digits in base (2 to 36), after a - or + if there is one.
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

// "true" or "false".
parse_bool :: fn(text: string) -> bool? {
    if equal(text, "true") {
        return true
    }
    if equal(text, "false") {
        return false
    }
    return null
}
