package text_buffer

import runtime from "base"

/*
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
    bytes : mut u8[],
    count : usize,
    truncated : bool,
}

DIGITS :: "0123456789abcdef"

make :: fn(bytes: mut u8[]) -> TextBuffer {
    return TextBuffer.{bytes = bytes, count = 0, truncated = false}
}

// What's been appended so far.
as_string :: fn(text: ptr[TextBuffer]) -> string {
    if text.count == 0 || text.bytes.count == 0 {
        return ""
    }
    return string_of(&text.bytes[0], text.count)
}

clear :: fn(text: ptr[mut TextBuffer]) {
    text.count = 0
    text.truncated = false
}

append_byte :: fn(text: ptr[mut TextBuffer], byte: u8) {
    if text.count >= text.bytes.count {
        text.truncated = true
        return void
    }
    text.bytes[text.count] = byte
    text.count += 1
}

append :: fn(text: ptr[mut TextBuffer], value: string) {
    for character in value {
        append_byte(text, cast[u8](character))
    }
}

/*
 * value in base (2 to 16), with at least minimum_digits digits, padded with zeros.
 * Hexadecimal digits are lowercase, with no prefix.
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

append_signed :: fn(text: ptr[mut TextBuffer], value: i64, base: u64 = 10, minimum_digits: usize = 1) {
    if value < 0 {
        append_byte(text, cast[u8]('-'))
        // Negating in unsigned arithmetic also works for the most negative value
        append_unsigned(text, 0 - cast[u64](value), base, minimum_digits)
        return void
    }
    append_unsigned(text, cast[u64](value), base, minimum_digits)
}

// value as 0x followed by 16 hexadecimal digits, the way addresses are usually shown.
append_address :: fn(text: ptr[mut TextBuffer], value: u64) {
    append(text, "0x")
    append_unsigned(text, value, 16, 16)
}
