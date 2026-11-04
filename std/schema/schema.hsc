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

/** The version of the schema format, written after "HSCH"; it changes when the bytes for the same type would. */
VERSION : u16 : runtime.SCHEMA_VERSION

/** What each kind is in the bytes: fixed, whatever compiler.TypeInfoVariant's order becomes. */
Kind :: alias runtime.SchemaKind

/**
 * Write a type's schema to the end of an array.
 *
 * Without the memory, calls context.assertion_handler, as array_add does; try_write is for code that handles running
 * out.
 *
 * @param type The type whose schema is written, as type_info_of gives it; a plain alias is described as the type it
 *     names.
 * @param into The array the bytes are added to, grown with its own allocator; what it held already is left as it is.
 * @param location Where the call is, given to the assertion handler; the caller's location by default.
 */
write :: fn(type: ptr[compiler.TypeInfo], into: ptr[mut u8[..]], location := #caller_location) {
    runtime.schema_write(type, into, location)
}

/**
 * Write a type's schema to the end of an array, giving back the error when there isn't the memory.
 *
 * A list of the types reached is kept on context.allocator while it runs, and freed before it returns.
 *
 * @param type The type whose schema is written; a plain alias is described as the type it names.
 * @param into The array the bytes are added to, grown with its own allocator; what it held already is left as it is.
 * @return Null when the whole schema was written; otherwise the allocator's error, and into's count is as it was, so
 *     nothing of the schema is left in it.
 */
try_write :: fn(type: ptr[compiler.TypeInfo], into: ptr[mut u8[..]]) -> runtime.AllocatorError? {
    return runtime.schema_try_write(type, into)
}

/**
 * Compute a type's schema hash, which names the type the same in every build, program and host.
 *
 * The schema's bytes are kept on context.allocator while they're hashed, and freed after. Without the memory for
 * them, calls context.assertion_handler, as write does.
 *
 * @param type The type whose schema is hashed; a plain alias hashes as the type it names.
 * @return BLAKE3-256 of the type's schema's bytes: equal for two types exactly when their schemas are.
 */
hash :: fn(type: ptr[compiler.TypeInfo]) -> u8[32] {
    return runtime.schema_hash(type)
}
