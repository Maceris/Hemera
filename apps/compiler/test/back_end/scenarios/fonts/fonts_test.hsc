/*
 * std/fonts against Noto Sans and Noto Sans Mono (OFL, apps/compiler/test/back_end/fonts): metrics, glyphs and
 * advances against what references.py read with a reader of its own; outlines whose points' bounds are glyf's
 * bounding boxes, simple and composite; kerning; measuring and wrapping; and any bytes refused or read without harm.
 */
package fonts_test

import runtime from "base"
import fonts from "std"
import strings from "std"
import testing from "std"

SANS :: #file_data("../../fonts/NotoSans-Regular.ttf")
MONO :: #file_data("../../fonts/NotoSansMono-Regular.ttf")

/** What references.py found for a character. */
Expected :: struct {
    point : u32,
    glyph : u32,
    advance : i32,
    x_min : i32,
    y_min : i32,
    x_max : i32,
    y_max : i32,
}

/** A font opened, for a test. */
sans :: fn() -> fonts.Font {
    return fonts.open(SANS[0..<SANS.count]) or_else fonts.Font.{}
}

/** The mono font opened. */
mono :: fn() -> fonts.Font {
    return fonts.open(MONO[0..<MONO.count]) or_else fonts.Font.{}
}

reads_metrics #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    font :: sans()
    testing.require(t, font.units_per_em != 0, "Noto Sans opens")?
    testing.expect_eq(t, font.units_per_em, cast[u32](NOTOSANS_REGULAR_UNITS), "units per em")
    testing.expect_eq(t, font.ascender, cast[i32](NOTOSANS_REGULAR_ASCENDER), "ascender")
    testing.expect_eq(t, font.descender, cast[i32](NOTOSANS_REGULAR_DESCENDER), "descender")
    testing.expect_eq(t, font.line_gap, cast[i32](NOTOSANS_REGULAR_LINE_GAP), "line gap")
    monospaced :: mono()
    testing.expect_eq(t, monospaced.ascender, cast[i32](NOTOSANSMONO_REGULAR_ASCENDER), "the mono's ascender")
    testing.expect(t, fonts.open(SANS[0..<100]) == null, "a font cut short isn't opened")
    return .Ok
}

finds_glyphs_and_advances #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    for pair in u8.[0, 1] {
        font :: if pair == 0 { sans() } else { mono() }
        expected :: if pair == 0 { NOTOSANS_REGULAR_GLYPHS[0..<NOTOSANS_REGULAR_GLYPHS.count] } else { NOTOSANSMONO_REGULAR_GLYPHS[0..<NOTOSANSMONO_REGULAR_GLYPHS.count] }
        for each in expected {
            glyph :: fonts.glyph_index(&font, each.point)
            if glyph != each.glyph || fonts.advance(&font, glyph) != each.advance {
                testing.note(t, strings.format("U+%: glyph % advance %, expected % and %", each.point, glyph, fonts.advance(&font, glyph), each.glyph, each.advance) or_else "")
                testing.fail(t, "a glyph or its advance isn't the reference's")
            }
        }
    }
    font :: sans()
    testing.expect_eq(t, fonts.glyph_index(&font, 0x10ffff), cast[u32](0), "a code point the font hasn't gives the missing glyph")
    return .Ok
}

outlines_match_bounding_boxes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    font :: sans()
    outline := fonts.Outline.{}
    defer fonts.free_outline(&outline)
    for each in NOTOSANS_REGULAR_GLYPHS {
        fonts.clear(&outline)
        testing.require(t, fonts.glyph_outline(&font, each.glyph, &outline), "an outline's read")?
        if each.x_max == 0 && each.y_max == 0 {
            testing.expect_eq(t, outline.verbs.count, cast[usize](0), "a space has no contours")
            continue
        }
        x_min := cast[f32](1e9)
        y_min := cast[f32](1e9)
        x_max := cast[f32](-1e9)
        y_max := cast[f32](-1e9)
        for point in outline.points {
            x_min = if point.x < x_min { point.x } else { x_min }
            y_min = if point.y < y_min { point.y } else { y_min }
            x_max = if point.x > x_max { point.x } else { x_max }
            y_max = if point.y > y_max { point.y } else { y_max }
        }
        close :: near(x_min, each.x_min) && near(y_min, each.y_min) && near(x_max, each.x_max) && near(y_max, each.y_max)
        if !close {
            testing.note(t, strings.format("U+%: bounds % % % %, expected % % % %", each.point, x_min, y_min, x_max, y_max, each.x_min, each.y_min, each.x_max, each.y_max) or_else "")
            testing.fail(t, "an outline's bounds aren't its glyph's bounding box")
        }
        // Contours: a Move first, a Close last, and the verbs' points all there
        needed := cast[usize](0)
        for verb in outline.verbs {
            needed += if verb == .Quad { cast[usize](2) } else if verb == .Close { cast[usize](0) } else { cast[usize](1) }
        }
        verbs :: outline.verbs[0..<outline.verbs.count]
        testing.expect(t, verbs.count > 0 && verbs[0] == .Move && verbs[verbs.count - 1] == .Close,
            "contours open with a Move and end with a Close")
        testing.expect_eq(t, needed, outline.points.count, "and the verbs have their points")
    }
    return .Ok
}

/** Whether a bound read from points is the reference's, within a unit. */
near :: fn(found: f32, expected: i32) -> bool {
    difference :: found - cast[f32](expected)
    return difference < 1.01 && difference > -1.01
}

kerns_pairs #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    font :: sans()
    a :: fonts.glyph_index(&font, cast[u32]('A'))
    v :: fonts.glyph_index(&font, cast[u32]('V'))
    testing.expect(t, font.pair_count > 0, "Noto Sans's kerning is in GPOS")
    testing.expect(t, fonts.kerning(&font, a, v) < 0, "A then V are kerned closer")
    testing.expect(t, fonts.kerning(&font, v, a) < 0, "and V then A")
    testing.expect_eq(t, fonts.kerning(&font, a, a), cast[i32](0), "A then A isn't kerned")
    monospaced :: mono()
    testing.expect_eq(t, fonts.kerning(&monospaced, fonts.glyph_index(&monospaced, cast[u32]('A')), fonts.glyph_index(&monospaced, cast[u32]('V'))), cast[i32](0),
        "a monospaced font isn't kerned")
    // Measured: the advances and the kerning, scaled
    width :: fonts.measure(&font, 20, string_bytes("AV"))
    expected :: cast[f32](fonts.advance(&font, a) + fonts.advance(&font, v) + fonts.kerning(&font, a, v)) * 20 / 1000
    testing.expect(t, width - expected < 0.001 && expected - width < 0.001, "AV measures its advances and kerning")
    return .Ok
}

wraps_lines #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    font :: mono()
    lines : fonts.Line[..]
    defer runtime.array_free(&lines)
    // Each character 600 units, so 6 px at 10 px: 60 px holds 10 characters
    text :: string_bytes("the quick brown fox jumps")
    fonts.wrap(&font, 10, text, 60, &lines)
    testing.require_eq(t, lines.count, cast[usize](3), "three lines")?
    found :: lines[0..<lines.count]
    if found.count < 3 {
        return .Ok
    }
    testing.expect(t, is_line(text, found[0], "the quick"), "the first, wrapped after a word")
    testing.expect(t, is_line(text, found[1], "brown fox"), "the second")
    testing.expect(t, is_line(text, found[2], "jumps"), "the third")
    testing.expect(t, found[0].width > 53.9 && found[0].width < 54.1, "its width is its nine characters', its space left out")
    runtime.array_reset(&lines)
    fonts.wrap(&font, 10, string_bytes("abcdefghijklmnop"), 60, &lines)
    testing.require_eq(t, lines.count, cast[usize](2), "a word wider than the width is broken")?
    if lines.count < 2 {
        return .Ok
    }
    testing.expect_eq(t, lines[0].end - lines[0].start, cast[usize](10), "after ten characters")
    runtime.array_reset(&lines)
    fonts.wrap(&font, 10, string_bytes("one\ntwo\r\n"), 600, &lines)
    testing.expect_eq(t, lines.count, cast[usize](3), "line breaks end lines, the last after the text's last break")
    return .Ok
}

/** Whether a line is a piece of text. */
is_line :: fn(text: u8[], line: fonts.Line, expected: string) -> bool {
    if line.end < line.start || line.end > text.count {
        return false
    }
    want :: string_bytes(expected)
    if line.end - line.start != want.count {
        return false
    }
    for byte, i in want {
        if line.start + i < text.count && text[line.start + i] != byte {
            return false
        }
    }
    return true
}

/** Any bytes are refused as a font, or read, every glyph's outline among them, without harm. */
reads_any_font_bytes #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    bytes :: testing.draw_bytes(source, 4000)
    font :: fonts.open(bytes) or_return .Ok
    outline := fonts.Outline.{}
    defer fonts.free_outline(&outline)
    for glyph in cast[u32](0)..<(if font.glyph_count < 64 { font.glyph_count } else { cast[u32](64) }) {
        fonts.clear(&outline)
        _ = fonts.glyph_outline(&font, glyph, &outline)
        _ = fonts.kerning(&font, glyph, glyph)
    }
    _ = fonts.measure(&font, 12, bytes)
    return .Ok
}

/** Noto Sans with some of its bytes changed: refused or read, without harm. */
reads_a_changed_font #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    copy, error :: runtime.new_array(u8, SANS.count)
    if error != null {
        return .Ok
    }
    defer runtime.free_array(copy)
    for byte, i in SANS {
        if i < copy.count {
            copy[i] = byte
        }
    }
    for change in 0..<16 {
        at :: cast[usize](testing.draw_between(source, 0, cast[int](SANS.count - 1)))
        if at < copy.count {
            copy[at] = cast[u8](testing.draw_between(source, 0, 255))
        }
    }
    font :: fonts.open(copy) or_return .Ok
    outline := fonts.Outline.{}
    defer fonts.free_outline(&outline)
    for each in NOTOSANS_REGULAR_GLYPHS {
        fonts.clear(&outline)
        _ = fonts.glyph_outline(&font, each.glyph, &outline)
    }
    _ = fonts.measure(&font, 12, string_bytes("AVWagé0 .€"))
    return .Ok
}
