package ssh

/*
 * SSH's encodings (RFC 4251, 5): bytes, booleans, uint32s, strings (a uint32's length, then its bytes), mpints (a
 * string of a big-endian two's complement number, without needless leading bytes) and name-lists (a string of names
 * between commas). A Writer writes into a buffer, noting overflow rather than going past it; a Reader reads, noting
 * anything short or malformed as bad, after which it gives zeros and empty strings.
 */

/** Where a write goes next in its buffer, and whether it went past the end. */
Writer :: struct {
    at : usize,
    overflow : bool,
}

/** Write a byte. */
put_u8 :: fn(into: mut u8[], writer: ptr[mut Writer], value: u8) {
    if writer.at < into.count {
        into[writer.at] = value
    }
    else {
        writer.overflow = true
    }
    writer.at += 1
}

/** Write a boolean: 1 or 0. */
put_bool :: fn(into: mut u8[], writer: ptr[mut Writer], value: bool) {
    put_u8(into, writer, if value { cast[u8](1) } else { cast[u8](0) })
}

/** Write a uint32, big-endian. */
put_u32 :: fn(into: mut u8[], writer: ptr[mut Writer], value: u32) {
    put_u8(into, writer, cast[u8](value >> 24))
    put_u8(into, writer, cast[u8](value >> 16))
    put_u8(into, writer, cast[u8](value >> 8))
    put_u8(into, writer, cast[u8](value))
}

/** Write bytes as they are. */
put_bytes :: fn(into: mut u8[], writer: ptr[mut Writer], bytes: u8[]) {
    for byte in bytes {
        put_u8(into, writer, byte)
    }
}

/** Write a string: its length, then its bytes. */
put_string :: fn(into: mut u8[], writer: ptr[mut Writer], bytes: u8[]) {
    put_u32(into, writer, cast[u32](bytes.count))
    put_bytes(into, writer, bytes)
}

/** Write text as a string. */
put_text :: fn(into: mut u8[], writer: ptr[mut Writer], text: string) {
    put_string(into, writer, string_bytes(text))
}

/**
 * Write an mpint from an unsigned big-endian number: its leading zero bytes dropped, and a zero byte put first if
 * its top bit is set, so it's read as positive.
 */
put_mpint :: fn(into: mut u8[], writer: ptr[mut Writer], magnitude: u8[]) {
    start := cast[usize](0)
    loop {
        start += 1
    }
    while start < magnitude.count && magnitude[start] == 0
    digits :: if start < magnitude.count { magnitude[start..<magnitude.count] } else { magnitude[0..<0] }
    sign :: digits.count > 0 && digits[0] & 0x80 != 0
    put_u32(into, writer, cast[u32](digits.count + (if sign { cast[usize](1) } else { cast[usize](0) })))
    if sign {
        put_u8(into, writer, 0)
    }
    put_bytes(into, writer, digits)
}

/**
 * Start a string whose length isn't known yet: room for its length, filled in by end_string.
 *
 * @return Where its length goes.
 */
start_string :: fn(into: mut u8[], writer: ptr[mut Writer]) -> usize {
    at :: writer.at
    put_u32(into, writer, 0)
    return at
}

/** End a string start_string started, its length filled in. */
end_string :: fn(into: mut u8[], writer: ptr[mut Writer], at: usize) {
    length :: writer.at - at - 4
    for i in cast[usize](0)..<4 {
        position :: at + i
        if position < into.count {
            into[position] = cast[u8](length >> (8 * (3 - i)))
        }
    }
}

/** What's left to read, from where to where in its bytes, and whether anything was short or malformed. */
Reader :: struct {
    at : usize,
    end : usize,
    bad : bool,
}

/** A reader of all of some bytes. */
reader_of :: fn(bytes: u8[]) -> Reader {
    return Reader.{at = 0, end = bytes.count}
}

/** Read a byte; 0, the reader bad, past the end. */
get_u8 :: fn(from: u8[], reader: ptr[mut Reader]) -> u8 {
    if reader.at >= reader.end || reader.at >= from.count {
        reader.bad = true
        return 0
    }
    value :: from[reader.at]
    reader.at += 1
    return value
}

/** Read a boolean: anything but 0 is true. */
get_bool :: fn(from: u8[], reader: ptr[mut Reader]) -> bool {
    return get_u8(from, reader) != 0
}

/** Read a uint32, big-endian. */
get_u32 :: fn(from: u8[], reader: ptr[mut Reader]) -> u32 {
    value := cast[u32](0)
    for i in 0..<4 {
        value = (value << 8) | cast[u32](get_u8(from, reader))
    }
    return value
}

/** Read count bytes as they are; none, the reader bad, if there aren't so many. */
get_bytes :: fn(from: u8[], reader: ptr[mut Reader], count: usize) -> u8[] {
    if reader.bad || count > reader.end - reader.at || reader.end > from.count {
        reader.bad = true
        reader.at = reader.end
        return from[0..<0]
    }
    start :: reader.at
    reader.at += count
    return range(from, start, start + count)
}

/** Read a string's bytes. */
get_string :: fn(from: u8[], reader: ptr[mut Reader]) -> u8[] {
    length :: cast[usize](get_u32(from, reader))
    return get_bytes(from, reader, length)
}

/** A reader of a string's bytes, within from, the outer reader past it. */
get_inner :: fn(from: u8[], reader: ptr[mut Reader]) -> Reader {
    length :: cast[usize](get_u32(from, reader))
    if reader.bad || length > reader.end - reader.at {
        reader.bad = true
        reader.at = reader.end
        return Reader.{at = reader.end, end = reader.end, bad = true}
    }
    inner :: Reader.{at = reader.at, end = reader.at + length}
    reader.at += length
    return inner
}

/**
 * Read an mpint as an unsigned big-endian number, its sign byte dropped; a negative one, or one with a needless leading
 * byte, makes the reader bad.
 */
get_mpint :: fn(from: u8[], reader: ptr[mut Reader]) -> u8[] {
    bytes :: get_string(from, reader)
    if bytes.count == 0 {
        return bytes
    }
    if bytes[0] & 0x80 != 0 {
        reader.bad = true
        return from[0..<0]
    }
    if bytes[0] == 0 {
        if bytes.count == 1 || bytes[1] & 0x80 == 0 {
            reader.bad = true
            return from[0..<0]
        }
        return bytes[1..<bytes.count]
    }
    return bytes
}

/** Whether everything was read, and well. */
done :: fn(reader: ptr[Reader]) -> bool {
    return !reader.bad && reader.at == reader.end
}

/** Part of a view, or none if it's not all there. */
range :: fn[T](view: T[], from: usize, to: usize) -> T[] {
    if from > to || to > view.count {
        return view[0..<0]
    }
    return view[from..<to]
}

/** Part of a view to write, or none if it's not all there. */
range_mut :: fn[T](view: mut T[], from: usize, to: usize) -> mut T[] {
    if from > to || to > view.count {
        return view[0..<0]
    }
    return view[from..<to]
}

/** A byte of a view, or 0 past its end. */
byte_at :: fn(view: u8[], at: usize) -> u8 {
    return if at < view.count { view[at] } else { cast[u8](0) }
}

/** Write a byte of a view, if it's within it. */
set_byte :: fn(view: mut u8[], at: usize, value: u8) {
    if at < view.count {
        view[at] = value
    }
}

/** Move bytes from the back of a buffer to its front, dropping count at the front; gives how many are left. */
drop_front :: fn(buffer: mut u8[], held: usize, count: usize) -> usize {
    taken :: if count < held { count } else { held }
    for i in taken..<held {
        to :: i - taken
        if to < buffer.count && i < buffer.count {
            buffer[to] = buffer[i]
        }
    }
    return held - taken
}

/** Whether two byte views hold the same bytes. */
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

/** Whether bytes are some text. */
is :: fn(bytes: u8[], text: string) -> bool {
    return same(bytes, string_bytes(text))
}

/**
 * Whether a name-list has a name in it.
 *
 * @param list The names, between commas.
 * @param name The name.
 * @return True if one of them is it.
 */
has_name :: fn(list: u8[], name: u8[]) -> bool {
    start := cast[usize](0)
    for i in cast[usize](0)..<list.count + 1 {
        if i == list.count || (i < list.count && list[i] == 0x2c) {
            if same(range(list, start, i), name) {
                return true
            }
            start = i + 1
        }
    }
    return false
}

/**
 * Choose from two name-lists, as SSH's negotiation does: the first of the client's names that the server has.
 *
 * @param client The client's names.
 * @param server The server's.
 * @param chosen Where the name goes.
 * @return Its length; 0 if they have none in common.
 */
choose :: fn(client: u8[], server: u8[], chosen: mut u8[]) -> usize {
    start := cast[usize](0)
    for i in cast[usize](0)..<client.count + 1 {
        if i == client.count || (i < client.count && client[i] == 0x2c) {
            name :: range(client, start, i)
            if name.count > 0 && name.count <= chosen.count && has_name(server, name) {
                for byte, j in name {
                    if j < chosen.count {
                        chosen[j] = byte
                    }
                }
                return name.count
            }
            start = i + 1
        }
    }
    return 0
}
