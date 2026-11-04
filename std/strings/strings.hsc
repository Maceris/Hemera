package strings

import runtime from "base"
import text_buffer from "std"

/**
 * How many bytes format tries on the stack first, which most results fit in.
 *
 * A longer result is formatted again into memory from the allocator, twice as big each time until it fits.
 */
FORMAT_STACK_SIZE :: 256

/**
 * Make a new string of a format string with its values filled in, as text_buffer.append_format does it.
 *
 *     match strings.format("frame %", index) {
 *         case Ok(name) => keep(name)
 *         case Error(_) => {}
 *     }
 *
 * The result is #unrestricted: it's the allocator's memory, never the values', so it can be kept anywhere. A result
 * longer than FORMAT_STACK_SIZE is formatted more than once, into scratch memory from allocator that's freed again.
 *
 * @param format_string The text, with a % for each value (docs/format_strings.md).
 * @param values The values, read but not kept.
 * @param allocator Where the string comes from.
 * @return The string, the caller's, given back with free_string and the same allocator; an empty result allocates
 *     nothing.
 * @error OutOfMemory The allocator had no memory for the string, or for scratch memory to format it in; nothing is
 *     left allocated. Any other error the allocator gives is returned the same way.
 */
format :: fn(format_string: string, values: any..., allocator := context.allocator) -> Result[string, runtime.AllocatorError] #unrestricted {
    storage : u8[FORMAT_STACK_SIZE]
    text := text_buffer.make(storage)
    text_buffer.append_format(&text, format_string, values)
    if !text.truncated {
        return clone(text_buffer.as_string(&text), allocator)
    }
    size : usize = FORMAT_STACK_SIZE * 2
    loop {
        bytes, error :: runtime.new_array(u8, size, allocator)
        match error {
            case Some(failure) => return .Error(failure)
            case None => {}
        }
        larger := text_buffer.make(bytes)
        text_buffer.append_format(&larger, format_string, values)
        if !larger.truncated {
            result :: clone(text_buffer.as_string(&larger), allocator)
            runtime.free_array(bytes, allocator)
            return result
        }
        runtime.free_array(bytes, allocator)
        size *= 2
    }
}

/**
 * Copy text into a new string.
 *
 * @param text The text, which can be anywhere: a view of the stack, or of memory about to be freed.
 * @param allocator Where the copy comes from.
 * @return The copy, the caller's, given back with free_string and the same allocator; #unrestricted, so it can be kept
 *     anywhere. Empty text gives "", allocating nothing.
 * @error OutOfMemory The allocator had no memory for the copy. Any other error the allocator gives is returned the same
 *     way.
 */
clone :: fn(text: string, allocator := context.allocator) -> Result[string, runtime.AllocatorError] #unrestricted {
    if text.count == 0 {
        return .Ok("")
    }
    bytes, error :: runtime.new_array(u8, text.count, allocator)
    match error {
        case Some(failure) => return .Error(failure)
        case None => {}
    }
    if bytes.count == 0 {
        return .Ok("")
    }
    for character, index in text {
        if index < bytes.count {
            bytes[index] = cast[u8](character)
        }
    }
    return .Ok(string_of(&bytes[0], bytes.count))
}

/**
 * Give back a string from format or clone, to the allocator it came from.
 *
 * @param text The string, invalid afterwards; an empty one is ignored, since it was never allocated.
 * @param allocator The allocator it came from.
 */
free_string :: fn(text: string, allocator := context.allocator) {
    if text.count == 0 {
        return void
    }
    runtime.free_array(bit_cast[u8[]](text), allocator)
}

/**
 * Tell whether two strings have the same bytes.
 *
 * @param a One string, only read.
 * @param b The string to compare it with, only read; which of the two is which doesn't matter.
 * @return True if they have the same count and bytes, byte for byte: no Unicode normalization or case folding.
 */
equal :: fn(a: string, b: string) -> bool {
    if a.count != b.count {
        return false
    }
    for character, index in a {
        if index >= b.count || b[index] != character {
            return false
        }
    }
    return true
}

/**
 * Take the bytes of text from start up to end, without copying.
 *
 * @param text The string to take from; it isn't copied, so the view is good only as long as its bytes are.
 * @param start The byte index of the first byte.
 * @param end The byte index past the last, not included. Both are clamped to the text, so a range past its end is cut
 *     short.
 * @return A view of text's bytes, good while they are; "" for an empty or backwards range. It can split a UTF-8
 *     character: indices are bytes.
 */
slice :: fn(text: string, start: usize, end: usize) -> string {
    last :: if end < text.count { end } else { text.count }
    if start >= last {
        return ""
    }
    return string_of(cast[ptr[u8]](cast[rawptr](text.data) + start), last - start)
}

/**
 * Tell whether text starts with a prefix.
 *
 * @param text The string to check, only read.
 * @param prefix The prefix; an empty one starts every text.
 * @return True if text's first bytes are prefix's.
 */
starts_with :: fn(text: string, prefix: string) -> bool {
    return prefix.count <= text.count && equal(slice(text, 0, prefix.count), prefix)
}

/**
 * Tell whether text ends with a suffix.
 *
 * @param text The string to check, only read.
 * @param suffix The suffix; an empty one ends every text.
 * @return True if text's last bytes are suffix's.
 */
ends_with :: fn(text: string, suffix: string) -> bool {
    return suffix.count <= text.count && equal(slice(text, text.count - suffix.count, text.count), suffix)
}

/**
 * Find where part first starts in text, from a byte index on.
 *
 * @param text The text to look in.
 * @param part What to look for; an empty part is found at start.
 * @param start The byte index to start looking at.
 * @return The byte index where part starts, at or after start; null if it isn't there, or start is past where it
 *     could fit.
 */
find :: fn(text: string, part: string, start: usize = 0) -> usize? {
    if part.count > text.count {
        return null
    }
    for index in start..<(text.count - part.count + 1) {
        if equal(slice(text, index, index + part.count), part) {
            return index
        }
    }
    return null
}

/**
 * Tell whether part is anywhere in text.
 *
 * @param text The text to look in.
 * @param part What to look for; an empty part is in every text.
 * @return True if find finds it.
 */
contains :: fn(text: string, part: string) -> bool {
    return find(text, part) != null
}

/**
 * Tell whether a character is a space, as trim takes them.
 *
 * @param character One byte of text: the bytes of a UTF-8 character past ASCII are never spaces.
 * @return True for a space, tab, carriage return or newline; false for anything else, other Unicode spaces included.
 */
is_space :: fn(character: char) -> bool {
    return character == ' ' || character == '\t' || character == '\r' || character == '\n'
}

/**
 * Take text without the spaces (is_space) at either end, without copying.
 *
 * @param text The string to trim; it isn't copied, so the view is good only as long as its bytes are.
 * @return A view of text's bytes, good while they are; "" if it's all spaces.
 */
trim :: fn(text: string) -> string {
    start : usize = 0
    end := text.count
    for character in text {
        if !is_space(character) {
            break
        }
        start += 1
    }
    loop {
        if end <= start || !is_space(text[end - 1]) {
            break
        }
        end -= 1
    }
    return slice(text, start, end)
}

/**
 * The pieces of text between each separator, a piece at a time, without copying.
 *
 *     pieces := strings.split("a,b,,c", ",")
 *     loop {
 *         match strings.next(&pieces) {
 *             case Some(piece) => use(piece)    // "a", "b", "", "c"
 *             case None => break
 *         }
 *     }
 *
 * Text without the separator is one piece, and "" is one empty piece. An empty separator gives
 * the whole text as one piece.
 */
Split :: struct {
    /** What's left of the text, after the pieces given so far and their separators. */
    rest : string,
    /** What the text is split at; empty to give the whole text as one piece. */
    separator : string,
    /** Whether the last piece was given, so next gives no more. */
    done : bool,
}

/**
 * Start splitting text at each separator.
 *
 * @param text The text, which the pieces are views of: it must outlive them, and the Split.
 * @param separator What to split at, which isn't in any piece; empty to give the whole text as one piece.
 * @return The pieces, given one at a time by next.
 */
split :: fn(text: string, separator: string) -> Split {
    return Split.{rest = text, separator = separator, done = false}
}

/**
 * Give the next piece of a split.
 *
 * @param pieces The split, moved on past the piece.
 * @return The piece, a view of the text, empty between two separators in a row or at either end; null once every
 *     piece has been given. There's always at least one piece, "" for empty text.
 */
next :: fn(pieces: ptr[mut Split]) -> string? {
    if pieces.done {
        return null
    }
    if pieces.separator.count > 0 {
        match find(pieces.rest, pieces.separator) {
            case Some(found) => {
                piece :: slice(pieces.rest, 0, found)
                pieces.rest = slice(pieces.rest, found + pieces.separator.count, pieces.rest.count)
                return piece
            }
            case None => {}
        }
    }
    pieces.done = true
    return pieces.rest
}
