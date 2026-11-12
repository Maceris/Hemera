package tls

/*
 * Reading and writing TLS's wire format (RFC 8446 §3): big-endian numbers and vectors with a length before them. A
 * Writer writes into bytes its caller gives, and notes overflow rather than writing past them; a Reader reads within an
 * end, and notes a read past it, which then reads zeros, so a short or malformed message is found by checking bad
 * once, never read past.
 */

/** Where a Writer is in the bytes it writes, and whether it ran out of room. */
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

/** Write a big-endian u16. */
put_u16 :: fn(into: mut u8[], writer: ptr[mut Writer], value: u16) {
    put_u8(into, writer, cast[u8](value >> 8))
    put_u8(into, writer, cast[u8](value))
}

/** Write a big-endian 24-bit number. */
put_u24 :: fn(into: mut u8[], writer: ptr[mut Writer], value: usize) {
    put_u8(into, writer, cast[u8](value >> 16))
    put_u8(into, writer, cast[u8](value >> 8))
    put_u8(into, writer, cast[u8](value))
}

/** Write bytes. */
put_bytes :: fn(into: mut u8[], writer: ptr[mut Writer], bytes: u8[]) {
    for byte in bytes {
        put_u8(into, writer, byte)
    }
}

/**
 * Start a vector: room for its length, of size bytes, filled in by end_vector.
 *
 * @return Where its length goes, for end_vector.
 */
start_vector :: fn(into: mut u8[], writer: ptr[mut Writer], size: usize) -> usize {
    at :: writer.at
    for i in 0..<size {
        put_u8(into, writer, 0)
    }
    return at
}

/**
 * End a vector: its length, from its start to here, written where start_vector left room.
 *
 * @param into The bytes.
 * @param writer The writer, at the vector's end.
 * @param at Where start_vector left its length's room.
 * @param size The length's size in bytes: 1, 2 or 3.
 */
end_vector :: fn(into: mut u8[], writer: ptr[mut Writer], at: usize, size: usize) {
    length :: writer.at - at - size
    for i in 0..<size {
        position :: at + i
        if position < into.count {
            into[position] = cast[u8](length >> (8 * (size - 1 - i)))
        }
    }
    if size < 3 && length >> (8 * size) != 0 {
        writer.overflow = true
    }
}

/** Where a Reader is in the bytes it reads, where it stops, and whether it read past that. */
Reader :: struct {
    at : usize,
    end : usize,
    bad : bool,
}

/**
 * Start reading bytes, all of them.
 *
 * @param bytes The bytes.
 * @return A reader at their start.
 */
reader_of :: fn(bytes: u8[]) -> Reader {
    return Reader.{at = 0, end = bytes.count}
}

/** Read a byte; 0, with bad set, past the end. */
get_u8 :: fn(from: u8[], reader: ptr[mut Reader]) -> u8 {
    if reader.at >= reader.end || reader.at >= from.count {
        reader.bad = true
        return 0
    }
    value :: from[reader.at]
    reader.at += 1
    return value
}

/** Read a big-endian u16. */
get_u16 :: fn(from: u8[], reader: ptr[mut Reader]) -> u16 {
    high :: cast[u16](get_u8(from, reader))
    return (high << 8) | cast[u16](get_u8(from, reader))
}

/** Read a big-endian 24-bit number. */
get_u24 :: fn(from: u8[], reader: ptr[mut Reader]) -> usize {
    a :: cast[usize](get_u8(from, reader))
    b :: cast[usize](get_u8(from, reader))
    return (a << 16) | (b << 8) | cast[usize](get_u8(from, reader))
}

/**
 * Read bytes.
 *
 * @param from The bytes read.
 * @param reader The reader.
 * @param count How many.
 * @return A view of them; empty, with bad set, if they run past the end.
 */
get_bytes :: fn(from: u8[], reader: ptr[mut Reader], count: usize) -> u8[] {
    if count > reader.end - reader.at || reader.at + count > from.count {
        reader.bad = true
        reader.at = reader.end
        return from[0..<0]
    }
    start :: reader.at
    reader.at += count
    return range(from, start, start + count)
}

/**
 * Read a vector's length and give a reader over its contents, moving past them.
 *
 * @param from The bytes read.
 * @param reader The reader, at the vector's length.
 * @param size The length's size in bytes: 1, 2 or 3.
 * @return A reader of the vector's contents; one that's at its end already, with bad set on reader, if it runs past
 *     reader's end.
 */
get_vector :: fn(from: u8[], reader: ptr[mut Reader], size: usize) -> Reader {
    length := cast[usize](0)
    for i in 0..<size {
        length = (length << 8) | cast[usize](get_u8(from, reader))
    }
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
 * Tell whether a reader's read all it had, without reading past it.
 *
 * @param reader The reader.
 * @return True if it's at its end, and never read past it.
 */
done :: fn(reader: ptr[Reader]) -> bool {
    return !reader.bad && reader.at == reader.end
}

/**
 * Give a part of a view, checked.
 *
 * @param view The view.
 * @param from Where the part starts.
 * @param to Where it ends, not included.
 * @return view[from..<to]; empty if that isn't within view.
 */
range :: fn[T](view: T[], from: usize, to: usize) -> T[] {
    if from > to || to > view.count {
        return view[0..<0]
    }
    return view[from..<to]
}

/** The same for a view written to. */
range_mut :: fn[T](view: mut T[], from: usize, to: usize) -> mut T[] {
    if from > to || to > view.count {
        return view[0..<0]
    }
    return view[from..<to]
}
