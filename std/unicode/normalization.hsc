package unicode

/*
 * Normalization (UAX #15) and case folding, from tables generated from the Unicode Character Database
 * (normalization_tables.hsc, by _generator/generate_normalization.py). Nothing allocates: the caller gives the room,
 * code points to work in and bytes to write to, sized from the text (SCRATCH_PER_BYTE, OUTPUT_PER_BYTE).
 *
 *     scratch : u32[256]
 *     out : u8[192]
 *     count := unicode.normalize(name, .NFC, scratch[0..<scratch.count], out[0..<out.count]) or_else 0
 *
 * Two texts match without regard to case or to how their accents were written when they're the same once each is
 * decomposed (NFD), case folded, and decomposed again: canonical caseless matching (the Unicode Standard, 3.13).
 */

/** A normalization form. */
Form :: enum {
    /** Canonical decomposition: every character decomposed, as far as it goes, and its marks in canonical order. */
    NFD,
    /** Canonical composition: NFD, then each starter and what follows it composed again where they compose. */
    NFC,
}

/** How many code points of scratch room normalize and case_fold need for each byte of text, at most. */
SCRATCH_PER_BYTE :: LONGEST_DECOMPOSITION
/** How many bytes of output normalize and case_fold write for each byte of text, at most. */
OUTPUT_PER_BYTE :: 3

// Hangul syllables, decomposed and composed by arithmetic (the Unicode Standard, 3.12)
/** The first precomposed syllable. */
HANGUL_S_BASE : u32 : 0xac00
/** The first leading consonant. */
HANGUL_L_BASE : u32 : 0x1100
/** The first vowel. */
HANGUL_V_BASE : u32 : 0x1161
/** One before the first trailing consonant. */
HANGUL_T_BASE : u32 : 0x11a7
/** How many leading consonants there are. */
HANGUL_L_COUNT : u32 : 19
/** How many vowels. */
HANGUL_V_COUNT : u32 : 21
/** How many trailing consonants, none counted. */
HANGUL_T_COUNT : u32 : 28
/** How many syllables share a leading consonant: vowels times trailing consonants. */
HANGUL_N_COUNT : u32 : 588
/** How many precomposed syllables there are. */
HANGUL_S_COUNT : u32 : 11172

/**
 * Find a code point's canonical combining class.
 *
 * @param point The code point; one past U+10FFFF is a starter.
 * @return Its class: 0 for a starter, which nothing reorders past.
 */
combining_class :: fn(point: u32) -> u8 {
    low := cast[usize](0)
    high := CLASS_STARTS.count
    // The last run that starts at or before point
    loop {
        if high - low <= 1 {
            break
        }
        middle :: low + (high - low) / 2
        if middle >= CLASS_STARTS.count {
            break
        }
        if CLASS_STARTS[middle] <= point {
            low = middle
        }
        else {
            high = middle
        }
    }
    found :: low
    if found >= CLASS_VALUES.count {
        return 0
    }
    return CLASS_VALUES[found]
}

/**
 * Write a code point's canonical decomposition, whole: a Hangul syllable's worked out, any other's from the tables, or
 * the code point itself if it doesn't decompose.
 *
 * @param point The code point.
 * @param into Where it's written, from the start: LONGEST_DECOMPOSITION code points are always room enough.
 * @return How many code points were written: 1 to LONGEST_DECOMPOSITION; 0 if into hasn't room for them.
 */
decompose :: fn(point: u32, into: mut u32[]) -> usize {
    if point >= HANGUL_S_BASE && point < HANGUL_S_BASE + HANGUL_S_COUNT {
        index :: point - HANGUL_S_BASE
        trailing :: index % HANGUL_T_COUNT
        if into.count < 2 || (trailing != 0 && into.count < 3) {
            return 0
        }
        into[0] = HANGUL_L_BASE + index / HANGUL_N_COUNT
        into[1] = HANGUL_V_BASE + index % HANGUL_N_COUNT / HANGUL_T_COUNT
        if trailing == 0 {
            return 2
        }
        if into.count < 3 {
            return 0
        }
        into[2] = HANGUL_T_BASE + trailing
        return 3
    }
    match index_of(DECOMPOSED[0..<DECOMPOSED.count], point) {
        case Some(at) => return copied(DECOMPOSITION_STARTS[0..<DECOMPOSITION_STARTS.count], DECOMPOSITIONS[0..<DECOMPOSITIONS.count], at, into)
        case None => {}
    }
    if into.count == 0 {
        return 0
    }
    into[0] = point
    return 1
}

/**
 * Find what two code points compose into, canonically: a Hangul leading consonant and vowel, or syllable and trailing
 * consonant, worked out; any other pair from the tables, those excluded from composition left out.
 *
 * @param first The first code point, a starter.
 * @param second The one that follows it.
 * @return The composite; null if they don't compose.
 */
compose :: fn(first: u32, second: u32) -> u32? {
    if first >= HANGUL_L_BASE && first < HANGUL_L_BASE + HANGUL_L_COUNT && second >= HANGUL_V_BASE
        && second < HANGUL_V_BASE + HANGUL_V_COUNT {
        return HANGUL_S_BASE + ((first - HANGUL_L_BASE) * HANGUL_V_COUNT + (second - HANGUL_V_BASE)) * HANGUL_T_COUNT
    }
    if first >= HANGUL_S_BASE && first < HANGUL_S_BASE + HANGUL_S_COUNT && (first - HANGUL_S_BASE) % HANGUL_T_COUNT == 0
        && second > HANGUL_T_BASE && second < HANGUL_T_BASE + HANGUL_T_COUNT {
        return first + (second - HANGUL_T_BASE)
    }
    key :: (cast[u64](first) << 21) | cast[u64](second)
    low := cast[usize](0)
    high := COMPOSED_PAIRS.count
    loop {
        if low >= high {
            return null
        }
        middle :: low + (high - low) / 2
        if middle >= COMPOSED_PAIRS.count || middle >= COMPOSITES.count {
            return null
        }
        found :: COMPOSED_PAIRS[middle]
        if found == key {
            return COMPOSITES[middle]
        }
        if found < key {
            low = middle + 1
        }
        else {
            high = middle
        }
    }
}

/**
 * Write a code point's full case folding (CaseFolding.txt's statuses C and F): what it's compared as when case doesn't
 * matter, like ß's ss.
 *
 * @param point The code point.
 * @param into Where it's written, from the start: 3 code points are always room enough.
 * @return How many code points were written, 1 to 3, the code point itself if folding doesn't change it; 0 if into
 *     hasn't room.
 */
fold :: fn(point: u32, into: mut u32[]) -> usize {
    match index_of(FOLDED[0..<FOLDED.count], point) {
        case Some(at) => return copied(FOLDING_STARTS[0..<FOLDING_STARTS.count], FOLDINGS[0..<FOLDINGS.count], at, into)
        case None => {}
    }
    if into.count == 0 {
        return 0
    }
    into[0] = point
    return 1
}

/**
 * Normalize UTF-8 text to a form.
 *
 * @param text The text; bytes that aren't UTF-8 are taken as U+FFFD, as decode takes them.
 * @param form NFD or NFC.
 * @param scratch Room to work in: SCRATCH_PER_BYTE code points for each byte of text is always enough.
 * @param into Where the normalized text is written, UTF-8, from the start: OUTPUT_PER_BYTE bytes for each byte of
 *     text is always enough.
 * @return How many bytes of into were written; null if scratch or into hasn't room, when into holds part of it.
 */
normalize :: fn(text: u8[], form: Form, scratch: mut u32[], into: mut u8[]) -> usize? {
    count :: decomposed(text, scratch) or_return null
    if count > scratch.count {
        return null
    }
    order(scratch[0..<count])
    if form == .NFD {
        return encoded(scratch[0..<count], into)
    }
    kept :: composed(scratch[0..<count])
    if kept > scratch.count {
        return null
    }
    return encoded(scratch[0..<kept], into)
}

/**
 * Case fold UTF-8 text, fully: each code point replaced by its folding (fold). For matching without regard to case
 * or accents' forms, decompose (NFD) before and after.
 *
 * @param text The text; bytes that aren't UTF-8 are taken as U+FFFD.
 * @param scratch Room to work in: SCRATCH_PER_BYTE code points for each byte of text is always enough.
 * @param into Where the folded text is written, UTF-8, from the start: OUTPUT_PER_BYTE bytes for each byte of text is
 *     always enough.
 * @return How many bytes of into were written; null if scratch or into hasn't room.
 */
case_fold :: fn(text: u8[], scratch: mut u32[], into: mut u8[]) -> usize? {
    count := cast[usize](0)
    at := cast[usize](0)
    loop {
        if at >= text.count {
            break
        }
        point, length :: next_point(text, at)
        at += length
        from :: count
        if from > scratch.count {
            return null
        }
        written :: fold(point, scratch[from..<scratch.count])
        if written == 0 {
            return null
        }
        count += written
    }
    if count > scratch.count {
        return null
    }
    return encoded(scratch[0..<count], into)
}

/**
 * Decompose text's code points, each whole, into scratch.
 *
 * @param text The UTF-8 text.
 * @param scratch Where the code points go, from the start.
 * @return How many there are; null if scratch hasn't room.
 */
decomposed :: fn(text: u8[], scratch: mut u32[]) -> usize? {
    count := cast[usize](0)
    at := cast[usize](0)
    loop {
        if at >= text.count {
            return count
        }
        point, length :: next_point(text, at)
        at += length
        from :: count
        if from > scratch.count {
            return null
        }
        written :: decompose(point, scratch[from..<scratch.count])
        if written == 0 {
            return null
        }
        count += written
    }
}

/**
 * Put each run of marks in canonical order: by their combining classes, those of one class kept in the order they
 * came; a starter (class 0) never moves, and nothing moves past one.
 *
 * @param points The code points, reordered in place.
 */
order :: fn(points: mut u32[]) {
    for i in 1..<points.count {
        class :: combining_class(points[i])
        if class == 0 {
            continue
        }
        j := i
        loop {
            if j == 0 || j >= points.count {
                break
            }
            before :: points[j - 1]
            if combining_class(before) <= class {
                break
            }
            points[j - 1] = points[j]
            points[j] = before
            j -= 1
        }
    }
}

/**
 * Compose decomposed, canonically ordered code points again (UAX #15's canonical composition): each one composes with
 * the starter before it unless something between them is a starter or has a class as high as its own.
 *
 * @param points The code points, in NFD; composed in place, from the start.
 * @return How many code points are left, from the start.
 */
composed :: fn(points: mut u32[]) -> usize {
    if points.count == 0 {
        return 0
    }
    NONE :: ~cast[usize](0)
    starter := if combining_class(points[0]) == 0 { cast[usize](0) } else { NONE }
    // A mark before the first starter blocks it: 256 is past every class
    last_class := if starter == NONE { cast[u32](256) } else { cast[u32](0) }
    kept := cast[usize](1)
    for i in 1..<points.count {
        point :: points[i]
        class :: cast[u32](combining_class(point))
        if starter < kept && starter < points.count && (last_class < class || last_class == 0) {
            match compose(points[starter], point) {
                case Some(composite) => {
                    points[starter] = composite
                    continue
                }
                case None => {}
            }
        }
        if class == 0 {
            starter = kept
        }
        last_class = class
        if kept < points.count {
            points[kept] = point
        }
        kept += 1
    }
    return kept
}

/**
 * Encode code points as UTF-8.
 *
 * @param points The code points.
 * @param into Where the bytes go, from the start.
 * @return How many bytes were written; null if into hasn't room for them all.
 */
encoded :: fn(points: u32[], into: mut u8[]) -> usize? {
    written := cast[usize](0)
    for point in points {
        from :: written
        if from > into.count {
            return null
        }
        count :: encode(point, into[from..<into.count])
        if count == 0 {
            return null
        }
        written += count
    }
    return written
}

/**
 * Read the code point at a place in UTF-8 text, as decode does, but U+FFFD for a byte that isn't UTF-8's.
 *
 * @param text The text.
 * @param at Where, before its end.
 * @return point The code point.
 * @return length How many bytes it took: at least 1.
 */
next_point :: fn(text: u8[], at: usize) -> (point: u32, length: usize) {
    point, length :: decode(text, at)
    if length == 0 {
        return 0xfffd, 1
    }
    return point, length
}

/**
 * Copy one of a table's entries, its code points, out: a decomposition's or a folding's.
 *
 * @param starts Where each entry starts in data, and, last, where the last ends.
 * @param data The entries, one after another.
 * @param at The entry's index.
 * @param into Where its code points go, from the start.
 * @return How many were copied; 0 for an index past the table's, or into without room.
 */
copied :: fn(starts: u16[], data: u32[], at: usize, into: mut u32[]) -> usize {
    if at >= starts.count {
        return 0
    }
    after :: at + 1
    if after >= starts.count {
        return 0
    }
    start :: cast[usize](starts[at])
    end :: cast[usize](starts[after])
    if start > end || end > data.count || end - start > into.count {
        return 0
    }
    for i in start..<end {
        place :: i - start
        if i < data.count && place < into.count {
            into[place] = data[i]
        }
    }
    return end - start
}

/**
 * Find a code point among sorted ones, by binary search.
 *
 * @param points The code points, ascending.
 * @param point The one looked for.
 * @return Its index; null if it isn't there.
 */
index_of :: fn(points: u32[], point: u32) -> usize? {
    low := cast[usize](0)
    high := points.count
    loop {
        if low >= high {
            return null
        }
        middle :: low + (high - low) / 2
        if middle >= points.count {
            return null
        }
        found :: points[middle]
        if found == point {
            return middle
        }
        if found < point {
            low = middle + 1
        }
        else {
            high = middle
        }
    }
}
