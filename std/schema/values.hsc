package schema

import runtime from "base"

/*
 * A value written for something that reads it elsewhere, by its type's schema (docs/types.md, Schemas): its bytes in
 * its own layout, then what it points to, copied after it, each pointer in it replaced by the distance from the
 * value's start to what it pointed to, or 0 for null. So nothing written says where anything was in the writer's
 * memory, and a reader with the schema finds everything from the value's start.
 *
 * Followed: a string's bytes, a cstring's to its zero (at most CSTRING_LIMIT of them), an array view's and a dynamic
 * array's elements (a dynamic array's capacity and allocator written as 0), what a pointer points to, up to
 * MAX_DEPTH pointers deep, and an optional pointer's when it's Some. Written as 0, as nothing elsewhere could use
 * them: rawptr, functions, type values, any, a pointer past MAX_DEPTH, and a #union struct holding pointers, since
 * which member it holds isn't known. A relative pointer is a distance already, and is written as it is.
 */

/**
 * How many pointers deep a value is followed, so one that points to itself is written once per level, and ends.
 * A pointer deeper than this is written as 0.
 */
MAX_DEPTH :: runtime.SCHEMA_MAX_DEPTH
/** The most bytes of a cstring followed, its zero included; a longer one is cut to this many, without its zero. */
CSTRING_LIMIT : usize : runtime.SCHEMA_CSTRING_LIMIT

/**
 * Write a value to the end of an array, with what it points to after it, for something that reads it elsewhere.
 *
 * Without the memory, calls context.assertion_handler, as array_add does; try_write_value is for code that handles
 * running out.
 *
 * @param value The value; every pointer in it that's followed has to point to memory that can be read.
 * @param into The array the bytes are added to, grown with its own allocator; what it held already is left as it is,
 *     and distances in what's written are from where the value starts in it.
 * @param location Where the call is, given to the assertion handler; the caller's location by default.
 */
write_value :: fn(value: any, into: ptr[mut u8[..]], location := #caller_location) {
    runtime.schema_write_value(value, into, location)
}

/**
 * Write a value to the end of an array, with what it points to after it, giving back the error when there isn't the
 * memory.
 *
 * @param value The value; every pointer in it that's followed has to point to memory that can be read.
 * @param into The array the bytes are added to, grown with its own allocator; what it held already is left as it is,
 *     and distances in what's written are from where the value starts in it.
 * @return Null when the whole value was written; otherwise the allocator's error, and into's count is as it was.
 */
try_write_value :: fn(value: any, into: ptr[mut u8[..]]) -> runtime.AllocatorError? {
    return runtime.schema_try_write_value(value, into)
}
