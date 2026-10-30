package schemas

import compiler from "base"
import runtime from "base"
import crypto from "std"
import schema from "std"

/*
 * std's schema: a type's description serialized canonically, and its hash, the same at compile time and at run time.
 * A plain alias is the type it names, a distinct one isn't; what's laid out alike under the same names hashes alike,
 * and a different name, member order or member type doesn't; a type that refers to itself is described once. A value
 * written for elsewhere has what it points to after it, at distances from its start, and no address of the writer's,
 * and reads back as the text base's output_format gives it. base's own BLAKE3, which hashes schemas, agrees with std's.
 * main returns 42 if each holds.
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

COMPILED_POINT :: #run schema.hash(type_info_of(Point))

same :: fn(a: u8[32], b: u8[32]) -> bool {
    for byte, i in a {
        if byte != b[i] {
            return false
        }
    }
    return true
}

hash_of :: fn(type: type) -> u8[32] {
    return schema.hash(type_info_of(type))
}

main :: fn() -> int {
    point :: hash_of(Point)
    if !same(point, COMPILED_POINT) {
        return 1
    }
    if !same(point, hash_of(PlainPoint)) || same(point, hash_of(DistinctPoint)) {
        return 2
    }
    if same(point, hash_of(Swapped)) || same(point, hash_of(Place)) || same(point, hash_of(Wide)) {
        return 3
    }
    // int is laid out as i64, under no name of its own
    if !same(hash_of(int), hash_of(i64)) || same(hash_of(i64), hash_of(u64)) {
        return 4
    }
    // A type that refers to itself: described once, and the same each time
    if !same(hash_of(Node), hash_of(Node)) || same(hash_of(Node), hash_of(Point)) {
        return 5
    }
    if same(hash_of(Shape), hash_of(Color)) || same(hash_of(Handler), hash_of(Shape)) {
        return 6
    }
    // The bytes: "HSCH", version 1, two types (it and i32), a struct (14) of 8 bytes named "Point"
    bytes : u8[..]
    defer runtime.array_free(&bytes)
    schema.write(type_info_of(Point), &bytes)
    expected :: u8.[0x48, 0x53, 0x43, 0x48, 1, 0, 2, 0, 0, 0, 14, 8, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0x50, 0x6f, 0x69, 0x6e, 0x74]
    if bytes.count < expected.count {
        return 7
    }
    for byte, i in expected {
        if i < bytes.count && bytes[i] != byte {
            return 8
        }
    }
    values :: check_values()
    if values != 42 {
        return values
    }
    hashes :: check_blake3()
    if hashes != 42 {
        return hashes
    }
    return check_render()
}

// base's BLAKE3, for schemas, against std's, across chunk and block edges.
check_blake3 :: fn() -> int {
    data : u8[5000]
    for i in cast[usize](0)..<data.count {
        data[i] = cast[u8](i * 7 + i / 251)
    }
    for count in usize.[0, 1, 63, 64, 65, 1023, 1024, 1025, 2048, 3073, 4096, 5000] {
        expected : u8[32]
        if count > data.count {
            return 21
        }
        crypto.blake3(data[0..<count], expected)
        if !same(runtime.hash_blake3(data[0..<count]), expected) {
            return 20
        }
    }
    return 42
}

Mood :: enum {
    Calm = 3,
    Busy = 9,
}

// What output_format writes for a value, and what render gives from its schema and value written elsewhere.
renders_alike :: fn(format_string: string, value: any) -> bool {
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
    return rendered.count == expected.count && (rendered.count == 0 || string_of(&rendered[0], rendered.count) == expected)
}

check_render :: fn() -> int {
    if !renders_alike("count % of", cast[u32](0)) || !renders_alike("%", cast[i64](0)) || !renders_alike("%{#018x}", cast[u64](0x4100000)) {
        return 36
    }
    if !renders_alike("count % of", cast[u32](1234)) || !renders_alike("[%]", cast[i16](-300)) || !renders_alike("%", true) {
        return 30
    }
    if !renders_alike("name: %!", "second") || !renders_alike("%{>8}|", "right") || !renders_alike("%{08x}", cast[u64](0xbeef)) {
        return 31
    }
    if !renders_alike("% and %", Mood.Busy) || !renders_alike("%", cast[Mood](4)) || !renders_alike("%", Color.Green) {
        return 32
    }
    if !renders_alike("%", 1.5) || !renders_alike("%", cast[f32](0.1)) || !renders_alike("%", Point.{x = 1, y = 2}) {
        return 33
    }
    if !renders_alike("%{+d} 100%%", cast[i8](-5)) || !renders_alike("%", 'x') || !renders_alike("%{x}", Color.Red) {
        return 34
    }
    // Two arguments, by number
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
    if rendered.count == 0 || string_of(&rendered[0], rendered.count) != "seven is 7, %!" {
        return 35
    }
    return 42
}

word_at :: fn(bytes: u8[], at: usize) -> u64 {
    result : u64 = 0
    for i in cast[usize](0)..<8 {
        if at + i < bytes.count {
            result |= cast[u64](bytes[at + i]) << (8 * i)
        }
    }
    return result
}

text_at :: fn(bytes: u8[], at: usize, count: usize) -> string {
    if at + count > bytes.count || count == 0 || at >= bytes.count {
        return ""
    }
    return string_of(&bytes[at], count)
}

// Where a member of Item is, from its type information.
offset_in_item :: fn(name: string) -> usize {
    for member in cast[ptr[compiler.TypeInfoStruct]](type_info_of(Item)).members {
        if member.name == name {
            return member.offset
        }
    }
    return 0
}

check_values :: fn() -> int {
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
    if word_at(bytes, 0) & 0xffffffff != 9 || text_at(bytes, cast[usize](word_at(bytes, name_at + 8)), 6) != "second" {
        return 10
    }
    // What next pointed to, after it, with its own string and view after that
    at :: cast[usize](word_at(bytes, next_at))
    if at == 0 || word_at(bytes, at) & 0xffffffff != 7 || text_at(bytes, cast[usize](word_at(bytes, at + name_at + 8)), 5) != "first" {
        return 11
    }
    if word_at(bytes, at + scores_at) != 3 {
        return 12
    }
    scores :: cast[usize](word_at(bytes, at + scores_at + 8))
    if word_at(bytes, scores) & 0xffffffff != 1 || word_at(bytes, scores + 8) & 0xffffffff != 3 {
        return 13
    }
    // Nothing elsewhere can use an any, and the end of the chain is null
    if word_at(bytes, at + extra_at) != 0 || word_at(bytes, at + extra_at + 8) != 0 || word_at(bytes, at + next_at) != 0 {
        return 14
    }
    // No address of the writer's in it
    for i in cast[usize](0)..<bytes.count {
        found :: word_at(bytes, i)
        if found == cast[u64](cast[usize](first)) || found == cast[u64](cast[usize](first_scores.data)) {
            return 15
        }
    }
    return 42
}
