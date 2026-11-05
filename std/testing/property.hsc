package testing

import runtime from "base"
import compiler from "base"
import reflection from "std"
import text_buffer from "std"

/*
 * Property tests (docs/testing.md, Property Tests): a test that takes a Source as well as its T, and draws its inputs
 * from it, run on many cases. A case is the bytes its draws read: fresh random ones while it runs, and when it fails,
 * the same bytes again, made as small as they can be while it still fails, so the case reported is a small one. Every
 * draw reads bytes so that fewer and lower bytes give smaller values, and zeros give the smallest, which is what makes
 * shrinking the bytes shrink the values, whatever drew them. std/fuzzing gives the same tests bytes of its own.
 */

/** How many cases a property test draws when its runner isn't told (RunOptions.runs). */
DEFAULT_RUNS :: 100

/**
 * The most bytes one case's draws read; past these, every draw reads zeros, so a case can't grow without end. A case
 * is kept in fixed space, as Case, so this is what it takes on the stack, several times over while one is shrunk.
 */
MAX_CASE_BYTES :: 1024

/** The most times a failing case is run again while it's made smaller; past these, the smallest found is reported. */
SHRINK_RUNS :: 2000

/**
 * A property test: a #test function that takes a Source as well, and draws its inputs from it, which a runner calls on
 * case after case (check_property). It can't keep the source, or what draw_bytes gives, past its return.
 */
Property :: alias fn(t: ptr[mut T], source: ptr[mut Source]) -> Outcome

/** A case's bytes, in fixed space. */
Case :: struct {
    /** The bytes; the first count are the case's. */
    bytes : u8[MAX_CASE_BYTES],
    /** How many of bytes are the case's, 0 to MAX_CASE_BYTES. */
    count : usize,
}

/**
 * Give a case's bytes.
 *
 * @param found The case, only read.
 * @return Its bytes, a view of its own, good while it's unchanged.
 */
case_bytes :: fn(found: ptr[Case]) -> u8[] {
    if found.count <= found.bytes.count {
        return found.bytes[0..<found.count]
    }
    return found.bytes[0..<found.bytes.count]
}

/**
 * Where a property test's draws come from: a case's bytes, read in order, in room its runner gives.
 *
 * It's #scoped, as its room is usually on the runner's stack: a test has it only by pointer, for as long as the case
 * runs (docs/memory.md, Scoped Structs).
 */
Source :: struct #scoped {
    /**
     * Where the case's bytes are: the first count, given or read so far. Reading past them adds a byte after them,
     * a fresh random one while random is set and a zero otherwise, until the room is full; past that, reads give zeros.
     */
    room : mut u8[],
    /** How many of room's bytes are the case's. */
    count : usize,
    /** How many bytes have been read. */
    at : usize,
    /** While drawing fresh, the random generator's state (SplitMix64); null while replaying given bytes. */
    random : u64?,
    /** The values drawn so far, as a failure shows values, separated by ", ": what's added to each failure's notes. */
    shown : Text,
    /**
     * The name of the first type draw was asked for that it can't make, like a string or a pointer, which fails the
     * test; empty while there's none.
     */
    unsupported : Text,
    /** Where draw was asked for the type in unsupported. */
    unsupported_at : runtime.SourceCodeLocation,
}

/**
 * Make a source over room the caller gives.
 *
 * @param room Where the case's bytes are, the given ones first; it's written past them, and has to last as long as the
 *     source.
 * @param given How many of room's first bytes are the case's to replay; 0 to draw every byte fresh.
 * @param random The generator's state for fresh bytes, read after the given ones; null to read zeros instead.
 * @return The source.
 */
source_in :: fn(room: mut u8[], given: usize, random: u64?) -> Source {
    return Source.{room = room, count = if given > room.count { room.count } else { given }, random = random}
}

/**
 * Give the bytes a source's case has read so far: what it's been, for replaying it.
 *
 * @param source The source, only read.
 * @return A view of its room, good while the room is unchanged.
 */
read_bytes :: fn(source: ptr[Source]) -> u8[] {
    end :: if source.at < source.count { source.at } else { source.count }
    if end <= source.room.count {
        return source.room[0..<end]
    }
    return source.room[0..<source.room.count]
}

/**
 * Put bytes in a case, as many as fit.
 *
 * @param into The case, whose bytes and count are replaced.
 * @param bytes The bytes; past MAX_CASE_BYTES, they're cut.
 */
set_case :: fn(into: ptr[mut Case], bytes: u8[]) {
    into.count = 0
    for byte, i in bytes {
        if i >= into.bytes.count {
            break
        }
        into.bytes[i] = byte
        into.count = i + 1
    }
}

/**
 * Advance a SplitMix64 generator and give its next number.
 *
 * @param state The generator's state, advanced.
 * @return The next number, any u64.
 */
next_random :: fn(state: ptr[mut u64]) -> u64 {
    state^ += 0x9e3779b97f4a7c15
    mixed := state^
    mixed = (mixed ~ (mixed >> 30)) * 0xbf58476d1ce4e5b9
    mixed = (mixed ~ (mixed >> 27)) * 0x94d049bb133111eb
    return mixed ~ (mixed >> 31)
}

/**
 * Give a test's own seed, from its name, so each property test draws other cases, the same ones in every run.
 *
 * @param name The test's name.
 * @return Its FNV-1a hash.
 */
seed_of :: fn(name: string) -> u64 {
    hash : u64 = 0xcbf29ce484222325
    for character in name {
        hash = (hash ~ cast[u64](cast[u8](character))) * 0x100000001b3
    }
    return hash
}

/**
 * Read a byte: the next of the case's, or past them, a fresh random one, or a zero while replaying; either is kept.
 *
 * @param source The source, read.
 * @return The byte; 0 once the source's room is full.
 */
draw_byte :: fn(source: ptr[mut Source]) -> u8 {
    at :: source.at
    if at < source.count && at < source.room.count {
        given :: source.room[at]
        source.at = at + 1
        return given
    }
    count :: source.count
    if count >= source.room.count {
        return 0
    }
    byte : u8 = 0
    match source.random {
        case Some(state) => {
            next := state
            byte = cast[u8](next_random(&next) & 0xff)
            source.random = next
        }
        case None => {}
    }
    if count < source.room.count {
        source.room[count] = byte
    }
    source.count = count + 1
    source.at = count + 1
    return byte
}

/**
 * Read a number from bytes, most significant first, so lower bytes give a lower number.
 *
 * @param source The source, read.
 * @param count How many bytes, 0 to 8.
 * @return The number they make; 0 for none.
 */
draw_word :: fn(source: ptr[mut Source], count: usize) -> u64 {
    value : u64 = 0
    for index in 0..<count {
        value = (value << 8) | cast[u64](draw_byte(source))
    }
    return value
}

/**
 * Draw a number below a bound.
 *
 * @param source The source, read: as many bytes as bound - 1 takes.
 * @param bound One more than the largest number wanted; 0 and 1 give 0, reading nothing.
 * @return A number from 0 to bound - 1, lower for lower bytes; 0 for zeros.
 */
draw_below :: fn(source: ptr[mut Source], bound: u64) -> u64 {
    if bound <= 1 {
        return 0
    }
    count : usize = 0
    rest := bound - 1
    loop {
        if rest == 0 {
            break
        }
        count += 1
        rest = rest >> 8
    }
    // Scaled into the bound, rather than wrapped, so a lower word never gives a higher number
    word :: cast[u128](draw_word(source, count))
    return cast[u64]((word * cast[u128](bound)) >> cast[u128](count * 8))
}

/**
 * Draw a boolean.
 *
 * @param source The source, read: one byte.
 * @return Whether the byte is odd; false for a zero.
 */
draw_bool :: fn(source: ptr[mut Source]) -> bool {
    return (draw_byte(source) & 1) == 1
}

/**
 * Draw an integer between two, both included.
 *
 * @tparam V The integer type.
 * @param source The source, read.
 * @param low The least it can be.
 * @param high The most it can be; below low, low is given, reading nothing.
 * @return A number from low to high, nearer low for lower bytes; low for zeros.
 */
draw_between :: fn[V: compiler.Integer](source: ptr[mut Source], low: V, high: V) -> V {
    if high <= low {
        return low
    }
    span :: cast[u64](high - low)
    offset :: if span == ~cast[u64](0) { draw_word(source, 8) } else { draw_below(source, span + 1) }
    drawn :: low + cast[V](offset)
    show(source, drawn)
    return drawn
}

/**
 * Draw how many of something there are, for a test to draw that many itself.
 *
 * @param source The source, read.
 * @param most The most it can be.
 * @return A count from 0 to most, lower for lower bytes; 0 for zeros.
 */
draw_count :: fn(source: ptr[mut Source], most: usize) -> usize {
    return cast[usize](draw_below(source, cast[u64](most) + 1))
}

/**
 * Draw bytes: a count of them, then that many, as a fuzzer's input is.
 *
 * @param source The source, read: the count, then the bytes.
 * @param most The most bytes; their count is drawn from 0 to it.
 * @return The bytes, a view of the source's room, good until the case ends; fewer than drawn if the room filled.
 */
draw_bytes :: fn(source: ptr[mut Source], most: usize) -> u8[] {
    count :: draw_count(source, most)
    start :: source.at
    for index in 0..<count {
        _ = draw_byte(source)
    }
    end :: source.at
    if start >= end || end > source.count || end > source.room.count {
        return source.room[0..<0]
    }
    drawn :: source.room[start..<end]
    show(source, drawn)
    return drawn
}

/**
 * Draw any value of a type made of numbers, booleans, characters and enums: those alone, or in structs, fixed arrays,
 * vectors and unions, optionals among them. Integers and floats favor their edges (0, 1, the least and the most, and
 * for floats infinities and NaN) now and then, as bugs do.
 *
 * @tparam V The type. One holding a string, a pointer, a view, a dynamic array, an any or a function can't be drawn:
 *     that's recorded in the source, and fails the test; draw what it holds instead, and build it.
 * @param source The source, read.
 * @param location Where it's drawn, where a type that can't be is reported; the caller's own.
 * @return The value; all zeros for zero bytes, and for a type that can't be drawn.
 */
draw :: fn[V](source: ptr[mut Source], location := #caller_location) -> V {
    value : V
    if source.unsupported.count == 0 {
        source.unsupported_at = location
    }
    draw_into(source, type_info_of(V), cast[rawptr](&value))
    show(source, value)
    return value
}

/**
 * Add a value to what a source shows a failure, after those before it.
 *
 * @param source The source, whose shown grows, cut at TEXT_BYTES.
 * @param value The value.
 */
show :: fn(source: ptr[mut Source], value: any) {
    storage : u8[TEXT_BYTES]
    text := text_buffer.make(storage)
    text_buffer.append(&text, text_of(&source.shown))
    if source.shown.count > 0 {
        text_buffer.append(&text, ", ")
    }
    append_shown(&text, value)
    source.shown = text_from(text_buffer.as_string(&text))
}

/**
 * Write a number's low bytes where a value goes.
 *
 * @param at Where, size bytes, written.
 * @param size How many bytes: 1, 2, 4 or 8; others write nothing.
 * @param value The number, of which the low size bytes are written.
 */
store :: fn(at: rawptr, size: usize, value: u64) {
    switch size {
        case 1: cast[ptr[mut u8]](at)^ = cast[u8](value & 0xff)
        case 2: cast[ptr[mut u16]](at)^ = cast[u16](value & 0xffff)
        case 4: cast[ptr[mut u32]](at)^ = cast[u32](value & 0xffff_ffff)
        case 8: cast[ptr[mut u64]](at)^ = value
        case _: return void
    }
}

/**
 * Give where a value's part is, so far past where the value is.
 *
 * @param at Where the value is.
 * @param offset How far its part is, in bytes.
 * @return Where the part is.
 */
offset_by :: fn(at: rawptr, offset: usize) -> rawptr {
    return cast[rawptr](cast[uintptr](at) + cast[uintptr](offset))
}

/**
 * Draw an integer's bits: now and then an edge, a small one, and otherwise any.
 *
 * @param source The source, read: a byte saying which kind, then the number's.
 * @param size How many bytes the integer has, 1 to 8.
 * @param signed Whether it's signed, which decides its edges.
 * @return The bits, in the low size bytes; 0 for zeros.
 */
draw_integer_bits :: fn(source: ptr[mut Source], size: usize, signed: bool) -> u64 {
    bits :: if size >= 8 { cast[u64](64) } else { cast[u64](size) * 8 }
    all :: if bits >= 64 { ~cast[u64](0) } else { (cast[u64](1) << bits) - 1 }
    kind :: draw_byte(source)
    if kind < 160 {
        return draw_word(source, size) & all
    }
    if kind < 224 {
        small :: draw_word(source, 1)
        // Small either side of 0, for a signed one
        return if signed && small >= 128 { (small | ~cast[u64](0xff)) & all } else { small }
    }
    least :: if signed { cast[u64](1) << (bits - 1) } else { cast[u64](0) }
    most :: if signed { (cast[u64](1) << (bits - 1)) - 1 } else { all }
    edge :: (kind - 224) % 6
    switch edge {
        case 0: return least
        case 1: return most
        case 2: return (least + 1) & all
        case 3: return (most - 1) & all
        case 4: return 1
        case _: return if signed { all } else { cast[u64](2) }
    }
}

/**
 * Draw a float's bits: now and then a special one, and otherwise any.
 *
 * @param source The source, read: a byte saying which kind, then the number's.
 * @param size How many bytes the float has: 4 or 8, or 2, which only draws any bits.
 * @return The bits, in the low size bytes; 0, which is 0.0, for zeros.
 */
draw_float_bits :: fn(source: ptr[mut Source], size: usize) -> u64 {
    kind :: draw_byte(source)
    if kind < 192 || (size != 4 && size != 8) {
        return draw_word(source, size)
    }
    // 0.0, -0.0, 1.0, -1.0, infinity, -infinity, NaN, the least subnormal, the most finite
    single : u32[9] = u32.[0, 0x8000_0000, 0x3f80_0000, 0xbf80_0000, 0x7f80_0000, 0xff80_0000, 0x7fc0_0000, 1, 0x7f7f_ffff]
    double : u64[9] = u64.[0, 0x8000_0000_0000_0000, 0x3ff0_0000_0000_0000, 0xbff0_0000_0000_0000, 0x7ff0_0000_0000_0000,
        0xfff0_0000_0000_0000, 0x7ff8_0000_0000_0000, 1, 0x7fef_ffff_ffff_ffff]
    which :: cast[usize](kind - 192) % 9
    return if size == 4 { cast[u64](single[which]) } else { double[which] }
}

/**
 * Draw a value of a type into place, as draw does.
 *
 * @param source The source, read; its unsupported is set if the type, or a part of it, can't be drawn.
 * @param info The type.
 * @param at Where the value goes, info.size bytes, zeroed by the caller.
 */
draw_into :: fn(source: ptr[mut Source], info: ptr[compiler.TypeInfo], at: rawptr) {
    plain :: reflection.unaliased(info)
    switch plain.variant {
        case .VOID: return void
        case .BOOLEAN: { store(at, plain.size, if draw_bool(source) { cast[u64](1) } else { cast[u64](0) }) }
        case .INTEGER: {
            integer :: cast[ptr[compiler.TypeInfoInteger]](plain)
            store(at, plain.size, draw_integer_bits(source, plain.size, integer.is_signed))
        }
        case .FLOAT: { store(at, plain.size, draw_float_bits(source, plain.size)) }
        case .CHAR: {
            // Mostly ASCII; otherwise any code point the size holds, less the surrogates
            ascii :: draw_byte(source) < 192
            limit :: if ascii { cast[u64](128) } else if plain.size == 1 { cast[u64](256) } else { cast[u64](0x10_f800) }
            code := draw_below(source, limit)
            if !ascii && plain.size > 1 && code >= 0xd800 {
                code += 0x800
            }
            store(at, plain.size, code)
        }
        case .ENUM: {
            enumeration :: cast[ptr[compiler.TypeInfoEnum]](plain)
            if enumeration.values.count == 0 {
                return void
            }
            which :: cast[usize](draw_below(source, cast[u64](enumeration.values.count)))
            if which < enumeration.values.count {
                store(at, plain.size, cast[u64](enumeration.values[which]))
            }
        }
        case .STRUCT: {
            structure :: cast[ptr[compiler.TypeInfoStruct]](plain)
            for member in structure.members {
                draw_into(source, member.member_type, offset_by(at, member.offset))
                // A C-like union's members share their place: the first is drawn
                if structure.is_union {
                    break
                }
            }
        }
        case .ARRAY: {
            array :: cast[ptr[compiler.TypeInfoArray]](plain)
            for dimension in array.dimensions {
                if dimension.type != .STATIC {
                    unsupported(source, info)
                    return void
                }
            }
            element :: array.base_type.size
            if element == 0 {
                return void
            }
            for index in 0..<plain.size / element {
                draw_into(source, array.base_type, offset_by(at, index * element))
            }
        }
        case .VECTOR: {
            vector :: cast[ptr[compiler.TypeInfoVector]](plain)
            element :: vector.element_type.size
            for index in 0..<vector.count {
                draw_into(source, vector.element_type, offset_by(at, index * element))
            }
        }
        case .COMPLEX, .QUATERNION: {
            // Parts that are floats: two, or four
            parts :: if plain.variant == .COMPLEX { cast[usize](2) } else { cast[usize](4) }
            for index in 0..<parts {
                store(offset_by(at, index * (plain.size / parts)), plain.size / parts, draw_float_bits(source, plain.size / parts))
            }
        }
        case .UNION: {
            described :: cast[ptr[compiler.TypeInfoUnion]](plain)
            variants :: described.variants
            // One without a tag is an optional pointer
            tag_size :: match described.tag_type {
                case Some(tag) => tag.size
                case None => cast[usize](0)
            }
            if tag_size == 0 || variants.count == 0 {
                unsupported(source, info)
                return void
            }
            which :: cast[usize](draw_below(source, cast[u64](variants.count)))
            if which >= variants.count {
                return void
            }
            store(at, tag_size, cast[u64](which))
            variant :: variants[which]
            for type, i in variant.types {
                if i < variant.offsets.count {
                    draw_into(source, type, offset_by(at, variant.offsets[i]))
                }
            }
        }
        case _: unsupported(source, info)
    }
}

/**
 * Note that a type can't be drawn, unless one was noted before it.
 *
 * @param source The source, whose unsupported is set.
 * @param info The type.
 */
unsupported :: fn(source: ptr[mut Source], info: ptr[compiler.TypeInfo]) {
    if source.unsupported.count == 0 {
        storage : u8[TEXT_BYTES]
        name := text_buffer.make(storage)
        text_buffer.append_type_name(&name, info)
        source.unsupported = text_from(text_buffer.as_string(&name))
    }
}

/**
 * Discard a case of a property test that doesn't fit what it tests, as skip does a test: the case is drawn again, and
 * isn't counted. A test all of whose cases are discarded is reported as skipped.
 *
 * @param t The test's state.
 * @param condition What a case has to meet.
 * @param why What it is, as the skip's reason.
 * @return Ok if condition holds; Error(Skipped), for the test to return with ?, if not.
 */
assume :: fn(t: ptr[mut T], condition: bool, why: string) -> Outcome {
    if condition {
        return .Ok
    }
    return skip(t, why)
}

/**
 * Run a property test on given bytes, as a case being shrunk is, its failures kept to itself.
 *
 * @param property The test.
 * @param test The test's own state, only read: its name is the attempt's.
 * @param bytes The case's bytes; past them, draws read zeros.
 * @param into Where the bytes it read go: the case's own up to there, and zeros past them.
 * @return Whether it failed: an assertion failed, or it drew a type draw can't make.
 */
replay :: fn(property: Property, test: ptr[T], bytes: u8[], into: ptr[mut Case]) -> bool {
    set_case(into, bytes)
    source := source_in(into.bytes[0..<into.bytes.count], into.count, null)
    attempt := T.{name = test.name}
    _ = property(&attempt, &source)
    // Bytes it didn't read aren't the case's
    into.count = read_bytes(&source).count
    return attempt.failure_count > 0 || source.unsupported.count > 0
}

/**
 * Tell whether some bytes make a smaller case than others: fewer, or as many but lower at the first that differs.
 *
 * @param a The bytes that may be smaller.
 * @param b Those they're compared with.
 * @return True if a is smaller.
 */
smaller :: fn(a: u8[], b: u8[]) -> bool {
    if a.count != b.count {
        return a.count < b.count
    }
    for byte, i in a {
        if i < b.count && byte != b[i] {
            return byte < b[i]
        }
    }
    return false
}

/**
 * Read bytes as a number, the first the most significant, as draws read them.
 *
 * @param bytes The bytes.
 * @param start Where the number starts.
 * @param size How many bytes it has, 1 to 8; those past the bytes' end count as zeros.
 * @return The number.
 */
number_at :: fn(bytes: u8[], start: usize, size: usize) -> u64 {
    value : u64 = 0
    for index in start..<start + size {
        value = (value << 8) | (if index < bytes.count { cast[u64](bytes[index]) } else { cast[u64](0) })
    }
    return value
}

/**
 * Write a number as bytes, the first the most significant, as number_at reads them.
 *
 * @param bytes The bytes, written.
 * @param start Where the number starts.
 * @param size How many bytes it takes, 1 to 8; those past the bytes' end aren't written.
 * @param value The number, of which the low size bytes are written.
 */
set_number_at :: fn(bytes: mut u8[], start: usize, size: usize, value: u64) {
    for index in start..<start + size {
        shift :: cast[u64](start + size - 1 - index) * 8
        if index < bytes.count {
            bytes[index] = cast[u8]((value >> shift) & 0xff)
        }
    }
}

/** A failing case being made smaller. */
Shrinking :: struct {
    /** The test. */
    property : Property,
    /** The smallest failing case so far. */
    best : Case,
    /** How many times the test has been run on a candidate. */
    runs : usize,
}

/**
 * Try a candidate: if the test still fails on it and what it read is smaller than the best, it's the best.
 *
 * @param shrinking The shrinking, whose runs go up by one, and whose best may be replaced.
 * @param test The test's state, as the runner gave it, only read.
 * @param candidate The bytes to try.
 * @return Whether it became the best.
 */
try_candidate :: fn(shrinking: ptr[mut Shrinking], test: ptr[T], candidate: ptr[Case]) -> bool {
    shrinking.runs += 1
    tried : Case
    if !replay(shrinking.property, test, case_bytes(candidate), &tried) || !smaller(case_bytes(&tried), case_bytes(&shrinking.best)) {
        return false
    }
    shrinking.best = tried
    return true
}

/**
 * Make a failing case smaller, as far as SHRINK_RUNS allow: take out runs of bytes, zero them, and lower them.
 *
 * @param shrinking The shrinking, its best a failing case; it's left the smallest failing case found.
 * @param test The test's state, as the runner gave it, only read.
 */
shrink :: fn(shrinking: ptr[mut Shrinking], test: ptr[T]) {
    candidate : Case
    sizes :: usize.[8, 4, 2, 1]
    ascending :: usize.[1, 2, 4, 8]
    improved := true
    loop {
        if !improved || shrinking.runs >= SHRINK_RUNS {
            break
        }
        improved = false
        // Take out size bytes at a time, from the end, as later draws depend on earlier ones
        for size in sizes {
            end := shrinking.best.count
            loop {
                if end < size || shrinking.runs >= SHRINK_RUNS {
                    break
                }
                candidate.count = 0
                for byte, i in case_bytes(&shrinking.best) {
                    if (i >= end - size && i < end) || candidate.count >= candidate.bytes.count {
                        continue
                    }
                    candidate.bytes[candidate.count] = byte
                    candidate.count += 1
                }
                if try_candidate(shrinking, test, &candidate) {
                    improved = true
                    end = if end > shrinking.best.count { shrinking.best.count } else { end }
                    continue
                }
                end -= 1
            }
        }
        // Zero size bytes at a time
        for size in sizes {
            start : usize = 0
            loop {
                if start + size > shrinking.best.count || shrinking.runs >= SHRINK_RUNS {
                    break
                }
                candidate = shrinking.best
                zeroed := false
                for index in start..<start + size {
                    if index < candidate.bytes.count && candidate.bytes[index] != 0 {
                        candidate.bytes[index] = 0
                        zeroed = true
                    }
                }
                if zeroed && try_candidate(shrinking, test, &candidate) {
                    improved = true
                }
                start += 1
            }
        }
        /*
         * Lower runs of bytes, each run read as a number, most significant byte first, as draws read them: halving the
         * distance to the lowest that still fails. A value drawn from two bytes can need both lowered at once. Single
         * bytes come first, as they take the fewest runs, and a count lowered shortens all that follows it
         */
        for size in ascending {
            for start in 0..<shrinking.best.count {
                low : u64 = 0
                loop {
                    if start + size > shrinking.best.count || shrinking.runs >= SHRINK_RUNS {
                        break
                    }
                    high :: number_at(case_bytes(&shrinking.best), start, size)
                    if low >= high {
                        break
                    }
                    middle :: low + (high - low) / 2
                    candidate = shrinking.best
                    set_number_at(candidate.bytes[0..<candidate.bytes.count], start, size, middle)
                    if try_candidate(shrinking, test, &candidate) {
                        improved = true
                    }
                    else {
                        low = middle + 1
                    }
                }
            }
        }
    }
}

/**
 * Run a property test on case after case, as tests_of's table does for one: on the first that fails, make it as small
 * as it can be while it still fails, and run the test on that once more, with t, so its failures are what's reported,
 * each with the values drawn in its notes, and how the case was found in t.found.
 *
 * Each case's bytes come from t.seed and the case's number, so a seed gives the same cases every run.
 *
 * @param t The test's state: its seed and runs say which cases and how many, 0 runs for DEFAULT_RUNS.
 * @param property The test.
 * @return Ok if no case failed; what the smallest failing case's run gave, or Error(Failed), if one did; skip's
 *     Error(Skipped) if every case was discarded (assume).
 */
check_property :: fn(t: ptr[mut T], property: Property) -> Outcome {
    runs :: if t.runs == 0 { cast[usize](DEFAULT_RUNS) } else { t.runs }
    discarded : usize = 0
    room : u8[MAX_CASE_BYTES]
    for index in 0..<runs {
        state := t.seed + cast[u64](index) * 0x9e3779b97f4a7c15
        source := source_in(room, 0, next_random(&state))
        attempt := T.{name = t.name}
        _ = property(&attempt, &source)
        if attempt.failure_count == 0 && source.unsupported.count == 0 {
            if attempt.skipped {
                discarded += 1
            }
            continue
        }
        if source.unsupported.count > 0 {
            storage : u8[TEXT_BYTES]
            message := text_buffer.make(storage)
            text_buffer.append_format(&message, "draw can't make %: draw what it holds, and build it", text_of(&source.unsupported))
            record(t, text_buffer.as_string(&message), "", source.unsupported_at)
            return .Error(.Failed)
        }
        smallest : Case
        return report_shrunk(t, property, read_bytes(&source), &smallest, "case % of % (seed %)", index + 1, runs, t.seed)
    }
    if runs > 0 && discarded == runs {
        return skip(t, "every case was discarded")
    }
    return .Ok
}

/**
 * Make a failing case as small as it can be while it still fails, and run the test on that once more, with t, so its
 * failures are what's reported, each with the values drawn in its notes, and how the case was found in t.found.
 *
 * @param t The test's state, which the final run records into.
 * @param property The test.
 * @param failing The case's bytes, on which the test failed.
 * @param smallest Where the smallest failing case goes, the one reported.
 * @param format_string How the case was found, like "case % of %"; "shrunk from..." follows it.
 * @param values The values for its %s.
 * @return What the final run gave, or Error(Failed) if that was Ok.
 */
report_shrunk :: fn(t: ptr[mut T], property: Property, failing: u8[], smallest: ptr[mut Case], format_string: string, values: any...) -> Outcome {
    shrinking := Shrinking.{property = property}
    set_case(&shrinking.best, failing)
    shrink(&shrinking, t)
    // Once more, reported: the smallest case
    smallest^ = shrinking.best
    final := shrinking.best
    source := source_in(final.bytes[0..<final.bytes.count], final.count, null)
    outcome := property(t, &source)
    if t.failure_count == 0 {
        fail(t, "the case fails again when it's run again, as the test depends only on what it draws")
        outcome = .Error(.Failed)
    }
    add_drawn(t, text_of(&source.shown))
    storage : u8[TEXT_BYTES]
    found := text_buffer.make(storage)
    text_buffer.append_format(&found, format_string, values)
    text_buffer.append_format(&found, ", shrunk from % bytes to % in % runs", failing.count, shrinking.best.count, shrinking.runs)
    t.found = text_from(text_buffer.as_string(&found))
    if outcome is_ok {
        return .Error(.Failed)
    }
    return outcome
}

/**
 * Add the values a case drew to each failure kept, after its notes.
 *
 * @param t The test's state, whose failures' notes grow, cut at TEXT_BYTES.
 * @param drawn The values, as Source.shown has them; empty adds nothing.
 */
add_drawn :: fn(t: ptr[mut T], drawn: string) {
    if drawn.count == 0 {
        return void
    }
    for &failure, i in t.failures {
        if i >= t.failure_count {
            break
        }
        storage : u8[TEXT_BYTES]
        text := text_buffer.make(storage)
        text_buffer.append(&text, text_of(&failure.notes))
        if failure.notes.count > 0 {
            text_buffer.append(&text, "; ")
        }
        text_buffer.append(&text, "drew ")
        text_buffer.append(&text, drawn)
        failure.notes = text_from(text_buffer.as_string(&text))
    }
}
