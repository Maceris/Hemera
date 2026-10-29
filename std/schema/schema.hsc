package schema

import compiler from "base"
import runtime from "base"

/*
 * A type's schema (docs/types.md, Schemas): its type information serialized canonically, so the same type gives the
 * same bytes in every build, every program and on every host, and the BLAKE3-256 hash of those bytes, which names the
 * type. It covers what a value's layout and its names are: each type's kind and size, the names of structs, unions,
 * enums and distinct aliases, their members and variants in order with their offsets, and the types they hold, but
 * nothing about where the type was declared or what's documented about it. The same code runs at compile time, in
 * #run, and at run time.
 *
 * The bytes: "HSCH", the format's version (u16), the number of types (u32), then each type, the one described first:
 * its kind (u8) and size (u64), then what its kind has, with each type it refers to by its place among them (u32),
 * counted in the order they're first reached, breadth first, so a type that refers to itself is described once.
 * Numbers are little-endian; a name is its length (u32) and its bytes. Plain aliases are the type they name.
 *
 * The code is base's (runtime.schema_write and the rest, schema.hsc), which the SlopOS logger writes records with.
 */

VERSION : u16 : runtime.SCHEMA_VERSION

// What each kind is in the bytes: fixed, whatever compiler.TypeInfoVariant's order becomes.
Kind :: alias runtime.SchemaKind

// A type's schema written to the end of into.
write :: fn(type: ptr[compiler.TypeInfo], into: ptr[mut u8[..]]) {
    runtime.schema_write(type, into)
}

// A type's schema hash: BLAKE3-256 of its schema's bytes.
hash :: fn(type: ptr[compiler.TypeInfo]) -> u8[32] {
    return runtime.schema_hash(type)
}
