/*
 * Fuzz targets (docs/testing.md, Fuzzing): property tests a fuzzer runs on inputs it makes. Run as tests, main returns 42
 * if they pass on many cases; built with hemera --fuzz, the fuzzer runs one of them, and finds_the_magic, which fails
 * only on four bytes in a row that drawing at random would take billions of cases to come on, fails within seconds.
 */
package fuzz_targets

import runtime from "base"
import compiler from "base"
import memory from "std"
import testing from "std"

/** Something read back from bytes another program sent: strings, views and pointers to check. */
Message :: struct {
    name : string,
    values : u32[],
    inner : ptr[Inner]?,
    shape : Shape,
    history : u16[..],
    on_change : (fn())?,
    raw : rawptr,
}

Inner :: struct {
    label : string,
    weights : u16[],
}

Shape :: union {
    Circle(f64),
    Named(string),
    Nothing,
}

// Wrong on purpose, for the fuzzer to find: the magic bytes are there for any test that looks
finds_the_magic #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    bytes :: testing.draw_bytes(source, 64)
    if bytes.count >= 4 && bytes[0] == cast[u8]('H') && bytes[1] == cast[u8]('E') && bytes[2] == cast[u8]('M')
        && bytes[3] == cast[u8]('R') {
        testing.fail(t, "the magic is never there")
    }
    return .Ok
}

/**
 * Check that a stretch of memory is inside the copy a read made.
 *
 * @param t The test's state.
 * @param start Where the copy starts.
 * @param end Where it ends, the byte after it.
 * @param at Where the stretch starts.
 * @param count How many bytes it has; 0 checks nothing, as an empty view points nowhere.
 * @param what What the stretch is, for the failure.
 * @param location Where the check is; the caller's own.
 */
expect_inside :: fn(t: ptr[mut testing.T], start: usize, end: usize, at: usize, count: usize, what: string, location := #caller_location) {
    if count > 0 && (at < start || at > end || count > end - at) {
        testing.record(t, what, "it points outside the copy", location)
    }
}

/**
 * Give where a string's bytes are.
 *
 * @param text The string.
 * @return Its first byte's address; 0 for an empty one.
 */
address_of :: fn(text: string) -> usize {
    if text.count == 0 {
        return 0
    }
    return cast[usize](cast[uintptr](&text[0]))
}

// Whatever the bytes, a value read from them points only into the copy the read made
reads_only_inside_the_copy #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    bytes :: testing.draw_bytes(source, 512)
    arena :: memory.make_arena(64 * 1024) or_return testing.skip(t, "no memory for an arena")
    defer memory.free_arena(arena)
    value : Message
    read := false
    push_context reading (allocator = memory.arena_allocator(arena)) {
        read = runtime.schema_read_value(bytes, type_info_of(Message), cast[rawptr](&value))
    }
    if !read {
        return .Ok
    }
    // The copy is the read's only block, the arena's newest
    start :: arena.last
    end :: start + bytes.count
    expect_inside(t, start, end, address_of(value.name), value.name.count, "the name is in the copy")
    if value.values.count > 0 {
        expect_inside(t, start, end, cast[usize](cast[uintptr](&value.values[0])), value.values.count * 4, "the values are in the copy")
    }
    match value.inner {
        case Some(inner) => {
            expect_inside(t, start, end, cast[usize](cast[uintptr](inner)), size_of(Inner), "the inner value is in the copy")
            expect_inside(t, start, end, address_of(inner.label), inner.label.count, "the inner label is in the copy")
            if inner.weights.count > 0 {
                expect_inside(t, start, end, cast[usize](cast[uintptr](&inner.weights[0])), inner.weights.count * 2,
                    "the inner weights are in the copy")
            }
        }
        case None => {}
    }
    match value.shape {
        case Named(name) => expect_inside(t, start, end, address_of(name), name.count, "the shape's name is in the copy")
        case _ => {}
    }
    if value.history.count > 0 {
        expect_inside(t, start, end, cast[usize](cast[uintptr](&value.history[0])), value.history.count * 2, "the history is in the copy")
    }
    // What the writer writes as 0 is read as 0, whatever the bytes say
    history :: runtime.resizable(&value.history)
    testing.expect_eq(t, history.capacity, 0, "the history owns no memory of its own")
    testing.expect(t, cast[rawptr](history.allocator.function) == null, "the history has no allocator")
    testing.expect(t, value.on_change is_none, "no function comes from the bytes")
    testing.expect(t, value.raw == null, "no rawptr comes from the bytes")
    // Added to, it moves to memory of its own, its elements with it
    first :: if value.history.count > 0 { value.history[0] } else { cast[u16](0) }
    count :: value.history.count
    runtime.array_add(&value.history, 7)
    testing.expect_eq(t, value.history.count, count + 1, "the history has one more")
    if count > 0 && value.history.count > 0 {
        testing.expect_eq(t, value.history[0], first, "the history keeps its first element")
    }
    testing.expect_gt(t, runtime.resizable(&value.history).capacity, count, "the history has memory of its own")
    runtime.array_free(&value.history)
    return .Ok
}

/*
 * What fuzzing reads_only_inside_the_copy found, each as a test of its own: a null string with a count, and a pointer
 * into the value itself, whose bytes were then made pointers again under it
 */

/**
 * Write a little-endian word into bytes.
 *
 * @param bytes The bytes.
 * @param at Where the word goes; bytes past the end aren't written.
 * @param value The word.
 */
put_word :: fn(bytes: mut u8[], at: usize, value: u64) {
    for index in cast[usize](0)..<8 {
        if at + index < bytes.count {
            bytes[at + index] = cast[u8]((value >> cast[u64](index * 8)) & 0xff)
        }
    }
}

/**
 * Make bytes that are all zeros.
 *
 * @param count How many.
 * @return The bytes, the caller's, given back with runtime.array_free.
 */
zeros :: fn(count: usize) -> u8[..] {
    made : u8[..]
    for index in 0..<count {
        runtime.array_add(&made, 0)
    }
    return made
}

refuses_a_null_string_with_a_count #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    bytes := zeros(size_of(Message))
    defer runtime.array_free(&bytes)
    put_word(bytes, offset_of(Message, name), 5)
    value : Message
    testing.expect(t, !runtime.schema_read_value(bytes, type_info_of(Message), cast[rawptr](&value)),
        "a string with a count and no bytes isn't read")
    return .Ok
}

refuses_a_pointer_into_the_value #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    bytes := zeros(size_of(Message) + size_of(Inner))
    defer runtime.array_free(&bytes)
    // Inside the value's own bytes, where history is, rather than after them
    put_word(bytes, offset_of(Message, inner), cast[u64](offset_of(Message, history)))
    value : Message
    testing.expect(t, !runtime.schema_read_value(bytes, type_info_of(Message), cast[rawptr](&value)),
        "a pointer into the value isn't read, as its bytes would be read as two things")
    return .Ok
}

reads_as_zero_what_the_writer_writes_as_zero #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    bytes := zeros(size_of(Message))
    defer runtime.array_free(&bytes)
    put_word(bytes, offset_of(Message, on_change), 0x1234)
    put_word(bytes, offset_of(Message, raw), 0x5678)
    // A dynamic array's capacity, and its allocator's function and data
    for word in cast[usize](2)..<5 {
        put_word(bytes, offset_of(Message, history) + word * 8, 0x9abc)
    }
    value : Message
    testing.require(t, runtime.schema_read_value(bytes, type_info_of(Message), cast[rawptr](&value)), "the value is read")?
    testing.expect(t, value.on_change is_none, "no function comes from the bytes")
    testing.expect(t, value.raw == null, "no rawptr comes from the bytes")
    history :: runtime.resizable(&value.history)
    testing.expect_eq(t, history.capacity, 0, "the history owns no memory")
    testing.expect(t, cast[rawptr](history.allocator.function) == null && history.allocator.data == null, "the history has no allocator")
    return .Ok
}

adds_to_an_array_read_back #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    sent := Message.{}
    for number in 1..=3 {
        runtime.array_add(&sent.history, cast[u16](number))
    }
    bytes : u8[..]
    runtime.schema_write_value(sent, &bytes)
    value : Message
    testing.require(t, runtime.schema_read_value(bytes, type_info_of(Message), cast[rawptr](&value)), "the value is read")?
    runtime.array_add(&value.history, 4)
    wanted :: u16.[1, 2, 3, 4]
    testing.expect_same_items(t, value.history, wanted[0..<4], "the history keeps its elements, and the one added")
    testing.expect_ge(t, runtime.resizable(&value.history).capacity, 4, "the history has memory of its own")
    runtime.array_free(&value.history)
    runtime.array_free(&sent.history)
    runtime.array_free(&bytes)
    return .Ok
}

main :: fn() -> int {
    storage : u8[4096]
    caught := testing.BufferReporter.{bytes = storage}
    failed :: testing.run(#insert testing.tests_of(compiler.load_package(".")), testing.reporter_of(&caught), testing.RunOptions.{runs = 2000})
    if failed != 0 {
        runtime.write_output(testing.report_text(&caught))
        return 1
    }
    return 42
}
