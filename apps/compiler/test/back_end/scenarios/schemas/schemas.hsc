package schemas

import runtime from "base"
import schema from "std"

/*
 * std's schema: a type's description serialized canonically, and its hash, the same at compile time and at run time.
 * A plain alias is the type it names, a distinct one isn't; what's laid out alike under the same names hashes alike,
 * and a different name, member order or member type doesn't; a type that refers to itself is described once. main
 * returns 42 if each holds.
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
    return 42
}
