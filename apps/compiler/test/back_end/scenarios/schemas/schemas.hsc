package schemas

import compiler from "base"
import runtime from "base"
import schema from "std"

/*
 * std's schema: a type's description serialized canonically, and its hash, the same at compile time and at run time.
 * A plain alias is the type it names, a distinct one isn't; what's laid out alike under the same names hashes alike,
 * and a different name, member order or member type doesn't; a type that refers to itself is described once. A value
 * written for elsewhere has what it points to after it, at distances from its start, and no address of the writer's.
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
    return check_values()
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
