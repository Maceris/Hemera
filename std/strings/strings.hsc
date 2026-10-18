package strings

import runtime from "base"
import text_buffer from "std"

/*
 * Bytes format tries on the stack first, which most results fit in. A longer result is formatted
 * again into memory from the allocator, twice as big each time until it fits.
 */
FORMAT_STACK_SIZE :: 256

/*
 * format_string with its values filled in, as text_buffer.append_format does it, in a new string
 * from allocator, which free_string gives back:
 *
 *     match strings.format("frame %", index) {
 *         case Ok(name) => keep(name)
 *         case Error(_) => {}
 *     }
 *
 * The result is #unrestricted: it's the allocator's memory, never the values', so it can be kept
 * anywhere. An empty result allocates nothing.
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

// A copy of text, in a new string from allocator, which free_string gives back. An empty one allocates nothing.
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

// Gives back a string from format or clone, to the allocator it came from.
free_string :: fn(text: string, allocator := context.allocator) {
    if text.count == 0 {
        return void
    }
    runtime.free_array(bit_cast[u8[]](text), allocator)
}

// Whether a and b have the same bytes.
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

/*
 * The bytes of text from start up to end, not including end, without copying. Both are clamped
 * to the text, so a range past its end is cut short, and an empty or backwards one is "".
 */
slice :: fn(text: string, start: usize, end: usize) -> string {
    last :: if end < text.count { end } else { text.count }
    if start >= last {
        return ""
    }
    return string_of(cast[ptr[u8]](cast[rawptr](text.data) + start), last - start)
}

starts_with :: fn(text: string, prefix: string) -> bool {
    return prefix.count <= text.count && equal(slice(text, 0, prefix.count), prefix)
}

ends_with :: fn(text: string, suffix: string) -> bool {
    return suffix.count <= text.count && equal(slice(text, text.count - suffix.count, text.count), suffix)
}

// Where part first starts in text, from start on, or none. An empty part is found at start.
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

contains :: fn(text: string, part: string) -> bool {
    return find(text, part) != null
}

// Spaces, tabs, carriage returns and newlines.
is_space :: fn(character: char) -> bool {
    return character == ' ' || character == '\t' || character == '\r' || character == '\n'
}

// text without the spaces (is_space) at either end, without copying.
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

/*
 * The pieces of text between each separator, a piece at a time, without copying:
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
    rest : string,
    separator : string,
    done : bool,
}

split :: fn(text: string, separator: string) -> Split {
    return Split.{rest = text, separator = separator, done = false}
}

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
