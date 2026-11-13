package fonts

import runtime from "base"

/*
 * The TrueType container (the OpenType specification, "Font file"): a table directory, then tables found by their
 * four-character tags. Every read is bounded: a font that says more than its bytes hold gives zeros, never a read
 * past them, so a damaged font draws wrongly but safely. open checks the tables it needs are within the bytes.
 */

/** The most components a composite glyph is followed through, nested. */
MAX_COMPOSITE_DEPTH :: 8
/** The most pair-kerning subtables kept from a font's GPOS. */
MAX_PAIR_SUBTABLES :: 64

/** A table's place in the font: its offset and length in bytes. */
Table :: struct {
    at : usize,
    size : usize,
}

/** A font, read from its bytes: what its tables say, and where they are; scoped, as it's a view of the bytes. */
Font :: struct #scoped {
    /** Its bytes, the caller's, kept for as long as the font's used. */
    data : u8[],
    /** Its design units in an em: 1000 or 2048, typically. */
    units_per_em : u32,
    /** Above and below the baseline, and the gap between lines, in design units; descender is negative. */
    ascender : i32,
    descender : i32,
    line_gap : i32,
    /** How many glyphs it has. */
    glyph_count : u32,
    /** Whether loca's offsets are 32-bit, not 16-bit halves. */
    long_loca : bool,
    /** How many glyphs have their own advance in hmtx; the rest have the last's. */
    hmetric_count : u32,
    hmtx : Table,
    loca : Table,
    glyf : Table,
    /** The character map's subtable chosen, by its offset in the font, and its format, 4 or 12; 0 for none. */
    cmap_at : usize,
    cmap_format : u32,
    /** GPOS's pair-adjustment subtables of its kern feature, by their offsets in the font. */
    pairs : u32[MAX_PAIR_SUBTABLES],
    pair_count : usize,
    /** The kern table, used when GPOS has no pair kerning; size 0 for none. */
    kern : Table,
}

/** A point of an outline, in design units, y up. */
Point :: struct {
    x : f32,
    y : f32,
}

/** What an outline's command does. */
Verb :: enum #backed_by(u8) {
    /** Start a contour at a point. */
    Move,
    /** A line to a point. */
    Line,
    /** A quadratic curve through a control point to a point: two points. */
    Quad,
    /** Close the contour, back to where it started. */
    Close,
}

/** A glyph's outline: its contours' commands and their points, in design units, y up. */
Outline :: struct {
    verbs : Verb[..],
    points : Point[..],
    /** Scratch for a simple glyph's points as it's read. */
    flags : u8[..],
    xs : i32[..],
    ys : i32[..],
}

/** An affine transform of outline points: x' = a x + c y + e, y' = b x + d y + f. */
Transform :: struct {
    a : f32 = 1,
    b : f32,
    c : f32,
    d : f32 = 1,
    e : f32,
    f : f32,
}

// ---- Reading bytes, bounded

/** A byte at an offset, or 0 past the end. */
u8_at :: fn(data: u8[], at: usize) -> u8 {
    return if at < data.count { data[at] } else { cast[u8](0) }
}

/** A big-endian u16 at an offset, or 0 past the end. */
u16_at :: fn(data: u8[], at: usize) -> u16 {
    return (cast[u16](u8_at(data, at)) << 8) | cast[u16](u8_at(data, at + 1))
}

/** A big-endian i16 at an offset, or 0 past the end. */
i16_at :: fn(data: u8[], at: usize) -> i16 {
    return bit_cast[i16](u16_at(data, at))
}

/** A big-endian u32 at an offset, or 0 past the end. */
u32_at :: fn(data: u8[], at: usize) -> u32 {
    return (cast[u32](u16_at(data, at)) << 16) | cast[u32](u16_at(data, at + 2))
}

/** A tag, four ASCII characters, as the u32 they're stored as. */
tag :: fn(name: string) -> u32 {
    bytes :: string_bytes(name)
    value := cast[u32](0)
    for i in cast[usize](0)..<4 {
        value = (value << 8) | cast[u32](if i < bytes.count { bytes[i] } else { cast[u8](0x20) })
    }
    return value
}

/**
 * Find a table by its tag.
 *
 * @param data The font's bytes.
 * @param name Its tag, as "glyf".
 * @return Its place; size 0 if it isn't there, or isn't all within the bytes.
 */
find_table :: fn(data: u8[], name: string) -> Table {
    wanted :: tag(name)
    count :: cast[usize](u16_at(data, 4))
    for i in cast[usize](0)..<count {
        record :: 12 + 16 * i
        if u32_at(data, record) == wanted {
            at :: cast[usize](u32_at(data, record + 8))
            size :: cast[usize](u32_at(data, record + 12))
            if at <= data.count && size <= data.count - at {
                return Table.{at = at, size = size}
            }
            return Table.{}
        }
    }
    return Table.{}
}

/**
 * Read a font from its bytes.
 *
 * @param data A TrueType or OpenType font with TrueType outlines, the caller's, kept for as long as the font's used.
 * @return The font; null if it isn't one: the wrong version, or missing a table it needs (head, hhea, maxp, hmtx,
 *     cmap, loca, glyf), or one of those past its bytes.
 */
open :: fn(data: u8[]) -> Font? {
    version :: u32_at(data, 0)
    if version != 0x00010000 && version != tag("true") {
        return null
    }
    head :: find_table(data, "head")
    hhea :: find_table(data, "hhea")
    maxp :: find_table(data, "maxp")
    font := Font.{data = data, hmtx = find_table(data, "hmtx"), loca = find_table(data, "loca"), glyf = find_table(data, "glyf"),
        kern = find_table(data, "kern")}
    cmap :: find_table(data, "cmap")
    if head.size < 54 || hhea.size < 36 || maxp.size < 6 || font.hmtx.size == 0 || cmap.size == 0 || font.loca.size == 0 || font.glyf.size == 0 {
        return null
    }
    font.units_per_em = cast[u32](u16_at(data, head.at + 18))
    font.long_loca = i16_at(data, head.at + 50) != 0
    font.ascender = cast[i32](i16_at(data, hhea.at + 4))
    font.descender = cast[i32](i16_at(data, hhea.at + 6))
    font.line_gap = cast[i32](i16_at(data, hhea.at + 8))
    font.hmetric_count = cast[u32](u16_at(data, hhea.at + 34))
    font.glyph_count = cast[u32](u16_at(data, maxp.at + 4))
    if font.units_per_em == 0 || font.hmetric_count == 0 {
        return null
    }
    choose_cmap(&font, cmap)
    if font.cmap_format == 0 {
        return null
    }
    find_pair_kerning(&font)
    return font
}

/** Choose the character map's subtable: format 12 for all of Unicode where there's one, else format 4. */
choose_cmap :: fn(font: ptr[mut Font], cmap: Table) {
    data :: font.data
    count :: cast[usize](u16_at(data, cmap.at + 2))
    for i in cast[usize](0)..<count {
        record :: cmap.at + 4 + 8 * i
        platform :: u16_at(data, record)
        encoding :: u16_at(data, record + 2)
        at :: cmap.at + cast[usize](u32_at(data, record + 4))
        format :: cast[u32](u16_at(data, at))
        unicode :: platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10))
        if !unicode || at >= data.count {
            continue
        }
        if format == 12 || (format == 4 && font.cmap_format != 12) {
            font.cmap_at = at
            font.cmap_format = format
        }
    }
}

/**
 * Find a code point's glyph.
 *
 * @param font The font.
 * @param point A Unicode code point.
 * @return Its glyph's index; 0, the missing glyph, if the font hasn't one for it.
 */
glyph_index :: fn(font: ptr[Font], point: u32) -> u32 {
    data :: font.data
    at :: font.cmap_at
    if font.cmap_format == 12 {
        groups :: cast[usize](u32_at(data, at + 12))
        low := cast[usize](0)
        high := groups
        loop {
            middle :: (low + high) / 2
            group :: at + 16 + 12 * middle
            start :: u32_at(data, group)
            end :: u32_at(data, group + 4)
            if point < start {
                high = middle
            }
            else if point > end {
                low = middle + 1
            }
            else {
                glyph :: u32_at(data, group + 8) + (point - start)
                return if glyph < font.glyph_count { glyph } else { cast[u32](0) }
            }
        }
        while low < high
        return 0
    }
    if font.cmap_format != 4 || point > 0xffff {
        return 0
    }
    segments_twice :: cast[usize](u16_at(data, at + 6))
    ends :: at + 14
    starts :: ends + segments_twice + 2
    deltas :: starts + segments_twice
    ranges :: deltas + segments_twice
    for i in cast[usize](0)..<segments_twice / 2 {
        end :: cast[u32](u16_at(data, ends + 2 * i))
        if end < point {
            continue
        }
        start :: cast[u32](u16_at(data, starts + 2 * i))
        if start > point {
            return 0
        }
        delta :: cast[u32](u16_at(data, deltas + 2 * i))
        range :: cast[usize](u16_at(data, ranges + 2 * i))
        if range == 0 {
            return (point + delta) & 0xffff
        }
        glyph :: cast[u32](u16_at(data, ranges + 2 * i + range + 2 * cast[usize](point - start)))
        return if glyph == 0 { cast[u32](0) } else { (glyph + delta) & 0xffff }
    }
    return 0
}

/**
 * A glyph's advance: how far the pen moves after it.
 *
 * @param font The font.
 * @param glyph The glyph's index.
 * @return The advance, in design units.
 */
advance :: fn(font: ptr[Font], glyph: u32) -> i32 {
    index :: if glyph < font.hmetric_count { glyph } else { font.hmetric_count - 1 }
    return cast[i32](u16_at(font.data, font.hmtx.at + 4 * cast[usize](index)))
}

/** Where a glyph's data is in glyf: its offset and size; size 0 for an empty glyph, as a space. */
glyph_place :: fn(font: ptr[Font], glyph: u32) -> Table {
    if glyph >= font.glyph_count {
        return Table.{}
    }
    index :: cast[usize](glyph)
    start := cast[usize](0)
    end := cast[usize](0)
    if font.long_loca {
        start = cast[usize](u32_at(font.data, font.loca.at + 4 * index))
        end = cast[usize](u32_at(font.data, font.loca.at + 4 * index + 4))
    }
    else {
        start = 2 * cast[usize](u16_at(font.data, font.loca.at + 2 * index))
        end = 2 * cast[usize](u16_at(font.data, font.loca.at + 2 * index + 2))
    }
    if end <= start || end > font.glyf.size {
        return Table.{}
    }
    return Table.{at = font.glyf.at + start, size = end - start}
}

/** Empty an outline, for the next glyph. */
clear :: fn(outline: ptr[mut Outline]) {
    runtime.array_reset(&outline.verbs)
    runtime.array_reset(&outline.points)
}

/** Give back an outline's arrays. */
free_outline :: fn(outline: ptr[mut Outline]) {
    runtime.array_free(&outline.verbs)
    runtime.array_free(&outline.points)
    runtime.array_free(&outline.flags)
    runtime.array_free(&outline.xs)
    runtime.array_free(&outline.ys)
}

/**
 * A glyph's outline, added to an outline: its contours, each a Move, then Lines and Quads, then Close.
 *
 * @param font The font.
 * @param glyph The glyph's index.
 * @param outline Where its contours are added, in design units, y up.
 * @return False if the glyph's data couldn't be read whole; what was read is kept.
 */
glyph_outline :: fn(font: ptr[Font], glyph: u32, outline: ptr[mut Outline]) -> bool {
    return outline_of(font, glyph, outline, Transform.{}, 0)
}

/** A glyph's outline, its points transformed, followed into a composite's components to a depth. */
outline_of :: fn(font: ptr[Font], glyph: u32, outline: ptr[mut Outline], transform: Transform, depth: usize) -> bool {
    place :: glyph_place(font, glyph)
    if place.size == 0 {
        return true
    }
    data :: font.data
    contours :: i16_at(data, place.at)
    if contours >= 0 {
        return simple_outline(font, place, cast[usize](contours), outline, transform)
    }
    if depth >= MAX_COMPOSITE_DEPTH {
        return false
    }
    // A composite: its components, each a glyph placed by its own transform
    at := place.at + 10
    end :: place.at + place.size
    loop {
        if at + 4 > end {
            return false
        }
        flags :: u16_at(data, at)
        component :: cast[u32](u16_at(data, at + 2))
        at += 4
        dx := cast[f32](0)
        dy := cast[f32](0)
        if flags & 0x0001 != 0 {
            if flags & 0x0002 != 0 {
                dx = cast[f32](i16_at(data, at))
                dy = cast[f32](i16_at(data, at + 2))
            }
            at += 4
        }
        else {
            if flags & 0x0002 != 0 {
                dx = cast[f32](bit_cast[i8](u8_at(data, at)))
                dy = cast[f32](bit_cast[i8](u8_at(data, at + 1)))
            }
            at += 2
        }
        placed := Transform.{e = dx, f = dy}
        if flags & 0x0008 != 0 {
            scale :: f2dot14(i16_at(data, at))
            placed.a = scale
            placed.d = scale
            at += 2
        }
        else if flags & 0x0040 != 0 {
            placed.a = f2dot14(i16_at(data, at))
            placed.d = f2dot14(i16_at(data, at + 2))
            at += 4
        }
        else if flags & 0x0080 != 0 {
            placed.a = f2dot14(i16_at(data, at))
            placed.b = f2dot14(i16_at(data, at + 2))
            placed.c = f2dot14(i16_at(data, at + 4))
            placed.d = f2dot14(i16_at(data, at + 6))
            at += 8
        }
        if !outline_of(font, component, outline, then(placed, transform), depth + 1) {
            return false
        }
        if flags & 0x0020 == 0 {
            break
        }
    }
    while true
    return true
}

/** A 2.14 fixed-point number as a float. */
f2dot14 :: fn(value: i16) -> f32 {
    return cast[f32](value) / 16384
}

/** One transform, then another: inner applied first. */
then :: fn(inner: Transform, outer: Transform) -> Transform {
    return Transform.{a = outer.a * inner.a + outer.c * inner.b, b = outer.b * inner.a + outer.d * inner.b,
        c = outer.a * inner.c + outer.c * inner.d, d = outer.b * inner.c + outer.d * inner.d,
        e = outer.a * inner.e + outer.c * inner.f + outer.e, f = outer.b * inner.e + outer.d * inner.f + outer.f}
}

/** A point transformed. */
apply :: fn(transform: Transform, x: f32, y: f32) -> Point {
    return Point.{x = transform.a * x + transform.c * y + transform.e, y = transform.b * x + transform.d * y + transform.f}
}

/** A simple glyph's contours: its points read, then each contour's on- and off-curve points made lines and curves. */
simple_outline :: fn(font: ptr[Font], place: Table, contours: usize, outline: ptr[mut Outline], transform: Transform) -> bool {
    data :: font.data
    end :: place.at + place.size
    ends_at :: place.at + 10
    if contours == 0 {
        return true
    }
    count :: cast[usize](u16_at(data, ends_at + 2 * (contours - 1))) + 1
    instructions :: cast[usize](u16_at(data, ends_at + 2 * contours))
    at := ends_at + 2 * contours + 2 + instructions
    if at > end || count > 0xffff {
        return false
    }
    // Flags, each with a repeat count
    runtime.array_reset(&outline.flags)
    loop {
        if at >= end {
            return false
        }
        flag :: u8_at(data, at)
        at += 1
        runtime.array_add(&outline.flags, flag)
        if flag & 0x08 != 0 {
            repeats :: u8_at(data, at)
            at += 1
            for r in cast[u8](0)..<repeats {
                runtime.array_add(&outline.flags, flag)
            }
        }
    }
    while outline.flags.count < count
    // Coordinates, each relative to the last, a byte or a word or the same
    runtime.array_reset(&outline.xs)
    runtime.array_reset(&outline.ys)
    x := cast[i32](0)
    for i in cast[usize](0)..<count {
        flag :: if i < outline.flags.count { outline.flags[i] } else { cast[u8](0) }
        if flag & 0x02 != 0 {
            delta :: cast[i32](u8_at(data, at))
            at += 1
            x += if flag & 0x10 != 0 { delta } else { -delta }
        }
        else if flag & 0x10 == 0 {
            x += cast[i32](i16_at(data, at))
            at += 2
        }
        runtime.array_add(&outline.xs, x)
    }
    y := cast[i32](0)
    for i in cast[usize](0)..<count {
        flag :: if i < outline.flags.count { outline.flags[i] } else { cast[u8](0) }
        if flag & 0x04 != 0 {
            delta :: cast[i32](u8_at(data, at))
            at += 1
            y += if flag & 0x20 != 0 { delta } else { -delta }
        }
        else if flag & 0x20 == 0 {
            y += cast[i32](i16_at(data, at))
            at += 2
        }
        runtime.array_add(&outline.ys, y)
    }
    if at > end {
        return false
    }
    // Each contour
    first := cast[usize](0)
    for c in cast[usize](0)..<contours {
        last :: cast[usize](u16_at(data, ends_at + 2 * c))
        if last < first || last >= count {
            return false
        }
        emit_contour(outline, first, last, transform)
        first = last + 1
    }
    return true
}

/** One of a simple glyph's points, transformed, and whether it's on the curve. */
point_of :: fn(outline: ptr[Outline], index: usize, transform: Transform) -> Point {
    x :: if index < outline.xs.count { outline.xs[index] } else { cast[i32](0) }
    y :: if index < outline.ys.count { outline.ys[index] } else { cast[i32](0) }
    return apply(transform, cast[f32](x), cast[f32](y))
}

/** Whether one of a simple glyph's points is on the curve. */
on_curve :: fn(outline: ptr[Outline], index: usize) -> bool {
    return index < outline.flags.count && outline.flags[index] & 0x01 != 0
}

/** The point halfway between two. */
middle :: fn(p: Point, q: Point) -> Point {
    return Point.{x = (p.x + q.x) / 2, y = (p.y + q.y) / 2}
}

/**
 * A contour's points, first to last, made a Move, Lines and Quads and a Close: two off-curve points in a row have an
 * on-curve point implied halfway between them, as TrueType's quadratic B-splines do.
 */
emit_contour :: fn(outline: ptr[mut Outline], first: usize, last: usize, transform: Transform) {
    n :: last - first + 1
    // Where to start: an on-curve point, or, if there's none, halfway between the last and the first
    start_index := n
    for i in cast[usize](0)..<n {
        if start_index == n && on_curve(outline, first + i) {
            start_index = i
        }
    }
    start :: if start_index < n { point_of(outline, first + start_index, transform) }
        else { middle(point_of(outline, last, transform), point_of(outline, first, transform)) }
    runtime.array_add(&outline.verbs, Verb.Move)
    runtime.array_add(&outline.points, start)
    pending := false
    control := start
    // Every point after the start, around to it again
    steps :: if start_index < n { n } else { n + 1 }
    for step in cast[usize](1)..<steps + 1 {
        is_end :: step == steps
        index :: if start_index < n { (start_index + step) % n } else { (step - 1) % n }
        point :: if is_end { start } else { point_of(outline, first + index, transform) }
        on :: is_end || on_curve(outline, first + index)
        if on {
            if pending {
                runtime.array_add(&outline.verbs, Verb.Quad)
                runtime.array_add(&outline.points, control)
                runtime.array_add(&outline.points, point)
            }
            else {
                runtime.array_add(&outline.verbs, Verb.Line)
                runtime.array_add(&outline.points, point)
            }
            pending = false
        }
        else {
            if pending {
                halfway :: middle(control, point)
                runtime.array_add(&outline.verbs, Verb.Quad)
                runtime.array_add(&outline.points, control)
                runtime.array_add(&outline.points, halfway)
            }
            control = point
            pending = true
        }
    }
    runtime.array_add(&outline.verbs, Verb.Close)
}
