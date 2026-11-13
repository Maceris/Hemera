package fonts

import intrinsics from "base"

/*
 * Pair kerning: GPOS's pair adjustment lookups (type 2, or type 9 extending one) under any script's kern feature, a
 * pair's first glyph's x advance adjusted; or, for a font without them, the kern table's format 0 pairs.
 */

/** Find GPOS's pair-adjustment subtables of its kern features, for kerning. */
find_pair_kerning :: fn(font: ptr[mut Font]) {
    data :: font.data
    gpos :: find_table(data, "GPOS")
    if gpos.size < 10 {
        return void
    }
    features :: gpos.at + cast[usize](u16_at(data, gpos.at + 6))
    lookups :: gpos.at + cast[usize](u16_at(data, gpos.at + 8))
    lookup_count :: cast[usize](u16_at(data, lookups))
    // Each lookup a kern feature names, once
    seen : bool[512]
    feature_count :: cast[usize](u16_at(data, features))
    for f in cast[usize](0)..<feature_count {
        record :: features + 2 + 6 * f
        if u32_at(data, record) != tag("kern") {
            continue
        }
        feature :: features + cast[usize](u16_at(data, record + 4))
        indices :: cast[usize](u16_at(data, feature + 2))
        for i in cast[usize](0)..<indices {
            index :: cast[usize](u16_at(data, feature + 4 + 2 * i))
            if index >= lookup_count || index >= seen.count || seen[index] {
                continue
            }
            seen[index] = true
            add_lookup(font, lookups + cast[usize](u16_at(data, lookups + 2 + 2 * index)))
        }
    }
}

/** Add a lookup's pair-adjustment subtables, following extension subtables to theirs. */
add_lookup :: fn(font: ptr[mut Font], lookup: usize) {
    data :: font.data
    kind :: u16_at(data, lookup)
    if kind != 2 && kind != 9 {
        return void
    }
    count :: cast[usize](u16_at(data, lookup + 4))
    for s in cast[usize](0)..<count {
        subtable := lookup + cast[usize](u16_at(data, lookup + 6 + 2 * s))
        if kind == 9 {
            if u16_at(data, subtable + 2) != 2 {
                continue
            }
            subtable += cast[usize](u32_at(data, subtable + 4))
        }
        if subtable < data.count && font.pair_count < font.pairs.count {
            font.pairs[font.pair_count] = cast[u32](subtable)
            font.pair_count += 1
        }
    }
}

/**
 * The kerning between two glyphs: what's added to the first's advance when the second follows it.
 *
 * @param font The font.
 * @param left The first glyph.
 * @param right The glyph after it.
 * @return The adjustment, in design units; usually negative or 0.
 */
kerning :: fn(font: ptr[Font], left: u32, right: u32) -> i32 {
    for i in cast[usize](0)..<font.pair_count {
        if i < font.pairs.count {
            match pair_adjustment(font, cast[usize](font.pairs[i]), left, right) {
                case Some(value) => return value
                case None => {}
            }
        }
    }
    if font.pair_count == 0 && font.kern.size > 0 {
        return kern_table(font, left, right)
    }
    return 0
}

/** A pair-adjustment subtable's x advance for a pair; null if it doesn't cover the pair. */
pair_adjustment :: fn(font: ptr[Font], subtable: usize, left: u32, right: u32) -> i32? {
    data :: font.data
    format :: u16_at(data, subtable)
    covered :: coverage_index(data, subtable + cast[usize](u16_at(data, subtable + 2)), left) or_return null
    first_format :: u16_at(data, subtable + 4)
    second_format :: u16_at(data, subtable + 6)
    first_size :: 2 * cast[usize](intrinsics.count_ones(first_format))
    second_size :: 2 * cast[usize](intrinsics.count_ones(second_format))
    // The x advance's place in the first value record, after x and y placement if they're there
    advance_at :: 2 * cast[usize](intrinsics.count_ones(first_format & 0x0003))
    has_advance :: first_format & 0x0004 != 0
    if format == 1 {
        set :: subtable + cast[usize](u16_at(data, subtable + 10 + 2 * covered))
        count :: cast[usize](u16_at(data, set))
        record_size :: 2 + first_size + second_size
        low := cast[usize](0)
        high := count
        loop {
            middle :: (low + high) / 2
            record :: set + 2 + record_size * middle
            second :: cast[u32](u16_at(data, record))
            if right < second {
                high = middle
            }
            else if right > second {
                low = middle + 1
            }
            else {
                return if has_advance { cast[i32](i16_at(data, record + 2 + advance_at)) } else { cast[i32](0) }
            }
        }
        while low < high
        return null
    }
    if format == 2 {
        first_class :: class_of(data, subtable + cast[usize](u16_at(data, subtable + 8)), left)
        second_class :: class_of(data, subtable + cast[usize](u16_at(data, subtable + 10)), right)
        first_count :: cast[usize](u16_at(data, subtable + 12))
        second_count :: cast[usize](u16_at(data, subtable + 14))
        if first_class >= first_count || second_class >= second_count {
            return null
        }
        record :: subtable + 16 + (first_class * second_count + second_class) * (first_size + second_size)
        return if has_advance { cast[i32](i16_at(data, record + advance_at)) } else { cast[i32](0) }
    }
    return null
}

/** A glyph's index in a coverage table (format 1, a list, or 2, ranges); null if it isn't covered. */
coverage_index :: fn(data: u8[], coverage: usize, glyph: u32) -> usize? {
    format :: u16_at(data, coverage)
    count :: cast[usize](u16_at(data, coverage + 2))
    low := cast[usize](0)
    high := count
    if format == 1 {
        loop {
            middle :: (low + high) / 2
            found :: cast[u32](u16_at(data, coverage + 4 + 2 * middle))
            if glyph < found {
                high = middle
            }
            else if glyph > found {
                low = middle + 1
            }
            else {
                return middle
            }
        }
        while low < high
        return null
    }
    if format == 2 {
        loop {
            middle :: (low + high) / 2
            range :: coverage + 4 + 6 * middle
            start :: cast[u32](u16_at(data, range))
            end :: cast[u32](u16_at(data, range + 2))
            if glyph < start {
                high = middle
            }
            else if glyph > end {
                low = middle + 1
            }
            else {
                return cast[usize](u16_at(data, range + 4)) + cast[usize](glyph - start)
            }
        }
        while low < high
    }
    return null
}

/** A glyph's class in a class definition (format 1, a run, or 2, ranges); 0 for one it doesn't list. */
class_of :: fn(data: u8[], definition: usize, glyph: u32) -> usize {
    format :: u16_at(data, definition)
    if format == 1 {
        start :: cast[u32](u16_at(data, definition + 2))
        count :: cast[u32](u16_at(data, definition + 4))
        if glyph < start || glyph - start >= count {
            return 0
        }
        return cast[usize](u16_at(data, definition + 6 + 2 * cast[usize](glyph - start)))
    }
    if format == 2 {
        count :: cast[usize](u16_at(data, definition + 2))
        low := cast[usize](0)
        high := count
        loop {
            middle :: (low + high) / 2
            range :: definition + 4 + 6 * middle
            start :: cast[u32](u16_at(data, range))
            end :: cast[u32](u16_at(data, range + 2))
            if glyph < start {
                high = middle
            }
            else if glyph > end {
                low = middle + 1
            }
            else {
                return cast[usize](u16_at(data, range + 4))
            }
        }
        while low < high
    }
    return 0
}

/** The kern table's adjustment for a pair, from its first horizontal format 0 subtable. */
kern_table :: fn(font: ptr[Font], left: u32, right: u32) -> i32 {
    data :: font.data
    at :: font.kern.at
    if u16_at(data, at) != 0 || u16_at(data, at + 2) == 0 {
        return 0
    }
    subtable :: at + 4
    coverage :: u16_at(data, subtable + 4)
    if coverage >> 8 != 0 || coverage & 0x0001 == 0 {
        return 0
    }
    count :: cast[usize](u16_at(data, subtable + 6))
    wanted :: (left << 16) | right
    low := cast[usize](0)
    high := count
    loop {
        middle :: (low + high) / 2
        pair :: subtable + 14 + 6 * middle
        found :: u32_at(data, pair)
        if wanted < found {
            high = middle
        }
        else if wanted > found {
            low = middle + 1
        }
        else {
            return cast[i32](i16_at(data, pair + 4))
        }
    }
    while low < high
    return 0
}
