package schemas

import compiler from "base"
import runtime from "base"
import crypto from "std"
import memory from "std"
import schema from "std"
import testing from "std"

/*
 * std's schema: a type's description serialized canonically, and its hash, the same at compile time and at run time.
 * A plain alias is the type it names, a distinct one isn't; what's laid out alike under the same names hashes alike,
 * and a different name, member order or member type doesn't; a type that refers to itself is described once. A value
 * written for elsewhere has what it points to after it, at distances from its start, and no address of the writer's,
 * and reads back as the text base's output_format gives it. base's own BLAKE3, which hashes schemas, agrees with std's.
 * Without the memory, try_write and try_write_value give the error and leave what they write to as it was, as the
 * SlopOS logger needs to drop a record rather than end the process.
 */

Point :: struct {
    x : i32,
    y : i32,
}

Swapped :: struct {
    y : i32,
    x : i32,
}

Place :: struct {
    x : i32,
    y : i32,
}

Wide :: struct {
    x : i64,
    y : i32,
}

PlainPoint :: Point
DistinctPoint :: distinct alias Point

Node :: struct {
    value : int,
    next : ptr[Node]?,
}

Shape :: union {
    Circle(f64),
    Square(f64, f64),
    Nothing,
}

Color :: enum #backed_by(u8) {
    Red = 1,
    Green = 2,
}

Handler :: alias fn(name: string, count: int) -> bool

// An entry, as a manifest has it: read back, each parameter's type hashes as its own schema does.
Entry :: alias fn(count: u64, label: string, item: Item, shape: Shape?, color: Color, node: Node) -> int

// An any's fields, to make one that points to the heap
AnyParts :: struct {
    data : rawptr,
    type : type,
}

Item :: struct {
    id : u32,
    name : string,
    scores : i32[],
    next : ptr[Item]?,
    extra : any,
}

/** Point's schema hash, worked out at compile time. */
COMPILED_POINT :: #run schema.hash(type_info_of(Point))

/**
 * Tell whether two hashes are the same.
 *
 * @param a A hash.
 * @param b Another.
 * @return True if every byte matches.
 */
same :: fn(a: u8[32], b: u8[32]) -> bool {
    for byte, i in a {
        if byte != b[i] {
            return false
        }
    }
    return true
}

/**
 * Hash a type's schema, at run time.
 *
 * @param type Any type.
 * @return The BLAKE3 hash of the schema schema.write writes for it.
 */
hash_of :: fn(type: type) -> u8[32] {
    return schema.hash(type_info_of(type))
}

hashes_alike_at_compile_and_run_time #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, same(hash_of(Point), COMPILED_POINT), "a schema is written the same by #run and by the program")
    return .Ok
}

hashes_what_is_laid_out_alike_under_the_same_names_alike #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    point :: hash_of(Point)
    testing.expect(t, same(point, hash_of(PlainPoint)), "a plain alias is the type it names")
    testing.expect(t, !same(point, hash_of(DistinctPoint)), "a distinct alias is a type of its own")
    testing.expect(t, !same(point, hash_of(Swapped)), "members in another order make another type")
    testing.expect(t, !same(point, hash_of(Place)), "the same members under another name make another type")
    testing.expect(t, !same(point, hash_of(Wide)), "a member of another type makes another type")
    // int is laid out as i64, under no name of its own
    testing.expect(t, same(hash_of(int), hash_of(i64)), "int is laid out as i64, under no name of its own")
    testing.expect(t, !same(hash_of(i64), hash_of(u64)), "signedness is part of an integer's schema")
    // A type that refers to itself: described once, and the same each time
    testing.expect(t, same(hash_of(Node), hash_of(Node)), "a type that refers to itself hashes the same each time")
    testing.expect(t, !same(hash_of(Node), hash_of(Point)), "and isn't another type's")
    testing.expect(t, !same(hash_of(Shape), hash_of(Color)), "a union and an enum differ")
    testing.expect(t, !same(hash_of(Handler), hash_of(Shape)), "a function type and a union differ")
    return .Ok
}

writes_a_types_bytes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // "HSCH", version 1, two types (it and i32), a struct (14) of 8 bytes named "Point"
    bytes : u8[..]
    defer runtime.array_free(&bytes)
    schema.write(type_info_of(Point), &bytes)
    expected :: u8.[0x48, 0x53, 0x43, 0x48, 1, 0, 2, 0, 0, 0, 14, 8, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0x50, 0x6f, 0x69, 0x6e, 0x74]
    testing.require_ge(t, bytes.count, expected.count, "a struct's schema has its header, kind, size and name, at least")?
    for byte, i in expected {
        if i < bytes.count {
            testing.expect_eq(t, bytes[i], byte, "the header, two types, a struct of 8 bytes, then its name")
        }
    }
    return .Ok
}

/**
 * Read 8 bytes as a little-endian number.
 *
 * @param bytes What's read.
 * @param at The offset of the first byte.
 * @return The number; bytes past the end count as 0.
 */
word_at :: fn(bytes: u8[], at: usize) -> u64 {
    result : u64 = 0
    for i in cast[usize](0)..<8 {
        if at + i < bytes.count {
            result |= cast[u64](bytes[at + i]) << (8 * i)
        }
    }
    return result
}

/**
 * View bytes as text.
 *
 * @param bytes What's viewed.
 * @param at The offset of the text's first byte.
 * @param count How many bytes the text has.
 * @return The text, a view of bytes; "" when count is 0 or it runs past the end.
 */
text_at :: fn(bytes: u8[], at: usize, count: usize) -> string {
    if at + count > bytes.count || count == 0 || at >= bytes.count {
        return ""
    }
    return string_of(&bytes[at], count)
}

/**
 * Find where a member of Item is, from its type information.
 *
 * @param name The member's name.
 * @return Its offset in bytes; 0 if Item has no member so named.
 */
offset_in_item :: fn(name: string) -> usize {
    for member in cast[ptr[compiler.TypeInfoStruct]](type_info_of(Item)).members {
        if member.name == name {
            return member.offset
        }
    }
    return 0
}

writes_values_for_elsewhere #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // On the heap, so a value pointing to them can go in an any
    first_scores : i32[..]
    defer runtime.array_free(&first_scores)
    for score in i32.[1, 2, 3] {
        runtime.array_add(&first_scores, score)
    }
    first := runtime.new(Item)
    defer runtime.free(first)
    first^ = Item.{id = 7, name = "first", scores = first_scores, extra = bit_cast[any](AnyParts.{data = cast[rawptr](first), type = Item})}
    second := Item.{id = 9, name = "second", next = first}
    bytes : u8[..]
    defer runtime.array_free(&bytes)
    schema.write_value(second, &bytes)
    name_at :: offset_in_item("name")
    scores_at :: offset_in_item("scores")
    next_at :: offset_in_item("next")
    extra_at :: offset_in_item("extra")
    testing.expect_eq(t, word_at(bytes, 0) & 0xffffffff, 9, "the value itself comes first")
    testing.expect_eq(t, text_at(bytes, cast[usize](word_at(bytes, name_at + 8)), 6), "second", "its string's bytes are where its data says, from the start")
    // What next pointed to, after it, with its own string and view after that
    at :: cast[usize](word_at(bytes, next_at))
    testing.require(t, at != 0, "what next points to is written, at a distance from the start")?
    testing.expect_eq(t, word_at(bytes, at) & 0xffffffff, 7, "what next points to is the first item")
    testing.expect_eq(t, text_at(bytes, cast[usize](word_at(bytes, at + name_at + 8)), 5), "first", "the item pointed to has its own string after it")
    testing.expect_eq(t, word_at(bytes, at + scores_at), 3, "the item pointed to keeps its view's count")
    scores :: cast[usize](word_at(bytes, at + scores_at + 8))
    testing.expect_eq(t, word_at(bytes, scores) & 0xffffffff, 1, "the view's elements are written, its first")
    testing.expect_eq(t, word_at(bytes, scores + 8) & 0xffffffff, 3, "and its last")
    // Nothing elsewhere can use an any, and the end of the chain is null
    testing.expect_eq(t, word_at(bytes, at + extra_at), 0, "an any's data is written as null, as nothing elsewhere can use it")
    testing.expect_eq(t, word_at(bytes, at + extra_at + 8), 0, "and its type too")
    testing.expect_eq(t, word_at(bytes, at + next_at), 0, "the end of the chain is null")
    // No address of the writer's in it
    for i in cast[usize](0)..<bytes.count {
        found :: word_at(bytes, i)
        testing.expect(t, found != cast[u64](cast[usize](first)) && found != cast[u64](cast[usize](first_scores.data)),
            "no address of the writer's is in what it writes for elsewhere")
    }
    return .Ok
}

/**
 * Write a value and read it back.
 *
 * @tparam T The value's type.
 * @param value The value.
 * @return Whether it was read back.
 */
reads_back :: fn[T](value: T) -> bool {
    bytes : u8[..]
    defer runtime.array_free(&bytes)
    schema.write_value(value, &bytes)
    return schema.read_value[T](bytes[0..<bytes.count]) is_some
}

reads_empty_strings_and_views_back #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Empty, but pointing somewhere: their writer gives where their bytes would go, past what it writes
    numbers :: u64.[1, 2]
    words :: string.["a", "bc"]
    testing.expect(t, reads_back(""), "an empty string pointing to a literal is read back")
    testing.expect(t, reads_back(numbers[0..<0]), "an empty view of an array is read back")
    testing.expect(t, reads_back(words[0..<0]), "an empty view of strings is read back")
    none : u64[]
    testing.expect(t, reads_back(none), "a null view is read back")
    listed : string[] = words
    testing.expect(t, reads_back(listed), "a view of strings is read back")
    return .Ok
}

agrees_with_stds_blake3 #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Across chunk and block edges
    data : u8[5000]
    for i in cast[usize](0)..<data.count {
        data[i] = cast[u8](i * 7 + i / 251)
    }
    for count in usize.[0, 1, 63, 64, 65, 1023, 1024, 1025, 2048, 3073, 4096, 5000] {
        expected : u8[32]
        if count > data.count {
            testing.fail(t, "every count hashed is within the data")
            return .Error(.Failed)
        }
        crypto.blake3(data[0..<count], expected)
        testing.expect(t, same(runtime.hash_blake3(data[0..<count]), expected), "base's BLAKE3 and std's are the same function")
    }
    return .Ok
}

Mood :: enum {
    Calm = 3,
    Busy = 9,
}

/**
 * Check that render gives a value, from its schema and the value written elsewhere, as output_format writes it.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param format_string The format, with one %.
 * @param value The value.
 * @param message Why they should be alike, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return True if they were alike; false, the failure recorded with both, if not.
 */
expect_renders_alike :: fn(t: ptr[mut testing.T], format_string: string, value: any, message: string,
    location := #caller_location) -> bool {
    expected_buffer := runtime.output_buffer(.OUTPUT)
    expected_buffer.capture = true
    runtime.output_format(&expected_buffer, format_string, value)
    expected :: string_of(&expected_buffer.bytes[0], expected_buffer.count)
    schema_bytes : u8[..]
    defer runtime.array_free(&schema_bytes)
    value_bytes : u8[..]
    defer runtime.array_free(&value_bytes)
    schema.write(type_info_of(value.type), &schema_bytes)
    schema.write_value(value, &value_bytes)
    rendered : u8[..]
    defer runtime.array_free(&rendered)
    arguments :: schema.Argument.[schema.Argument.{schema = schema_bytes, value = value_bytes}]
    schema.render(format_string, arguments, &rendered)
    rendered_text :: if rendered.count == 0 { "" } else { string_of(&rendered[0], rendered.count) }
    return testing.expect_eq(t, rendered_text, expected, message, location)
}

renders_values_as_output_format_does #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    expect_renders_alike(t, "count % of", cast[u32](0), "a zero is a digit, not nothing")
    expect_renders_alike(t, "%", cast[i64](0), "a zero alone is a digit")
    expect_renders_alike(t, "%{#018x}", cast[u64](0x4100000), "a padded hexadecimal number with its prefix")
    expect_renders_alike(t, "count % of", cast[u32](1234), "an unsigned number between text")
    expect_renders_alike(t, "[%]", cast[i16](-300), "a negative number keeps its sign")
    expect_renders_alike(t, "%", true, "a boolean is a word")
    expect_renders_alike(t, "name: %!", "second", "a string's bytes are followed to where they were written")
    expect_renders_alike(t, "%{>8}|", "right", "a string padded to the right")
    expect_renders_alike(t, "%{08x}", cast[u64](0xbeef), "a hexadecimal number padded with zeros")
    expect_renders_alike(t, "% and %", Mood.Busy, "an enum member by name, and a % with nothing for it")
    expect_renders_alike(t, "%", cast[Mood](4), "an enum value without a member")
    expect_renders_alike(t, "%", Color.Green, "a backed enum's member by name")
    expect_renders_alike(t, "%", 1.5, "an f64")
    expect_renders_alike(t, "%", cast[f32](0.1), "an f32, as the shortest text that reads back as it")
    expect_renders_alike(t, "%", Point.{x = 1, y = 2}, "a struct, member by member")
    expect_renders_alike(t, "%{+d} 100%%", cast[i8](-5), "a signed number with its sign always, and an escaped %")
    expect_renders_alike(t, "%", 'x', "a character")
    expect_renders_alike(t, "%{x}", Color.Red, "an enum member as its hexadecimal value")
    return .Ok
}

renders_arguments_by_number #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    first : u8[..]
    defer runtime.array_free(&first)
    second : u8[..]
    defer runtime.array_free(&second)
    first_schema : u8[..]
    defer runtime.array_free(&first_schema)
    second_schema : u8[..]
    defer runtime.array_free(&second_schema)
    schema.write(type_info_of(int), &first_schema)
    schema.write_value(cast[int](7), &first)
    schema.write(type_info_of(string), &second_schema)
    schema.write_value("seven", &second)
    rendered : u8[..]
    defer runtime.array_free(&rendered)
    arguments :: schema.Argument.[schema.Argument.{schema = first_schema, value = first},
        schema.Argument.{schema = second_schema, value = second}]
    schema.render("%2 is %1, %3", arguments, &rendered)
    rendered_text :: if rendered.count == 0 { "" } else { string_of(&rendered[0], rendered.count) }
    testing.expect_eq(t, rendered_text, "seven is 7, %!", "%N takes the Nth argument, and one past the last is marked")
    return .Ok
}

/**
 * Give the schema hash of Entry's parameter i's type.
 *
 * @param i The parameter's index, 0 to 5; past 5, Node's.
 * @return Its type's hash, as hash_of gives it.
 */
entry_hash :: fn(i: usize) -> u8[32] {
    return if i == 0 { hash_of(u64) } else if i == 1 { hash_of(string) } else if i == 2 { hash_of(Item) } else if i == 3 { hash_of(Shape?) }
        else if i == 4 { hash_of(Color) } else { hash_of(Node) }
}

/**
 * Find the place of a function's parameter i's type, in the schema it was read from.
 *
 * @param entry The function's type, read back.
 * @param i The parameter's index.
 * @return The type's place; schema.NOWHERE when the function has no parameter i.
 */
input_type :: fn(entry: ptr[schema.Type], i: usize) -> usize {
    for input, j in entry.inputs {
        if j == i {
            return input.type
        }
    }
    return schema.NOWHERE
}

reads_schemas_back #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // An entry's parameters, their names, kinds and members, and each one's schema written alone
    bytes : u8[..]
    defer runtime.array_free(&bytes)
    schema.write(type_info_of(Entry), &bytes)
    parsed :: schema.parse(bytes)
    read := testing.require_some(t, parsed, "a schema written reads back")?
    defer schema.free(&read)
    entry :: testing.require_some(t, schema.type_in(&read, 0), "its root type is at place 0")?
    testing.expect(t, entry.kind == .Function, "Entry is a function type")
    testing.require_eq(t, entry.inputs.count, 6, "it has its six parameters")?
    testing.expect_eq(t, entry.outputs.count, 1, "and its one result")
    names :: string.["count", "label", "item", "shape", "color", "node"]
    for input, i in entry.inputs {
        if i < names.count {
            testing.expect_eq(t, input.name, names[i], "each parameter keeps its name, in order")
        }
        testing.expect(t, same(schema.hash_rooted(&read, input.type), entry_hash(i)), "each parameter's type hashes as its own schema does")
    }
    testing.expect(t, same(schema.hash_rooted(&read, 0), hash_of(Entry)), "the whole hashes as the schema written does")
    item :: testing.require_some(t, schema.type_in(&read, input_type(entry, 2)), "the item parameter's type is there")?
    testing.expect(t, item.kind == .Struct && item.name == "Item", "it's the struct Item")
    testing.expect(t, item.members.count == 5 && item.members[1].name == "name", "with its five members, in order")
    testing.expect(t, item.members.count == 5 && item.members[1].offset == cast[u64](offset_in_item("name")), "each where the type puts it")
    color :: testing.require_some(t, schema.type_in(&read, input_type(entry, 4)), "the color parameter's type is there")?
    testing.expect(t, color.kind == .Enum && color.constants.count == 2, "it's an enum of two constants")
    testing.expect(t, color.constants.count == 2 && color.constants[1].name == "Green" && color.constants[1].value == 2, "each with its name and value")
    count :: testing.require_some(t, schema.type_in(&read, input_type(entry, 0)), "the count parameter's type is there")?
    testing.expect(t, count.kind == .Integer && !count.is_signed && count.size == 8, "it's an unsigned 8-byte integer, u64")
    shape :: testing.require_some(t, schema.type_in(&read, input_type(entry, 3)), "the shape parameter's type is there")?
    testing.expect(t, shape.kind == .Union && shape.variants.count == 2, "an optional is a union of two")
    testing.expect(t, shape.variants.count == 2 && shape.variants[1].name == "Some", "its second variant Some")
    return .Ok
}

refuses_a_schema_cut_short_or_with_more_after #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    bytes : u8[..]
    defer runtime.array_free(&bytes)
    schema.write(type_info_of(Entry), &bytes)
    shorter : u8[..]
    defer runtime.array_free(&shorter)
    for byte, i in bytes {
        if i + 1 < bytes.count {
            runtime.array_add(&shorter, byte)
        }
    }
    testing.expect(t, schema.parse(shorter) is_none, "without its last byte, it isn't a schema")
    longer : u8[..]
    defer runtime.array_free(&longer)
    for byte in bytes {
        runtime.array_add(&longer, byte)
    }
    runtime.array_add(&longer, cast[u8](0))
    testing.expect(t, schema.parse(longer) is_none, "with a byte after it, it isn't a schema")
    return .Ok
}

leaves_output_alone_when_memory_runs_out #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // try_write and try_write_value with each of their allocations failing in turn, then with none failing
    first := Item.{id = 7, name = "first"}
    second := Item.{id = 9, name = "second", next = &first}
    fail_at : u64 = 1
    loop {
        made :: memory.make_failing(fail_at)
        failing :: testing.require_some(t, made, "a failing allocator can be made")?
        schema_bytes : u8[..]
        value_bytes : u8[..]
        schema_error : runtime.AllocatorError? = null
        value_error : runtime.AllocatorError? = null
        push_context failing_context (allocator = memory.failing_allocator(failing)) {
            schema_error = schema.try_write(type_info_of(Item), &schema_bytes)
            value_error = schema.try_write_value(second, &value_bytes)
        }
        failed :: failing.failed
        written :: schema_error == null && value_error == null
        schema_kept :: schema_error == null || schema_bytes.count == 0
        value_kept :: value_error == null || value_bytes.count == 0
        whole :: !written || (same(runtime.hash_blake3(schema_bytes), hash_of(Item)) && word_at(value_bytes, 0) & 0xffffffff == 9)
        runtime.array_free(&schema_bytes)
        runtime.array_free(&value_bytes)
        live :: failing.live
        memory.free_failing(failing)
        testing.require(t, failed != written, "an error is given exactly when an allocation failed")?
        testing.require(t, schema_kept && value_kept, "after an error, what was written to is as it was, empty")?
        testing.require(t, whole, "with no allocation failing, both are written whole")?
        testing.require_eq(t, live, 0, "nothing allocated is kept, failing or not")?
        if !failed {
            return .Ok
        }
        fail_at += 1
        testing.require_le(t, fail_at, 1000, "writing needs fewer than 1000 allocations, so it ends without failing")?
    }
}
