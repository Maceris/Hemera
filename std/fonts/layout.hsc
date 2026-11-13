package fonts

import runtime from "base"
import unicode from "std"

/*
 * Text laid out in lines: each glyph's advance, scaled from design units to pixels, with the pair kerning before it;
 * lines wrapped to a width at the spaces between words, or at line breaks, a word wider than the width broken between
 * its characters.
 */

/** A line of text, as wrap gives it: its bytes in the text, and its width in pixels. */
Line :: struct {
    /** Its first byte, and one past its last, in the text, its line break or the spaces it was wrapped at left out. */
    start : usize,
    end : usize,
    /** Its width, in pixels: its glyphs' advances and kerning, its trailing spaces left out. */
    width : f32,
}

/**
 * How many pixels a design unit is at a size.
 *
 * @param font The font.
 * @param size The size, in pixels per em.
 * @return The scale.
 */
scale_of :: fn(font: ptr[Font], size: f32) -> f32 {
    return size / cast[f32](font.units_per_em)
}

/**
 * The height of a line at a size: from one baseline to the next, ascender to descender and the gap.
 *
 * @param font The font.
 * @param size The size, in pixels per em.
 * @return The line's height, in pixels.
 */
line_height :: fn(font: ptr[Font], size: f32) -> f32 {
    return cast[f32](font.ascender - font.descender + font.line_gap) * scale_of(font, size)
}

/**
 * How wide a run of text is, on one line.
 *
 * @param font The font.
 * @param size The size, in pixels per em.
 * @param text UTF-8; line breaks are measured as any other character, with the missing glyph's advance or none.
 * @return Its width in pixels: its glyphs' advances, with the kerning between each pair.
 */
measure :: fn(font: ptr[Font], size: f32, text: u8[]) -> f32 {
    units := cast[i32](0)
    previous := cast[u32](0)
    at := cast[usize](0)
    loop {
        point, length :: unicode.decode(text, at)
        at += if length > 0 { length } else { cast[usize](1) }
        glyph :: glyph_index(font, point)
        if previous != 0 {
            units += kerning(font, previous, glyph)
        }
        units += advance(font, glyph)
        previous = glyph
    }
    while at < text.count
    return cast[f32](units) * scale_of(font, size)
}

/**
 * Wrap text into lines no wider than a width: broken at line breaks (LF, or CR LF), and at the spaces between words
 * when the next word won't fit, a word wider than the width broken between its characters.
 *
 * @param font The font.
 * @param size The size, in pixels per em.
 * @param text UTF-8.
 * @param width The widest a line may be, in pixels; at most one character goes on a line narrower than it.
 * @param lines Where the lines go, added to what's there.
 */
wrap :: fn(font: ptr[Font], size: f32, text: u8[], width: f32, lines: ptr[mut Line[..]]) {
    scale :: scale_of(font, size)
    limit :: if scale > 0 { width / scale } else { cast[f32](0) }
    start := cast[usize](0)
    units := cast[i32](0)
    previous := cast[u32](0)
    // The last place a line could end: after a word, before its spaces; and where the next line would then start
    break_end := cast[usize](0)
    break_units := cast[i32](0)
    break_next := cast[usize](0)
    has_break := false
    in_spaces := false
    at := cast[usize](0)
    loop {
        if at >= text.count {
            break
        }
        point, length :: unicode.decode(text, at)
        step :: if length > 0 { length } else { cast[usize](1) }
        if point == 0x0a || point == 0x0d {
            end :: at
            runtime.array_add(lines, Line.{start = start, end = trailing_end(text, start, end), width = cast[f32](trailing_units(font, text, start, end)) * scale})
            at += step
            if point == 0x0d && at < text.count && text[at] == 0x0a {
                at += 1
            }
            start = at
            units = 0
            previous = 0
            has_break = false
            in_spaces = false
            continue
        }
        if point == 0x20 {
            if !in_spaces {
                break_end = at
                break_units = units
                has_break = true
            }
            in_spaces = true
        }
        else if in_spaces {
            // A word starts here: the line could start here after a break
            break_next = at
            in_spaces = false
        }
        glyph :: glyph_index(font, point)
        added := advance(font, glyph)
        if previous != 0 {
            added += kerning(font, previous, glyph)
        }
        if point != 0x20 && cast[f32](units + added) > limit && at > start {
            if has_break && break_next > start {
                // Back to the last break: this word starts the next line
                runtime.array_add(lines, Line.{start = start, end = break_end, width = cast[f32](break_units) * scale})
                start = break_next
                at = break_next
            }
            else {
                // A word wider than the line, broken before this character
                runtime.array_add(lines, Line.{start = start, end = at, width = cast[f32](units) * scale})
                start = at
            }
            units = 0
            previous = 0
            has_break = false
            in_spaces = false
            continue
        }
        units += added
        previous = glyph
        at += step
    }
    while true
    if start < text.count || lines.count == 0 || ends_with_break(text) {
        runtime.array_add(lines, Line.{start = start, end = trailing_end(text, start, text.count), width = cast[f32](trailing_units(font, text, start, text.count)) * scale})
    }
}

/** Whether text ends with a line break, so a last, empty line follows it. */
ends_with_break :: fn(text: u8[]) -> bool {
    return text.count > 0 && (text[text.count - 1] == 0x0a || text[text.count - 1] == 0x0d)
}

/** Where a line ends with its trailing spaces left out. */
trailing_end :: fn(text: u8[], start: usize, end: usize) -> usize {
    trimmed := end
    loop {
        trimmed -= 1
    }
    while trimmed > start && trimmed - 1 < text.count && text[trimmed - 1] == 0x20
    return trimmed
}

/** A line's width in design units, its trailing spaces left out. */
trailing_units :: fn(font: ptr[Font], text: u8[], start: usize, end: usize) -> i32 {
    stop :: trailing_end(text, start, end)
    units := cast[i32](0)
    previous := cast[u32](0)
    at := start
    loop {
        point, length :: unicode.decode(text, at)
        at += if length > 0 { length } else { cast[usize](1) }
        glyph :: glyph_index(font, point)
        if previous != 0 {
            units += kerning(font, previous, glyph)
        }
        units += advance(font, glyph)
        previous = glyph
    }
    while at < stop
    return units
}
