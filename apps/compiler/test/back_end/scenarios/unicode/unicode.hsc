/*
 * std/unicode: UTF-8 decoded and encoded, every case of the Unicode Character Database's GraphemeBreakTest.txt split
 * into the clusters it expects, and the columns clusters take. main returns 42 if everything worked, or the number of
 * the first check that failed.
 */
package unicode_test

import unicode from "std"

TESTS :: #file_data("../../../../../../std/unicode/test/grapheme_break_test.txt")

// The most code points, and boundaries, one test line has.
MOST :: 32

main :: fn() -> int {
    // Decoding: each length, and what isn't UTF-8
    bytes :: string_bytes("aé中😀")
    point, length := unicode.decode(bytes, 0)
    if point != 0x61 || length != 1 {
        return 1
    }
    point, length = unicode.decode(bytes, 1)
    if point != 0xe9 || length != 2 {
        return 2
    }
    point, length = unicode.decode(bytes, 3)
    if point != 0x4e2d || length != 3 {
        return 3
    }
    point, length = unicode.decode(bytes, 6)
    if point != 0x1f600 || length != 4 {
        return 4
    }
    overlong :: u8.[0xc0, 0xaf]
    surrogate :: u8.[0xed, 0xa0, 0x80]
    cut :: u8.[0xe4, 0xb8]
    _, overlong_length :: unicode.decode(overlong, 0)
    _, surrogate_length :: unicode.decode(surrogate, 0)
    _, cut_length :: unicode.decode(cut, 0)
    if overlong_length != 0 || surrogate_length != 0 || cut_length != 0 {
        return 5
    }
    // Encoding round trips
    for each in u32.[0x24, 0xa2, 0x20ac, 0x10348, 0x10ffff] {
        into : u8[4]
        written :: unicode.encode(each, into)
        back, back_length :: unicode.decode(into, 0)
        if written == 0 || back != each || back_length != written {
            return 6
        }
    }
    into : u8[4]
    if unicode.encode(0xd800, into) != 0 || unicode.encode(0x110000, into) != 0 {
        return 7
    }
    // Properties
    if unicode.grapheme_break(0x0d) != .CR || unicode.grapheme_break(0x0301) != .Extend || !unicode.is_extended_pictographic(0x1f600)
        || !unicode.is_default_ignorable(0x200b) || !unicode.is_bidi_control(0x202e) || unicode.is_bidi_control(0x41) {
        return 8
    }
    // Widths: narrow, wide, combining, emoji, flags, and bytes that aren't UTF-8
    if unicode.text_width(string_bytes("abc")) != 3 || unicode.text_width(string_bytes("中文")) != 4 {
        return 9
    }
    if unicode.text_width(string_bytes("é")) != 1 || unicode.text_width(string_bytes("😀")) != 2 {
        return 10
    }
    // A family (ZWJ sequence), a flag, a heart with emoji presentation and one with text presentation
    if unicode.text_width(string_bytes("👨‍👩‍👧")) != 2
        || unicode.text_width(string_bytes("🇯🇵")) != 2 || unicode.text_width(string_bytes("❤️")) != 2
        || unicode.text_width(string_bytes("❤︎")) != 1 {
        return 11
    }
    // A Hangul syllable from jamo
    if unicode.text_width(string_bytes("각")) != 2 || unicode.text_width(u8.[0xff, 0x41]) != 2 {
        return 12
    }
    return check_breaks()
}

// Every line of GraphemeBreakTest.txt: its code points as UTF-8, split where it marks ÷ and nowhere else.
check_breaks :: fn() -> int {
    lines : usize = 0
    at : usize = 0
    loop {
        // One line, without its line break
        start :: at
        loop {
            if at >= TESTS.count || TESTS[at] == cast[u8]('\n') {
                break
            }
            at += 1
        }
        end :: at
        at += 1
        if end > start && start < TESTS.count && TESTS[start] != cast[u8]('#') {
            if !check_line(TESTS[start..<end]) {
                return 20
            }
            lines += 1
        }
    }
    while at < TESTS.count
    // Unicode 17.0.0's file has 766 cases
    return if lines >= 700 { 42 } else { 21 }
}

// One test line, "÷ 0020 × 0308 ÷  # comment": whether grapheme_end splits its text where ÷ says.
check_line :: fn(line: u8[]) -> bool {
    text : u8[MOST * 4]
    text_count : usize = 0
    // Where a break is expected, by byte offset into text
    breaks : bool[MOST * 4 + 1]
    i : usize = 0
    loop {
        if i >= line.count || line[i] == cast[u8]('#') {
            break
        }
        character :: line[i]
        // ÷ is C3 B7 in UTF-8, × is C3 97
        if character == 0xc3 && i + 1 < line.count {
            if line[i + 1] == 0xb7 && text_count < breaks.count {
                breaks[text_count] = true
            }
            i += 2
            continue
        }
        if is_hex(character) {
            point : u32 = 0
            loop {
                if i >= line.count || !is_hex(line[i]) {
                    break
                }
                point = point * 16 + hex_value(line[i])
                i += 1
            }
            if text_count > text.count || text.count - text_count < 4 {
                return false
            }
            text_count += unicode.encode(point, text[text_count..<text.count])
            continue
        }
        i += 1
    }
    // Each cluster from grapheme_end must end at an expected break, with none expected inside it
    if text_count > text.count {
        return false
    }
    position : usize = 0
    loop {
        end :: unicode.grapheme_end(text[0..<text_count], position)
        if end <= position || end > text_count || end >= breaks.count || !breaks[end] {
            return false
        }
        for inside in position + 1..<end {
            if inside < breaks.count && breaks[inside] {
                return false
            }
        }
        position = end
    }
    while position < text_count
    return true
}

is_hex :: fn(character: u8) -> bool {
    return (character >= cast[u8]('0') && character <= cast[u8]('9')) || (character >= cast[u8]('A') && character <= cast[u8]('F'))
}

hex_value :: fn(character: u8) -> u32 {
    return if character <= cast[u8]('9') { cast[u32](character - cast[u8]('0')) } else { cast[u32](character - cast[u8]('A')) + 10 }
}
