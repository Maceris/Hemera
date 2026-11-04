package runtime

/*
 * Converting between UTF-8, which Hemera's strings hold, and UTF-16, which Windows' functions
 * take, into memory the caller provides. Anything that isn't valid, like a lone surrogate or a
 * stray continuation byte, becomes U+FFFD, the replacement character, so every input converts.
 *
 *     units : u16[256]
 *     count :: runtime.utf8_to_utf16(path, units)   // at most path.count units
 */

/** U+FFFD, the code point that anything invalid converts to. */
REPLACEMENT_CHARACTER : u32 : 0xfffd

/**
 * Compute the most UTF-8 bytes that a number of UTF-16 units can need, to size the bytes given to utf16_to_utf8.
 *
 * @param count How many UTF-16 units, any number from 0.
 * @return The bytes they can need: 3 for each unit, since a pair of surrogates needs 4. It overflows only for a count
 *     no memory could hold.
 */
utf8_capacity_for_utf16 :: fn(count: usize) -> usize {
    return count * 3
}

/**
 * Write a byte at an index if it fits, so a conversion can count what it needs past the end of its buffer.
 *
 * @param bytes Where the byte goes; nothing is written when index is past its end.
 * @param index Where in bytes, which may be past its end.
 * @param byte The byte, as a u32 so callers can compute it from a code point; only its low 8 bits are kept.
 * @return The index after it, index + 1, whether or not the byte fit.
 */
put_byte :: fn(bytes: mut u8[], index: usize, byte: u32) -> usize {
    if index < bytes.count {
        bytes[index] = cast[u8](byte)
    }
    return index + 1
}

/**
 * Write a UTF-16 unit at an index if it fits, so a conversion can count what it needs past the end of its buffer.
 *
 * @param units Where the unit goes; nothing is written when index is past its end.
 * @param index Where in units, which may be past its end.
 * @param unit The unit, as a u32 so callers can compute it from a code point; only its low 16 bits are kept.
 * @return The index after it, index + 1, whether or not the unit fit.
 */
put_unit :: fn(units: mut u16[], index: usize, unit: u32) -> usize {
    if index < units.count {
        units[index] = cast[u16](unit)
    }
    return index + 1
}

/**
 * Write a code point as UTF-8 at an index, as much of it as fits.
 *
 * @param bytes Where its bytes go; those past its end aren't written.
 * @param index Where in bytes the first of them goes, which may be past its end.
 * @param code_point The code point, up to 0x10ffff; it isn't checked, so a surrogate is written as one would be,
 *     and callers give U+FFFD in place of anything invalid.
 * @return The index after its last byte, 1 to 4 past index, whether or not they fit.
 */
put_utf8 :: fn(bytes: mut u8[], index: usize, code_point: u32) -> usize {
    if code_point < 0x80 {
        return put_byte(bytes, index, code_point)
    }
    if code_point < 0x800 {
        next :: put_byte(bytes, index, 0xc0 | (code_point >> 6))
        return put_byte(bytes, next, 0x80 | (code_point & 0x3f))
    }
    if code_point < 0x10000 {
        first :: put_byte(bytes, index, 0xe0 | (code_point >> 12))
        second :: put_byte(bytes, first, 0x80 | ((code_point >> 6) & 0x3f))
        return put_byte(bytes, second, 0x80 | (code_point & 0x3f))
    }
    first :: put_byte(bytes, index, 0xf0 | (code_point >> 18))
    second :: put_byte(bytes, first, 0x80 | ((code_point >> 12) & 0x3f))
    third :: put_byte(bytes, second, 0x80 | ((code_point >> 6) & 0x3f))
    return put_byte(bytes, third, 0x80 | (code_point & 0x3f))
}

/**
 * Convert UTF-16 to UTF-8, into memory the caller provides.
 *
 * A high surrogate followed by a low one is the code point they make; any other surrogate becomes U+FFFD.
 *
 * @param units The UTF-16 to convert, which may be empty.
 * @param bytes Where the UTF-8 goes. Only what fits is written, and a code point can be cut partway through, so a
 *     result larger than its count means the conversion is incomplete; utf8_capacity_for_utf16 is always enough.
 * @return How many bytes the whole conversion takes, which can be more than bytes holds; 0 only for empty units.
 */
utf16_to_utf8 :: fn(units: u16[], bytes: mut u8[]) -> usize {
    written : usize = 0
    index : usize = 0
    loop {
        if index >= units.count {
            break
        }
        unit :: cast[u32](units[index])
        index += 1
        code_point := unit
        if unit >= 0xd800 && unit < 0xdc00 {
            code_point = REPLACEMENT_CHARACTER
            if index < units.count {
                low :: cast[u32](units[index])
                if low >= 0xdc00 && low < 0xe000 {
                    code_point = 0x10000 + ((unit - 0xd800) << 10) + (low - 0xdc00)
                    index += 1
                }
            }
        }
        else if unit >= 0xdc00 && unit < 0xe000 {
            code_point = REPLACEMENT_CHARACTER
        }
        written = put_utf8(bytes, written, code_point)
    }
    return written
}

/**
 * Convert UTF-8 to UTF-16, into memory the caller provides.
 *
 * A byte that can't start a sequence, a sequence cut short by a byte that doesn't continue it or by the end, an
 * overlong form, a surrogate, and anything above U+10FFFF each become one U+FFFD.
 *
 * @param text The UTF-8 to convert, which may be empty and needn't be valid.
 * @param units Where the UTF-16 goes. Only what fits is written, and a surrogate pair can be cut in half, so a result
 *     larger than its count means the conversion is incomplete; text.count units are always enough.
 * @return How many units the whole conversion takes, never more than text.count, and 0 only for empty text.
 */
utf8_to_utf16 :: fn(text: string, units: mut u16[]) -> usize {
    written : usize = 0
    index : usize = 0
    loop {
        if index >= text.count {
            break
        }
        lead :: cast[u32](text[index])
        index += 1
        // How many continuation bytes follow, and the smallest code point that needs them
        extra : usize = 0
        minimum : u32 = 0
        code_point := lead
        if lead >= 0xc2 && lead < 0xe0 {
            extra = 1
            minimum = 0x80
            code_point = lead & 0x1f
        }
        else if lead >= 0xe0 && lead < 0xf0 {
            extra = 2
            minimum = 0x800
            code_point = lead & 0x0f
        }
        else if lead >= 0xf0 && lead < 0xf5 {
            extra = 3
            minimum = 0x10000
            code_point = lead & 0x07
        }
        else if lead >= 0x80 {
            code_point = REPLACEMENT_CHARACTER
        }
        for i in 0..<extra {
            if index >= text.count {
                code_point = REPLACEMENT_CHARACTER
                break
            }
            continuation :: cast[u32](text[index])
            if continuation & 0xc0 != 0x80 {
                code_point = REPLACEMENT_CHARACTER
                break
            }
            code_point = (code_point << 6) | (continuation & 0x3f)
            index += 1
        }
        if extra > 0 && code_point != REPLACEMENT_CHARACTER
            && (code_point < minimum || code_point > 0x10ffff || (code_point >= 0xd800 && code_point < 0xe000)) {
            code_point = REPLACEMENT_CHARACTER
        }
        if code_point >= 0x10000 {
            high :: put_unit(units, written, 0xd800 + ((code_point - 0x10000) >> 10))
            written = put_unit(units, high, 0xdc00 + ((code_point - 0x10000) & 0x3ff))
        }
        else {
            written = put_unit(units, written, code_point)
        }
    }
    return written
}
