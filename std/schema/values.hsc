package schema

import compiler from "base"
import runtime from "base"
import reflection from "std"

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

// How many pointers deep a value is followed, so one that points to itself is written once per level, and ends.
MAX_DEPTH :: 8
// The most bytes of a cstring followed, its zero included.
CSTRING_LIMIT : usize : 4096

// A value written to the end of into, with what it points to after it.
write_value :: fn(value: any, into: ptr[mut u8[..]]) {
    info :: type_info_of(value.type)
    start :: into.count
    copy_in(into, value.data, info.size)
    fix(into, start, start, info, 0)
}

// count bytes from data appended.
copy_in :: fn(into: ptr[mut u8[..]], data: rawptr, count: usize) {
    for byte in view_of(cast[ptr[u8]](data), count) {
        runtime.array_add(into, byte)
    }
}

word :: fn(into: ptr[mut u8[..]], at: usize) -> u64 {
    bytes : u8[] = into^
    result : u64 = 0
    for i in cast[usize](0)..<8 {
        j :: at + i
        if j < bytes.count {
            result |= cast[u64](bytes[j]) << (8 * i)
        }
    }
    return result
}

set_word :: fn(into: ptr[mut u8[..]], at: usize, value: u64) {
    bytes : mut u8[] = into^
    for i in cast[usize](0)..<8 {
        j :: at + i
        if j < bytes.count {
            bytes[j] = cast[u8]((value >> (8 * i)) & 0xff)
        }
    }
}

zero :: fn(into: ptr[mut u8[..]], at: usize, count: usize) {
    bytes : mut u8[] = into^
    for i in cast[usize](0)..<count {
        j :: at + i
        if j < bytes.count {
            bytes[j] = 0
        }
    }
}

/*
 * The pointer word at `at` replaced by what it pointed to, count bytes of it, copied to the end: its distance from
 * start, or 0 if it was null. Where the copy is, or null if there's none to follow into.
 */
follow :: fn(into: ptr[mut u8[..]], start: usize, at: usize, count: usize) -> usize? {
    pointer :: word(into, at)
    if pointer == 0 {
        return null
    }
    copied :: into.count
    copy_in(into, cast[rawptr](cast[uintptr](pointer)), count)
    set_word(into, at, cast[u64](copied - start))
    return copied
}

/*
 * The pointers in the part of into at `at`, a value of type, each followed or written as 0. Positions are kept as
 * indices, since into grows as what's followed is appended.
 */
fix :: fn(into: ptr[mut u8[..]], start: usize, at: usize, type: ptr[compiler.TypeInfo], depth: int) {
    info :: reflection.unaliased(type)
    variant :: info.variant
    if variant == .STRING {
        if cast[ptr[compiler.TypeInfoString]](info).is_raw {
            pointer :: word(into, at)
            if pointer != 0 {
                bytes :: view_of(cast[ptr[u8]](cast[uintptr](pointer)), CSTRING_LIMIT)
                length := CSTRING_LIMIT
                for byte, i in bytes {
                    if byte == 0 {
                        length = i + 1
                        break
                    }
                }
                _ = follow(into, start, at, length)
            }
            return void
        }
        // count, then data
        _ = follow(into, start, at + 8, cast[usize](word(into, at)))
    }
    else if variant == .ARRAY {
        fix_array(into, start, at, cast[ptr[compiler.TypeInfoArray]](info), 0, depth)
    }
    else if variant == .POINTER {
        pointer :: cast[ptr[compiler.TypeInfoPointer]](info)
        if pointer.is_relative {
            return void
        }
        fix_pointer(into, start, at, pointer.base_type, depth)
    }
    else if variant == .STRUCT {
        structure :: cast[ptr[compiler.TypeInfoStruct]](info)
        if structure.is_union {
            if holds_pointers(info, 0) {
                zero(into, at, info.size)
            }
            return void
        }
        for member in structure.members {
            fix(into, start, at + member.offset, member.member_type, depth)
        }
    }
    else if variant == .UNION {
        union_info :: cast[ptr[compiler.TypeInfoUnion]](info)
        if union_info.null_is_none {
            // Just the pointer: Some's only value
            for each in union_info.variants {
                if each.types.count == 1 {
                    fix(into, start, at, each.types[0], depth)
                    break
                }
            }
            return void
        }
        tag_size :: match union_info.tag_type {
            case Some(tag) => tag.size
            case None => cast[usize](0)
        }
        tag :: cast[usize](word(into, at) & mask_of(tag_size))
        if tag >= union_info.variants.count {
            return void
        }
        chosen :: union_info.variants[tag]
        for held, i in chosen.types {
            if i < chosen.offsets.count {
                fix(into, start, at + chosen.offsets[i], held, depth)
            }
        }
    }
    else if variant == .ANY || variant == .FUNCTION || variant == .TYPE {
        zero(into, at, info.size)
    }
}

// What a pointer at `at` points to, of type pointed, followed, unless it's a rawptr or too deep.
fix_pointer :: fn(into: ptr[mut u8[..]], start: usize, at: usize, pointed: ptr[compiler.TypeInfo]?, depth: int) {
    if (pointed is_none) || depth >= MAX_DEPTH {
        set_word(into, at, 0)
        return void
    }
    target :: pointed or_return void
    match follow(into, start, at, target.size) {
        case Some(copied) => fix(into, start, copied, target, depth + 1)
        case None => {}
    }
}

// The array at `at`, from dimension on: a static one's elements in place, a view's or dynamic one's copied after.
fix_array :: fn(into: ptr[mut u8[..]], start: usize, at: usize, info: ptr[compiler.TypeInfoArray], dimension: usize, depth: int) {
    dimensions :: info.dimensions
    if dimension >= dimensions.count {
        fix(into, start, at, info.base_type, depth)
        return void
    }
    element_size :: reflection.dimension_element_size(info, dimension)
    array_type :: dimensions[dimension].type
    elements := at
    count := dimensions[dimension].count
    if array_type == .VIEW || array_type == .DYNAMIC {
        // count, then data; a dynamic array's capacity and allocator after them mean nothing elsewhere
        count = cast[usize](word(into, at))
        if array_type == .DYNAMIC {
            zero(into, at + 16, size_of(runtime.ResizableArray) - 16)
        }
        elements = follow(into, start, at + 8, count * element_size) or_return void
    }
    if !holds_pointers_array(info, dimension) {
        return void
    }
    for index in cast[usize](0)..<count {
        fix_array(into, start, elements + index * element_size, info, dimension + 1, depth)
    }
}

// The bits of a tag of size bytes.
mask_of :: fn(size: usize) -> u64 {
    if size >= 8 {
        return 0xffffffffffffffff
    }
    return (cast[u64](1) << (8 * size)) - 1
}

// Whether a value of type holds anything fix changes, looking no deeper than MAX_DEPTH types in.
holds_pointers :: fn(type: ptr[compiler.TypeInfo], depth: int) -> bool {
    if depth >= MAX_DEPTH {
        return true
    }
    info :: reflection.unaliased(type)
    variant :: info.variant
    if variant == .STRING || variant == .POINTER || variant == .ANY || variant == .FUNCTION || variant == .TYPE || variant == .UNION {
        return true
    }
    if variant == .ARRAY {
        return holds_pointers_array(cast[ptr[compiler.TypeInfoArray]](info), 0)
    }
    if variant == .STRUCT {
        for member in cast[ptr[compiler.TypeInfoStruct]](info).members {
            if holds_pointers(member.member_type, depth + 1) {
                return true
            }
        }
    }
    return false
}

holds_pointers_array :: fn(info: ptr[compiler.TypeInfoArray], dimension: usize) -> bool {
    for i in dimension..<info.dimensions.count {
        if info.dimensions[i].type != .STATIC {
            return true
        }
    }
    return holds_pointers(info.base_type, 0)
}
