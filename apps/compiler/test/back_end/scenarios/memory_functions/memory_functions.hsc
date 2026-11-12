/*
 * The memory functions the compiler defines, as nothing Hemera builds links a C library: memcpy, memmove and memset,
 * which go a word at a time where their pointers are as aligned as each other, against a byte at a time, at every
 * alignment and length up to past a few words, memmove overlapping either way.
 */
package memory_functions

import intrinsics from "base"
import testing from "std"

/** The buffers' size: room for any length drawn at any offset. */
SIZE :: 512

/** Fill a buffer with bytes that differ from one place to the next, from a seed. */
pattern :: fn(buffer: ptr[mut u8[SIZE]], seed: u8) {
    for &b, i in buffer^ {
        b^ = cast[u8](i * 7) + seed
    }
}

/** Where target and source start, and how many bytes: any alignment of each, 0 to 300 bytes. */
Copy :: struct {
    target : usize,
    source : usize,
    count : usize,
}

/** The address of a buffer's byte at an offset, which the copies take. */
at :: fn(buffer: ptr[u8[SIZE]], offset: usize) -> u64 {
    return cast[u64](buffer) + cast[u64](offset)
}

/**
 * Set a byte of a buffer, where it's in the buffer.
 *
 * @param buffer The buffer.
 * @param index Which byte; past the end, nothing is set.
 * @param value The byte.
 */
put :: fn(buffer: ptr[mut u8[SIZE]], index: usize, value: u8) {
    if index < SIZE {
        buffer[index] = value
    }
}

/**
 * Read a byte of a buffer.
 *
 * @param buffer The buffer.
 * @param index Which byte.
 * @return It; 0 past the end.
 */
get :: fn(buffer: ptr[u8[SIZE]], index: usize) -> u8 {
    return if index < SIZE { buffer[index] } else { 0 }
}

/** Draw a copy that fits the buffers. */
draw_copy :: fn(source: ptr[mut testing.Source]) -> Copy {
    return Copy.{
        target = cast[usize](testing.draw_below(source, 64)),
        source = cast[usize](testing.draw_below(source, 64)),
        count = cast[usize](testing.draw_below(source, 301)),
    }
}

copies_without_overlap #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    copy :: draw_copy(source)
    from : u8[SIZE]
    pattern(&from, 1)
    to : u8[SIZE]
    pattern(&to, 100)
    expected := to
    for i in 0..<copy.count {
        put(&expected, copy.target + i, get(&from, copy.source + i))
    }
    intrinsics.mem_copy_non_overlapping(cast[mut rawptr](at(&to, copy.target)), cast[rawptr](at(&from, copy.source)), copy.count)
    testing.note(t, "% bytes from % to %", copy.count, copy.source, copy.target)
    testing.expect(t, to == expected, "every byte copied, and none around them touched")
    testing.end_note(t)
    return .Ok
}

copies_over_itself #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    copy :: draw_copy(source)
    buffer : u8[SIZE]
    pattern(&buffer, 3)
    before :: buffer
    expected := buffer
    for i in 0..<copy.count {
        put(&expected, copy.target + i, get(&before, copy.source + i))
    }
    intrinsics.mem_copy(cast[mut rawptr](at(&buffer, copy.target)), cast[rawptr](at(&buffer, copy.source)), copy.count)
    testing.note(t, "% bytes from % to %, overlapping", copy.count, copy.source, copy.target)
    testing.expect(t, buffer == expected, "every byte as it was before the copy, and none around them touched")
    testing.end_note(t)
    return .Ok
}

/** Fill bytes one at a time, which the optimizer makes a memset of. */
fill :: fn(buffer: ptr[mut u8[SIZE]], start: usize, count: usize, value: u8) {
    for i in 0..<count {
        if start + i < SIZE {
            buffer[start + i] = value
        }
    }
}

fills #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    copy :: draw_copy(source)
    value :: cast[u8](testing.draw_below(source, 256))
    buffer : u8[SIZE]
    pattern(&buffer, 5)
    expected := buffer
    for i in 0..<copy.count {
        put(&expected, copy.target + i, value)
    }
    fill(&buffer, copy.target, copy.count, value)
    testing.note(t, "% bytes of % at %", copy.count, value, copy.target)
    testing.expect(t, buffer == expected, "every byte set, and none around them touched")
    testing.end_note(t)
    zeroed := buffer
    intrinsics.mem_zero(cast[mut rawptr](at(&zeroed, copy.target)), copy.count)
    for i in 0..<copy.count {
        put(&expected, copy.target + i, 0)
    }
    testing.expect(t, zeroed == expected, "mem_zero zeroes every byte, and none around them")
    return .Ok
}
