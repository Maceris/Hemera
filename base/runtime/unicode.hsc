package runtime

/*
 * Converting between UTF-8, which Hemera's strings hold, and UTF-16, which Windows' functions
 * take, into memory the caller provides. Anything that isn't valid, like a lone surrogate or a
 * stray continuation byte, becomes U+FFFD, the replacement character, so every input converts.
 *
 *     units : u16[256]
 *     count :: runtime.utf8_to_utf16(path, units)   // at most path.count units
 */

REPLACEMENT_CHARACTER : u32 : 0xfffd

// The most UTF-8 bytes count UTF-16 units can need: 3 each, since a pair of surrogates needs 4.
utf8_capacity_for_utf16 :: fn(count: usize) -> usize {
    return count * 3
}

// Writes byte at index if it fits, and gives back the next index.
put_byte :: fn(bytes: mut u8[], index: usize, byte: u32) -> usize {
    if index < bytes.count {
        bytes[index] = cast[u8](byte)
    }
    return index + 1
}

put_unit :: fn(units: mut u16[], index: usize, unit: u32) -> usize {
    if index < units.count {
        units[index] = cast[u16](unit)
    }
    return index + 1
}

// code_point as UTF-8 at index, giving back the index after it.
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

/*
 * units as UTF-8 in bytes, giving back how many bytes it takes, which can be more than bytes holds
 * (utf8_capacity_for_utf16 is always enough): only what fits is written.
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

/*
 * text as UTF-16 in units, giving back how many units it takes, which is never more than
 * text.count: only what fits is written.
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
