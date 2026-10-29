package runtime

import compiler from "base"

/*
 * A type's schema (docs/types.md, Schemas): its type information serialized canonically, so the same type gives the
 * same bytes in every build, every program and on every host, and the BLAKE3-256 hash of those bytes, which names the
 * type. It covers what a value's layout and its names are: each type's kind and size, the names of structs, unions,
 * enums and distinct aliases, their members and variants in order with their offsets, and the types they hold, but
 * nothing about where the type was declared or what's documented about it. The same code runs at compile time, in
 * #run, and at run time. std/schema gives it as schema.write, schema.hash and schema.write_value; it's here, in base,
 * for the SlopOS logger (slop_os_events.hsc).
 *
 * The bytes: "HSCH", the format's version (u16), the number of types (u32), then each type, the one described first:
 * its kind (u8) and size (u64), then what its kind has, with each type it refers to by its place among them (u32),
 * counted in the order they're first reached, breadth first, so a type that refers to itself is described once.
 * Numbers are little-endian; a name is its length (u32) and its bytes. Plain aliases are the type they name.
 */

SCHEMA_VERSION : u16 : 1

// What each kind is in the bytes: fixed, whatever compiler.TypeInfoVariant's order becomes.
SchemaKind :: enum #backed_by(u8) {
    Alias = 1,
    Any = 2,
    Array = 3,
    Boolean = 4,
    Char = 5,
    Complex = 6,
    Enum = 7,
    Float = 8,
    Function = 9,
    Integer = 10,
    Pointer = 11,
    Quaternion = 12,
    String = 13,
    Struct = 14,
    Type = 15,
    Union = 16,
    Vector = 17,
    Void = 18,
}

// A type's schema written to the end of into.
schema_write :: fn(type: ptr[compiler.TypeInfo], into: ptr[mut u8[..]]) {
    // Each type by its address, as a number, so where they're kept isn't a question
    types : uintptr[..]
    defer array_free(&types)
    array_add(&types, cast[uintptr](schema_plain(type)))
    // Each type reached, from the first, adds those it refers to that are new
    at : usize = 0
    loop {
        if at >= types.count {
            break
        }
        schema_reach(cast[ptr[compiler.TypeInfo]](types[at]), &types)
        at += 1
    }
    for byte in u8.[0x48, 0x53, 0x43, 0x48] {
        array_add(into, byte)
    }
    schema_number(into, cast[u64](SCHEMA_VERSION), 2)
    schema_number(into, cast[u64](types.count), 4)
    for each in types {
        schema_describe(cast[ptr[compiler.TypeInfo]](each), &types, into)
    }
}

// A type's schema hash: BLAKE3-256 of its schema's bytes.
schema_hash :: fn(type: ptr[compiler.TypeInfo]) -> u8[32] {
    bytes : u8[..]
    defer array_free(&bytes)
    schema_write(type, &bytes)
    return hash_blake3(bytes)
}

// The type a plain alias names, through any number of them.
schema_plain :: fn(type: ptr[compiler.TypeInfo]) -> ptr[compiler.TypeInfo] {
    result := type
    loop {
        if result.variant != .ALIAS {
            return result
        }
        alias :: cast[ptr[compiler.TypeInfoAlias]](result)
        if alias.is_distinct {
            return result
        }
        result = alias.base_type
    }
}

// A type's place among types, added at the end if it's new.
schema_place :: fn(type: ptr[compiler.TypeInfo], types: ptr[mut uintptr[..]]) -> usize {
    found :: cast[uintptr](schema_plain(type))
    for each, i in types^ {
        if each == found {
            return i
        }
    }
    array_add(types, found)
    return types.count - 1
}

// Every type a type refers to, given a place.
schema_reach :: fn(type: ptr[compiler.TypeInfo], types: ptr[mut uintptr[..]]) {
    variant :: type.variant
    if variant == .ALIAS {
        _ = schema_place(cast[ptr[compiler.TypeInfoAlias]](type).base_type, types)
    }
    else if variant == .ARRAY {
        _ = schema_place(cast[ptr[compiler.TypeInfoArray]](type).base_type, types)
    }
    else if variant == .ENUM {
        _ = schema_place(cast[ptr[compiler.TypeInfoEnum]](type).backing_type, types)
    }
    else if variant == .FUNCTION {
        function :: cast[ptr[compiler.TypeInfoFunction]](type)
        for input in function.input {
            _ = schema_place(input.type, types)
        }
        for output in function.output {
            _ = schema_place(output.type, types)
        }
    }
    else if variant == .POINTER {
        pointer :: cast[ptr[compiler.TypeInfoPointer]](type)
        match pointer.base_type {
            case Some(pointed) => _ = schema_place(pointed, types)
            case None => {}
        }
    }
    else if variant == .STRUCT {
        for member in cast[ptr[compiler.TypeInfoStruct]](type).members {
            _ = schema_place(member.member_type, types)
        }
    }
    else if variant == .UNION {
        union_info :: cast[ptr[compiler.TypeInfoUnion]](type)
        match union_info.tag_type {
            case Some(tag) => _ = schema_place(tag, types)
            case None => {}
        }
        for each_variant in union_info.variants {
            for held in each_variant.types {
                _ = schema_place(held, types)
            }
        }
    }
    else if variant == .VECTOR {
        _ = schema_place(cast[ptr[compiler.TypeInfoVector]](type).element_type, types)
    }
}

// One type's part of the bytes.
schema_describe :: fn(type: ptr[compiler.TypeInfo], types: ptr[mut uintptr[..]], into: ptr[mut u8[..]]) {
    variant :: type.variant
    array_add(into, cast[u8](schema_kind_of(variant)))
    schema_number(into, cast[u64](type.size), 8)
    if variant == .ALIAS {
        alias :: cast[ptr[compiler.TypeInfoAlias]](type)
        schema_name(into, alias.name)
        schema_reference(into, alias.base_type, types)
    }
    else if variant == .ARRAY {
        array :: cast[ptr[compiler.TypeInfoArray]](type)
        schema_reference(into, array.base_type, types)
        schema_number(into, cast[u64](array.dimensions.count), 4)
        for dimension in array.dimensions {
            kind : u8 = if dimension.type == .STATIC { 1 } else if dimension.type == .DYNAMIC { 2 } else { 3 }
            array_add(into, kind)
            schema_number(into, cast[u64](dimension.count), 8)
            schema_flag(into, dimension.is_mutable)
        }
    }
    else if variant == .ENUM {
        enumeration :: cast[ptr[compiler.TypeInfoEnum]](type)
        schema_name(into, enumeration.name)
        schema_reference(into, enumeration.backing_type, types)
        schema_number(into, cast[u64](enumeration.members.count), 4)
        for member, i in enumeration.members {
            schema_name(into, member)
            value : u128 = if i < enumeration.values.count { enumeration.values[i] } else { 0 }
            schema_number(into, cast[u64](value), 8)
            schema_number(into, cast[u64](value >> 64), 8)
        }
    }
    else if variant == .FLOAT {
        schema_endianness(into, cast[ptr[compiler.TypeInfoFloat]](type).endianness)
    }
    else if variant == .FUNCTION {
        function :: cast[ptr[compiler.TypeInfoFunction]](type)
        schema_number(into, cast[u64](function.input.count), 4)
        for input in function.input {
            schema_name(into, input.name)
            schema_reference(into, input.type, types)
            schema_flag(into, input.is_varargs)
            schema_flag(into, input.is_escaping)
        }
        schema_number(into, cast[u64](function.output.count), 4)
        for output in function.output {
            schema_reference(into, output.type, types)
        }
        schema_flag(into, function.never_returns)
    }
    else if variant == .INTEGER {
        integer :: cast[ptr[compiler.TypeInfoInteger]](type)
        schema_flag(into, integer.is_signed)
        schema_endianness(into, integer.endianness)
    }
    else if variant == .POINTER {
        pointer :: cast[ptr[compiler.TypeInfoPointer]](type)
        match pointer.base_type {
            case Some(pointed) => {
                schema_flag(into, true)
                schema_reference(into, pointed, types)
            }
            case None => schema_flag(into, false)
        }
        schema_flag(into, pointer.is_relative)
        schema_flag(into, pointer.is_mutable)
    }
    else if variant == .STRING {
        schema_flag(into, cast[ptr[compiler.TypeInfoString]](type).is_raw)
    }
    else if variant == .STRUCT {
        structure :: cast[ptr[compiler.TypeInfoStruct]](type)
        schema_name(into, structure.name)
        schema_number(into, cast[u64](structure.alignment), 8)
        schema_flag(into, structure.is_packed)
        schema_flag(into, structure.is_union)
        schema_number(into, cast[u64](structure.members.count), 4)
        for member in structure.members {
            schema_name(into, member.name)
            schema_reference(into, member.member_type, types)
            schema_number(into, cast[u64](member.offset), 8)
            schema_flag(into, member.is_using)
        }
    }
    else if variant == .UNION {
        union_info :: cast[ptr[compiler.TypeInfoUnion]](type)
        schema_name(into, union_info.name)
        schema_flag(into, union_info.null_is_none)
        match union_info.tag_type {
            case Some(tag) => {
                schema_flag(into, true)
                schema_reference(into, tag, types)
            }
            case None => schema_flag(into, false)
        }
        schema_number(into, cast[u64](union_info.variants.count), 4)
        for each_variant in union_info.variants {
            schema_name(into, each_variant.name)
            schema_number(into, cast[u64](each_variant.types.count), 4)
            for held, i in each_variant.types {
                schema_reference(into, held, types)
                offset : usize = if i < each_variant.offsets.count { each_variant.offsets[i] } else { 0 }
                schema_number(into, cast[u64](offset), 8)
            }
        }
    }
    else if variant == .VECTOR {
        vector :: cast[ptr[compiler.TypeInfoVector]](type)
        schema_reference(into, vector.element_type, types)
        schema_number(into, cast[u64](vector.count), 8)
        schema_flag(into, vector.is_bits)
    }
}

schema_kind_of :: fn(variant: compiler.TypeInfoVariant) -> SchemaKind {
    return match variant {
        case .ALIAS => SchemaKind.Alias
        case .ANY => SchemaKind.Any
        case .ARRAY => SchemaKind.Array
        case .BOOLEAN => SchemaKind.Boolean
        case .CHAR => SchemaKind.Char
        case .COMPLEX => SchemaKind.Complex
        case .ENUM => SchemaKind.Enum
        case .FLOAT => SchemaKind.Float
        case .FUNCTION => SchemaKind.Function
        case .INTEGER => SchemaKind.Integer
        case .POINTER => SchemaKind.Pointer
        case .QUATERNION => SchemaKind.Quaternion
        case .STRING => SchemaKind.String
        case .STRUCT => SchemaKind.Struct
        case .TYPE => SchemaKind.Type
        case .UNION => SchemaKind.Union
        case .VECTOR => SchemaKind.Vector
        case .VOID => SchemaKind.Void
    }
}

// A number's lowest bytes, little-endian.
schema_number :: fn(into: ptr[mut u8[..]], value: u64, bytes: usize) {
    for i in cast[usize](0)..<bytes {
        array_add(into, cast[u8]((value >> (8 * i)) & 0xff))
    }
}

schema_flag :: fn(into: ptr[mut u8[..]], value: bool) {
    array_add(into, if value { cast[u8](1) } else { cast[u8](0) })
}

schema_name :: fn(into: ptr[mut u8[..]], text: string) {
    schema_number(into, cast[u64](text.count), 4)
    for byte in view_of(cast[ptr[u8]](text.data), text.count) {
        array_add(into, byte)
    }
}

schema_endianness :: fn(into: ptr[mut u8[..]], value: compiler.Endianness) {
    array_add(into, if value == .BIG { cast[u8](1) } else if value == .LITTLE { cast[u8](2) } else { cast[u8](3) })
}

// A type it refers to, by its place, which reach gave it.
schema_reference :: fn(into: ptr[mut u8[..]], type: ptr[compiler.TypeInfo], types: ptr[mut uintptr[..]]) {
    schema_number(into, cast[u64](schema_place(type, types)), 4)
}

/*
 * A value written for something that reads it elsewhere, by its type's schema (docs/types.md, Schemas): its bytes in
 * its own layout, then what it points to, copied after it, each pointer in it replaced by the distance from the
 * value's start to what it pointed to, or 0 for null. So nothing written says where anything was in the writer's
 * memory, and a reader with the schema finds everything from the value's start.
 *
 * Followed: a string's bytes, a cstring's to its zero (at most SCHEMA_CSTRING_LIMIT of them), an array view's and a
 * dynamic array's elements (a dynamic array's capacity and allocator written as 0), what a pointer points to, up to
 * SCHEMA_MAX_DEPTH pointers deep, and an optional pointer's when it's Some. Written as 0, as nothing elsewhere could use
 * them: rawptr, functions, type values, any, a pointer past SCHEMA_MAX_DEPTH, and a #union struct holding pointers, since
 * which member it holds isn't known. A relative pointer is a distance already, and is written as it is.
 */

// How many pointers deep a value is followed, so one that points to itself is written once per level, and ends.
SCHEMA_MAX_DEPTH :: 8
// The most bytes of a cstring followed, its zero included.
SCHEMA_CSTRING_LIMIT : usize : 4096

// A value written to the end of into, with what it points to after it.
schema_write_value :: fn(value: any, into: ptr[mut u8[..]]) {
    info :: type_info_of(value.type)
    start :: into.count
    schema_copy_in(into, value.data, info.size)
    schema_fix(into, start, start, info, 0)
}

// count bytes from data appended.
schema_copy_in :: fn(into: ptr[mut u8[..]], data: rawptr, count: usize) {
    for byte in view_of(cast[ptr[u8]](data), count) {
        array_add(into, byte)
    }
}

schema_word :: fn(into: ptr[mut u8[..]], at: usize) -> u64 {
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

schema_set_word :: fn(into: ptr[mut u8[..]], at: usize, value: u64) {
    bytes : mut u8[] = into^
    for i in cast[usize](0)..<8 {
        j :: at + i
        if j < bytes.count {
            bytes[j] = cast[u8]((value >> (8 * i)) & 0xff)
        }
    }
}

schema_zero :: fn(into: ptr[mut u8[..]], at: usize, count: usize) {
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
schema_follow :: fn(into: ptr[mut u8[..]], start: usize, at: usize, count: usize) -> usize? {
    pointer :: schema_word(into, at)
    if pointer == 0 {
        return null
    }
    copied :: into.count
    schema_copy_in(into, cast[rawptr](cast[uintptr](pointer)), count)
    schema_set_word(into, at, cast[u64](copied - start))
    return copied
}

/*
 * The pointers in the part of into at `at`, a value of type, each followed or written as 0. Positions are kept as
 * indices, since into grows as what's followed is appended.
 */
schema_fix :: fn(into: ptr[mut u8[..]], start: usize, at: usize, type: ptr[compiler.TypeInfo], depth: int) {
    info :: schema_unaliased(type)
    variant :: info.variant
    if variant == .STRING {
        if cast[ptr[compiler.TypeInfoString]](info).is_raw {
            pointer :: schema_word(into, at)
            if pointer != 0 {
                bytes :: view_of(cast[ptr[u8]](cast[uintptr](pointer)), SCHEMA_CSTRING_LIMIT)
                length := SCHEMA_CSTRING_LIMIT
                for byte, i in bytes {
                    if byte == 0 {
                        length = i + 1
                        break
                    }
                }
                _ = schema_follow(into, start, at, length)
            }
            return void
        }
        // count, then data
        _ = schema_follow(into, start, at + 8, cast[usize](schema_word(into, at)))
    }
    else if variant == .ARRAY {
        schema_fix_array(into, start, at, cast[ptr[compiler.TypeInfoArray]](info), 0, depth)
    }
    else if variant == .POINTER {
        pointer :: cast[ptr[compiler.TypeInfoPointer]](info)
        if pointer.is_relative {
            return void
        }
        schema_fix_pointer(into, start, at, pointer.base_type, depth)
    }
    else if variant == .STRUCT {
        structure :: cast[ptr[compiler.TypeInfoStruct]](info)
        if structure.is_union {
            if schema_holds_pointers(info, 0) {
                schema_zero(into, at, info.size)
            }
            return void
        }
        for member in structure.members {
            schema_fix(into, start, at + member.offset, member.member_type, depth)
        }
    }
    else if variant == .UNION {
        union_info :: cast[ptr[compiler.TypeInfoUnion]](info)
        if union_info.null_is_none {
            // Just the pointer: Some's only value
            for each in union_info.variants {
                if each.types.count == 1 {
                    schema_fix(into, start, at, each.types[0], depth)
                    break
                }
            }
            return void
        }
        tag_size :: match union_info.tag_type {
            case Some(tag) => tag.size
            case None => cast[usize](0)
        }
        tag :: cast[usize](schema_word(into, at) & schema_mask_of(tag_size))
        if tag >= union_info.variants.count {
            return void
        }
        chosen :: union_info.variants[tag]
        for held, i in chosen.types {
            if i < chosen.offsets.count {
                schema_fix(into, start, at + chosen.offsets[i], held, depth)
            }
        }
    }
    else if variant == .ANY || variant == .FUNCTION || variant == .TYPE {
        schema_zero(into, at, info.size)
    }
}

// What a pointer at `at` points to, of type pointed, followed, unless it's a rawptr or too deep.
schema_fix_pointer :: fn(into: ptr[mut u8[..]], start: usize, at: usize, pointed: ptr[compiler.TypeInfo]?, depth: int) {
    if (pointed is_none) || depth >= SCHEMA_MAX_DEPTH {
        schema_set_word(into, at, 0)
        return void
    }
    target :: pointed or_return void
    match schema_follow(into, start, at, target.size) {
        case Some(copied) => schema_fix(into, start, copied, target, depth + 1)
        case None => {}
    }
}

// The array at `at`, from dimension on: a static one's elements in place, a view's or dynamic one's copied after.
schema_fix_array :: fn(into: ptr[mut u8[..]], start: usize, at: usize, info: ptr[compiler.TypeInfoArray], dimension: usize, depth: int) {
    dimensions :: info.dimensions
    if dimension >= dimensions.count {
        schema_fix(into, start, at, info.base_type, depth)
        return void
    }
    element_size :: schema_dimension_element_size(info, dimension)
    array_type :: dimensions[dimension].type
    elements := at
    count := dimensions[dimension].count
    if array_type == .VIEW || array_type == .DYNAMIC {
        // count, then data; a dynamic array's capacity and allocator after them mean nothing elsewhere
        count = cast[usize](schema_word(into, at))
        if array_type == .DYNAMIC {
            schema_zero(into, at + 16, size_of(ResizableArray) - 16)
        }
        elements = schema_follow(into, start, at + 8, count * element_size) or_return void
    }
    if !schema_holds_pointers_array(info, dimension) {
        return void
    }
    for index in cast[usize](0)..<count {
        schema_fix_array(into, start, elements + index * element_size, info, dimension + 1, depth)
    }
}

// The bits of a tag of size bytes.
schema_mask_of :: fn(size: usize) -> u64 {
    if size >= 8 {
        return 0xffffffffffffffff
    }
    return (cast[u64](1) << (8 * size)) - 1
}

// Whether a value of type holds anything fix changes, looking no deeper than SCHEMA_MAX_DEPTH types in.
schema_holds_pointers :: fn(type: ptr[compiler.TypeInfo], depth: int) -> bool {
    if depth >= SCHEMA_MAX_DEPTH {
        return true
    }
    info :: schema_unaliased(type)
    variant :: info.variant
    if variant == .STRING || variant == .POINTER || variant == .ANY || variant == .FUNCTION || variant == .TYPE || variant == .UNION {
        return true
    }
    if variant == .ARRAY {
        return schema_holds_pointers_array(cast[ptr[compiler.TypeInfoArray]](info), 0)
    }
    if variant == .STRUCT {
        for member in cast[ptr[compiler.TypeInfoStruct]](info).members {
            if schema_holds_pointers(member.member_type, depth + 1) {
                return true
            }
        }
    }
    return false
}

schema_holds_pointers_array :: fn(info: ptr[compiler.TypeInfoArray], dimension: usize) -> bool {
    for i in dimension..<info.dimensions.count {
        if info.dimensions[i].type != .STATIC {
            return true
        }
    }
    return schema_holds_pointers(info.base_type, 0)
}

// The type an alias names, distinct or not, through any number of them.
schema_unaliased :: fn(info: ptr[compiler.TypeInfo]) -> ptr[compiler.TypeInfo] {
    result := info
    loop {
        if result.variant != .ALIAS {
            return result
        }
        result = cast[ptr[compiler.TypeInfoAlias]](result).base_type
    }
}

// The bytes of each element of an array's dimension.
schema_dimension_element_size :: fn(info: ptr[compiler.TypeInfoArray], dimension: usize) -> usize {
    inner :: dimension + 1
    if inner >= info.dimensions.count {
        return info.base_type.size
    }
    inner_type :: info.dimensions[inner].type
    if inner_type == .VIEW {
        return size_of(ArrayView)
    }
    if inner_type == .DYNAMIC {
        return size_of(ResizableArray)
    }
    return info.dimensions[inner].count * schema_dimension_element_size(info, inner)
}
