/*
 * std/unicode: UTF-8 decoded and encoded, every case of the Unicode Character Database's GraphemeBreakTest.txt split
 * into the clusters it expects, the columns clusters take, and normalization (NormalizationTest.txt) and case folding.
 */
package unicode_test

import testing from "std"
import unicode from "std"

TESTS :: #file_data("../../../../../../std/unicode/test/grapheme_break_test.txt")

// The most code points, and boundaries, one test line has.
MOST :: 32

decodes_each_length #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    bytes :: string_bytes("aé中😀")
    point, length := unicode.decode(bytes, 0)
    testing.expect(t, point == 0x61 && length == 1, "ASCII is one byte")
    point, length = unicode.decode(bytes, 1)
    testing.expect(t, point == 0xe9 && length == 2, "é is two bytes")
    point, length = unicode.decode(bytes, 3)
    testing.expect(t, point == 0x4e2d && length == 3, "a CJK ideograph is three bytes")
    point, length = unicode.decode(bytes, 6)
    testing.expect(t, point == 0x1f600 && length == 4, "an emoji past the BMP is four bytes")
    return .Ok
}

refuses_what_isnt_utf8 #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    overlong :: u8.[0xc0, 0xaf]
    surrogate :: u8.[0xed, 0xa0, 0x80]
    cut :: u8.[0xe4, 0xb8]
    _, overlong_length :: unicode.decode(overlong, 0)
    _, surrogate_length :: unicode.decode(surrogate, 0)
    _, cut_length :: unicode.decode(cut, 0)
    testing.expect_eq(t, overlong_length, 0, "a / written in two bytes is overlong")
    testing.expect_eq(t, surrogate_length, 0, "a UTF-16 surrogate isn't a code point")
    testing.expect_eq(t, cut_length, 0, "three bytes' sequence cut off after two")
    return .Ok
}

encodes_and_decodes_back #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    for each in u32.[0x24, 0xa2, 0x20ac, 0x10348, 0x10ffff] {
        into : u8[4]
        written :: unicode.encode(each, into)
        back, back_length :: unicode.decode(into, 0)
        testing.expect_ne(t, written, 0, "each length, up to the last code point, is encoded")
        testing.expect_eq(t, back, each, "what's encoded decodes back")
        testing.expect_eq(t, back_length, written, "taking the bytes encode wrote")
    }
    into : u8[4]
    testing.expect_eq(t, unicode.encode(0xd800, into), 0, "a surrogate isn't encoded")
    testing.expect_eq(t, unicode.encode(0x110000, into), 0, "past the last code point isn't encoded")
    return .Ok
}

knows_properties #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, unicode.grapheme_break(0x0d) == .CR, "carriage return has a break property of its own")
    testing.expect(t, unicode.grapheme_break(0x0301) == .Extend, "a combining accent extends what's before it")
    testing.expect(t, unicode.is_extended_pictographic(0x1f600), "an emoji is pictographic")
    testing.expect(t, unicode.is_default_ignorable(0x200b), "a zero-width space is ignorable")
    testing.expect(t, unicode.is_bidi_control(0x202e), "right-to-left override controls direction")
    testing.expect(t, !unicode.is_bidi_control(0x41), "a letter doesn't")
    return .Ok
}

measures_columns #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Narrow, wide, combining, emoji, flags, and bytes that aren't UTF-8
    testing.expect_eq(t, unicode.text_width(string_bytes("abc")), 3, "ASCII is a column a letter")
    testing.expect_eq(t, unicode.text_width(string_bytes("中文")), 4, "CJK ideographs are wide, two columns each")
    testing.expect_eq(t, unicode.text_width(string_bytes("é")), 1, "a letter with an accent is one column")
    testing.expect_eq(t, unicode.text_width(string_bytes("😀")), 2, "an emoji is wide")
    // A family (ZWJ sequence), a flag, a heart with emoji presentation and one with text presentation
    testing.expect_eq(t, unicode.text_width(string_bytes("👨‍👩‍👧")), 2, "a ZWJ family is one wide cluster")
    testing.expect_eq(t, unicode.text_width(string_bytes("🇯🇵")), 2, "a flag's two regional indicators are one wide cluster")
    testing.expect_eq(t, unicode.text_width(string_bytes("❤️")), 2, "a heart with emoji presentation is wide")
    testing.expect_eq(t, unicode.text_width(string_bytes("❤︎")), 1, "a heart with text presentation is narrow")
    // A Hangul syllable from jamo
    testing.expect_eq(t, unicode.text_width(string_bytes("각")), 2, "a Hangul syllable made from jamo is one wide cluster")
    testing.expect_eq(t, unicode.text_width(u8.[0xff, 0x41]), 2, "a byte that isn't UTF-8 takes a column, as a replacement would")
    return .Ok
}

splits_every_case_of_grapheme_break_test #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Each line's code points as UTF-8, split where it marks ÷ and nowhere else
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
            testing.expect(t, check_line(TESTS[start..<end]), "grapheme_end splits each line's text where ÷ marks, and only there")
            lines += 1
        }
    }
    while at < TESTS.count
    // Unicode 17.0.0's file has 766 cases
    testing.expect_ge(t, lines, 700, "the whole file is read, 766 cases in Unicode 17.0.0")
    return .Ok
}

/**
 * Check one line of GraphemeBreakTest.txt, like "÷ 0020 × 0308 ÷  # comment".
 *
 * @param line The line, without its line break.
 * @return Whether grapheme_end splits its code points, as UTF-8, where ÷ says and nowhere else; false too for a line
 *     of more than MOST code points.
 */
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

/**
 * Tell whether a byte is an uppercase hexadecimal digit, as the file writes code points.
 *
 * @param character Any byte.
 * @return True for 0 to 9 and A to F.
 */
is_hex :: fn(character: u8) -> bool {
    return (character >= cast[u8]('0') && character <= cast[u8]('9')) || (character >= cast[u8]('A') && character <= cast[u8]('F'))
}

/**
 * Give an uppercase hexadecimal digit's value.
 *
 * @param character A digit, as is_hex says.
 * @return Its value, 0 to 15.
 */
hex_value :: fn(character: u8) -> u32 {
    return if character <= cast[u8]('9') { cast[u32](character - cast[u8]('0')) } else { cast[u32](character - cast[u8]('A')) + 10 }
}

// ---- Normalization (UAX #15) and case folding

NORMALIZATION_TESTS :: #file_data("../../../../../../std/unicode/test/normalization_test.txt")

/** The most code points one field of a NormalizationTest.txt line has. */
FIELD_MOST :: 40

/**
 * Every line kept of NormalizationTest.txt: for its fields c1 to c3, NFC(c1), NFC(c2) and NFC(c3) are c2, and NFD of
 * each is c3 (the NFKC and NFKD fields, c4 and c5, are compatibility forms, which aren't these).
 */
normalizes_every_case_of_normalization_test #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    lines : usize = 0
    failed : usize = 0
    at : usize = 0
    loop {
        start :: at
        loop {
            if at >= NORMALIZATION_TESTS.count || NORMALIZATION_TESTS[at] == cast[u8]('\n') {
                break
            }
            at += 1
        }
        end :: at
        at += 1
        if end > start && start < NORMALIZATION_TESTS.count && is_hex(NORMALIZATION_TESTS[start]) {
            lines += 1
            if !check_normalization(NORMALIZATION_TESTS[start..<end]) {
                failed += 1
            }
        }
    }
    while at < NORMALIZATION_TESTS.count
    testing.expect_eq(t, failed, 0, "NFC gives c2 and NFD gives c3 for each of c1 to c3, on every line")
    testing.expect_ge(t, lines, 4000, "the whole file is read: parts 0 and 2 to 5, and a line in ten of part 1")
    return .Ok
}

/** One field of a NormalizationTest.txt line, as UTF-8. */
Field :: struct {
    /** Its bytes, the first count of them. */
    bytes : u8[FIELD_MOST * 4],
    /** How many of bytes are its. */
    count : usize,
}

/**
 * Add a code point to a field, as UTF-8.
 *
 * @param field The field.
 * @param point The code point.
 * @return False if there's no room for it.
 */
add_point :: fn(field: ptr[mut Field], point: u32) -> bool {
    at :: field.count
    if at > field.bytes.count {
        return false
    }
    written :: unicode.encode(point, field.bytes[at..<field.bytes.count])
    field.count = at + written
    return written > 0
}

/**
 * See a field's bytes.
 *
 * @param field The field.
 * @return A view of its bytes.
 */
bytes_of :: fn(field: ptr[Field]) -> u8[] {
    count :: field.count
    if count > field.bytes.count {
        return field.bytes[0..<0]
    }
    return field.bytes[0..<count]
}

/**
 * Check one line of NormalizationTest.txt, like "1E0A;1E0A;0044 0307;1E0A;0044 0307; # comment".
 *
 * @param line The line, without its line break.
 * @return Whether NFC of c1, c2 and c3 is c2, and NFD of each is c3; false too for a field of more than FIELD_MOST code
 *     points.
 */
check_normalization :: fn(line: u8[]) -> bool {
    fields : Field[3]
    field := cast[usize](0)
    i := cast[usize](0)
    loop {
        if i >= line.count || line[i] == cast[u8]('#') || field >= 3 {
            break
        }
        character :: line[i]
        if character == cast[u8](';') {
            field += 1
            i += 1
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
            which :: field
            if which >= fields.count || !add_point(&fields[which], point) {
                return false
            }
            continue
        }
        i += 1
    }
    composed_form :: bytes_of(&fields[1])
    decomposed_form :: bytes_of(&fields[2])
    for &source in fields {
        scratch : u32[FIELD_MOST * 4 * unicode.SCRATCH_PER_BYTE]
        out : u8[FIELD_MOST * 4 * unicode.OUTPUT_PER_BYTE]
        nfc :: unicode.normalize(bytes_of(source), .NFC, scratch[0..<scratch.count], out[0..<out.count]) or_return false
        if nfc > out.count || !same(out[0..<nfc], composed_form) {
            return false
        }
        nfd :: unicode.normalize(bytes_of(source), .NFD, scratch[0..<scratch.count], out[0..<out.count]) or_return false
        if nfd > out.count || !same(out[0..<nfd], decomposed_form) {
            return false
        }
    }
    return true
}

/**
 * Tell whether two byte strings are the same.
 *
 * @param a One.
 * @param b The other.
 * @return True if they have the same bytes.
 */
same :: fn(a: u8[], b: u8[]) -> bool {
    if a.count != b.count {
        return false
    }
    for byte, i in a {
        if i < b.count && byte != b[i] {
            return false
        }
    }
    return true
}

/**
 * Write text's canonical caseless key: NFD, case folded, NFD again (the Unicode Standard, 3.13).
 *
 * @param text The text.
 * @param into Where the key goes.
 * @return How many bytes; 0 if it didn't fit.
 */
caseless :: fn(text: u8[], into: mut u8[]) -> usize {
    scratch : u32[256]
    first : u8[192]
    second : u8[192]
    a :: unicode.normalize(text, .NFD, scratch[0..<scratch.count], first[0..<first.count]) or_return 0
    if a > first.count {
        return 0
    }
    b :: unicode.case_fold(first[0..<a], scratch[0..<scratch.count], second[0..<second.count]) or_return 0
    if b > second.count {
        return 0
    }
    return unicode.normalize(second[0..<b], .NFD, scratch[0..<scratch.count], into) or_return 0
}

/**
 * Tell whether what was written to a buffer is the bytes expected.
 *
 * @param out The buffer.
 * @param count How many bytes of it were written.
 * @param expected The bytes expected.
 * @return True if count is in the buffer and its first count bytes are expected's.
 */
wrote :: fn(out: u8[], count: usize, expected: u8[]) -> bool {
    if count > out.count {
        return false
    }
    return same(out[0..<count], expected)
}

/** Case folding folds case fully, ß to ss and final sigma to sigma, and matching that way ignores how accents are written. */
folds_case_and_matches_without_it #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    scratch : u32[64]
    out : u8[48]
    folded :: unicode.case_fold(string_bytes("Straße"), scratch[0..<scratch.count], out[0..<out.count]) or_else 0
    testing.expect(t, wrote(out, folded, string_bytes("strasse")), "ß folds to ss, and capitals to small letters")
    sigma :: unicode.case_fold(string_bytes("ΟΔΟΣ"), scratch[0..<scratch.count], out[0..<out.count]) or_else 0
    testing.expect(t, wrote(out, sigma, string_bytes("οδοσ")), "capital sigma folds to σ")
    a : u8[192]
    b : u8[192]
    // CAFÉ with E and a combining acute accent, U+0301
    first :: caseless(string_bytes("Café"), a[0..<a.count])
    second :: caseless(u8.[0x43, 0x41, 0x46, 0x45, 0xcc, 0x81], b[0..<b.count])
    testing.expect(t, first > 0 && first <= a.count && wrote(b, second, a[0..<first]), "Café and CAFÉ written with a combining accent match without case")
    composed :: unicode.normalize(u8.[0x65, 0xcc, 0x81], .NFC, scratch[0..<scratch.count], out[0..<out.count]) or_else 0
    testing.expect(t, wrote(out, composed, string_bytes("é")), "e and a combining acute compose to é")
    // U+1100, U+1161 and U+11A8
    hangul :: unicode.normalize(u8.[0xe1, 0x84, 0x80, 0xe1, 0x85, 0xa1, 0xe1, 0x86, 0xa8], .NFC, scratch[0..<scratch.count], out[0..<out.count]) or_else 0
    testing.expect(t, wrote(out, hangul, string_bytes("각")), "Hangul jamo compose to their syllable")
    small : u8[2]
    testing.expect(t, unicode.normalize(string_bytes("é"), .NFD, scratch[0..<scratch.count], small[0..<small.count]) is_none,
        "output too small for é decomposed, 3 bytes, is refused")
    return .Ok
}
