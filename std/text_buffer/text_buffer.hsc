package text_buffer

import runtime from "base"

/**
 * Text built up in bytes the caller provides. Appending past the end keeps what fits and sets
 * truncated, so a message that's too long is cut short rather than lost.
 *
 *     storage : u8[128]
 *     text := make(storage)
 *     append(&text, "free pages: ")
 *     append_unsigned(&text, count)
 *     log_info(as_string(&text))
 *
 * It's #scoped, since its bytes are usually a buffer on the stack: it's passed by pointer, and can't
 * be kept on the heap (docs/memory.md, Scoped Structs).
 */
TextBuffer :: struct #scoped {
    /** The caller's bytes the text is built in; never more than these are written. */
    bytes : mut u8[],
    /** How many of bytes hold text, from 0 to bytes.count. */
    count : usize,
    /** Whether something appended didn't fit, so the text is cut short; only clear resets it. */
    truncated : bool,
}

/** The digits append_unsigned writes, for bases up to 16, lowercase. */
DIGITS :: "0123456789abcdef"

/**
 * Make an empty text buffer over the caller's bytes.
 *
 * @param bytes Where the text goes, which the buffer borrows: they have to outlast it, and what they held is
 *     overwritten as text is appended. Empty gives a buffer where everything appended is truncated.
 * @return The buffer, empty and not truncated.
 */
make :: fn(bytes: mut u8[]) -> TextBuffer {
    return TextBuffer.{bytes = bytes, count = 0, truncated = false}
}

/**
 * Give what's been appended so far.
 *
 * @param text The buffer.
 * @return The text, a view of the buffer's bytes, not a copy: what's appended or cleared after changes what it holds.
 *     It's cut wherever it ran out of room, which can be in the middle of a UTF-8 character.
 */
as_string :: fn(text: ptr[TextBuffer]) -> string {
    if text.count == 0 || text.bytes.count == 0 {
        return ""
    }
    return string_of(&text.bytes[0], text.count)
}

/**
 * Empty a buffer, to build another text in the same bytes.
 *
 * @param text The buffer, left empty and not truncated; its bytes aren't zeroed.
 */
clear :: fn(text: ptr[mut TextBuffer]) {
    text.count = 0
    text.truncated = false
}

/**
 * Append one byte, if there's room.
 *
 * @param text The buffer. When it's full, the byte is dropped and truncated is set.
 * @param byte The byte.
 */
append_byte :: fn(text: ptr[mut TextBuffer], byte: u8) {
    if text.count >= text.bytes.count {
        text.truncated = true
        return void
    }
    text.bytes[text.count] = byte
    text.count += 1
}

/**
 * Append text, as much of it as fits.
 *
 * @param text The buffer. If it fills, the bytes that fit are kept, the rest dropped, and truncated set.
 * @param value The text, copied byte by byte.
 */
append :: fn(text: ptr[mut TextBuffer], value: string) {
    for character in value {
        append_byte(text, cast[u8](character))
    }
}

/**
 * Append an unsigned number's digits, as many as fit.
 *
 * @param text The buffer. If it fills, the digits that fit are kept, the rest dropped, and truncated set.
 * @param value The number.
 * @param base The base, from 2 to 16; digits past 9 are lowercase, with no prefix. Any other base calls
 *     context.assertion_handler.
 * @param minimum_digits The fewest digits written, padded with leading zeros; at most 64 are ever written. At least
 *     one is always written, so 0 is "0" even with 0 here.
 */
append_unsigned :: fn(text: ptr[mut TextBuffer], value: u64, base: u64 = 10, minimum_digits: usize = 1) {
    runtime.assert(base >= 2 && base <= 16, "append_unsigned takes a base from 2 to 16")
    // The digits come out lowest first, so they're collected backwards, from the end
    digits : u8[64]
    start : usize = digits.count
    with {
        rest := value
    }
    loop {
        start -= 1
        digits[start] = cast[u8](DIGITS[rest % base])
        rest /= base
    }
    while (rest != 0 || digits.count - start < minimum_digits) && start > 0
    for i in start..<digits.count {
        append_byte(text, digits[i])
    }
}

/**
 * Append a signed number: a - for a negative one, then its magnitude's digits, as append_unsigned writes them.
 *
 * @param text The buffer. If it fills, what fits is kept, the rest dropped, and truncated set.
 * @param value The number, the most negative i64 included.
 * @param base The base, from 2 to 16; any other calls context.assertion_handler.
 * @param minimum_digits The fewest digits written after any -, padded with leading zeros.
 */
append_signed :: fn(text: ptr[mut TextBuffer], value: i64, base: u64 = 10, minimum_digits: usize = 1) {
    if value < 0 {
        append_byte(text, cast[u8]('-'))
        // Negating in unsigned arithmetic also works for the most negative value
        append_unsigned(text, 0 - cast[u64](value), base, minimum_digits)
        return void
    }
    append_unsigned(text, cast[u64](value), base, minimum_digits)
}

/**
 * Append a number as 0x followed by 16 lowercase hexadecimal digits, the way addresses are usually shown.
 *
 * @param text The buffer. If it fills, what fits is kept, the rest dropped, and truncated set.
 * @param value The number, like an address cast to u64.
 */
append_address :: fn(text: ptr[mut TextBuffer], value: u64) {
    append(text, "0x")
    append_unsigned(text, value, 16, 16)
}
