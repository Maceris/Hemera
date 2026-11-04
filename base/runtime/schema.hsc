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

/** The version of the schema format, written after "HSCH"; it changes when the bytes for the same type would. */
SCHEMA_VERSION : u16 : 1

/**
 * What each kind is in the bytes, as the u8 that starts a type's description.
 *
 * The values are fixed, whatever compiler.TypeInfoVariant's order becomes, so a schema's bytes don't change with it.
 */
SchemaKind :: enum #backed_by(u8) {
    Alias = 1, /**< A distinct alias; a plain one is described as the type it names. */
    Any = 2, /**< The any type: a value with its type beside it. */
    Array = 3, /**< An array of any dimensions: static, view or dynamic. */
    Boolean = 4, /**< A boolean. */
    Char = 5, /**< A character type. */
    Complex = 6, /**< A complex number type. */
    Enum = 7, /**< An enum, with its backing type and its members' values. */
    Float = 8, /**< A floating-point type. */
    Function = 9, /**< A function type: its inputs, its outputs, and whether it returns. */
    Integer = 10, /**< An integer type, signed or not. */
    Pointer = 11, /**< A pointer, to a type or raw. */
    Quaternion = 12, /**< A quaternion type. */
    String = 13, /**< A string, or a cstring. */
    Struct = 14, /**< A struct, or a #union struct. */
    Type = 15, /**< A type value. */
    Union = 16, /**< A tagged union, or an optional that's just a pointer. */
    Vector = 17, /**< A vector of lanes. */
    Void = 18, /**< The void type. */
}

/**
 * The bytes being written, and the first error growing them or the types, after which nothing more is added.
 *
 * #scoped, since the array may be on the stack.
 */
SchemaBytes :: struct #scoped {
    /** The array the bytes are added to the end of, grown with its own allocator; the caller's, which outlives this. */
    into : ptr[mut u8[..]],
    /** The first error growing into or the list of types, or null; once it's set, every addition is skipped. */
    error : AllocatorError?,
}

/**
 * Write a type's schema to the end of an array.
 *
 * Without the memory, calls context.assertion_handler, as array_add does; schema_try_write is for code that handles
 * running out.
 *
 * @param type The type whose schema is written; a plain alias is described as the type it names.
 * @param into The array the bytes are added to, grown with its own allocator; what it held already is left as it is.
 * @param location Where the call is, given to the assertion handler; the caller's location by default.
 */
schema_write :: fn(type: ptr[compiler.TypeInfo], into: ptr[mut u8[..]], location := #caller_location) {
    if schema_try_write(type, into) != null {
        context.assertion_handler(location, "out of memory")
    }
}

/**
 * Write a type's schema to the end of an array, giving back the error when there isn't the memory.
 *
 * For code that handles running out, like the SlopOS logger, which drops a record rather than end the process.
 * A list of the types reached is kept on context.allocator while it runs, and freed before it returns.
 *
 * @param type The type whose schema is written; a plain alias is described as the type it names.
 * @param into The array the bytes are added to, grown with its own allocator; what it held already is left as it is.
 * @return Null when the whole schema was written; otherwise the allocator's error, and into's count is as it was,
 *     so nothing of the schema is left in it.
 */
schema_try_write :: fn(type: ptr[compiler.TypeInfo], into: ptr[mut u8[..]]) -> AllocatorError? {
    start :: into.count
    out := SchemaBytes.{into = into, error = null}
    // Each type by its address, as a number, so where they're kept isn't a question
    types : uintptr[..]
    defer array_free(&types)
    _ = schema_place(type, &types, &out)
    // Each type reached, from the first, adds those it refers to that are new
    at : usize = 0
    loop {
        if at >= types.count || out.error != null {
            break
        }
        schema_reach(cast[ptr[compiler.TypeInfo]](types[at]), &types, &out)
        at += 1
    }
    for byte in u8.[0x48, 0x53, 0x43, 0x48] {
        schema_add(&out, byte)
    }
    schema_number(&out, cast[u64](SCHEMA_VERSION), 2)
    schema_number(&out, cast[u64](types.count), 4)
    for each in types {
        schema_describe(cast[ptr[compiler.TypeInfo]](each), &types, &out)
    }
    if out.error != null {
        resizable(into).count = start
    }
    return out.error
}

/**
 * Compute a type's schema hash, which names the type the same in every build, program and host.
 *
 * The schema's bytes are kept on context.allocator while they're hashed, and freed after. Without the memory for
 * them, calls context.assertion_handler, as schema_write does.
 *
 * @param type The type whose schema is hashed; a plain alias hashes as the type it names.
 * @return BLAKE3-256 of the type's schema's bytes.
 */
schema_hash :: fn(type: ptr[compiler.TypeInfo]) -> u8[32] {
    bytes : u8[..]
    defer array_free(&bytes)
    schema_write(type, &bytes)
    return hash_blake3(bytes)
}

/**
 * Find the type a plain alias names, through any number of them, since a schema describes a plain alias as that type.
 *
 * @param type The type, which may be a plain alias, a distinct alias or anything else.
 * @return The first type that isn't a plain alias: type itself when it isn't one. A distinct alias stops the search,
 *     since it's a type of its own.
 */
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

/**
 * Find a type's place among the types a schema describes, adding it at the end if it's new.
 *
 * @param type The type; a plain alias is placed as the type it names.
 * @param types The types reached so far, each by its address as a number, in the order they're described.
 * @param out The bytes being written, whose error is set when there isn't the memory to add the type.
 * @return The type's place, from 0, as a schema refers to it; 0 when it's new and out has an error, set now or
 *     before, since it couldn't be added.
 */
schema_place :: fn(type: ptr[compiler.TypeInfo], types: ptr[mut uintptr[..]], out: ptr[mut SchemaBytes]) -> usize {
    found :: cast[uintptr](schema_plain(type))
    for each, i in types^ {
        if each == found {
            return i
        }
    }
    if out.error == null {
        out.error = array_try_add(types, found)
    }
    if out.error != null {
        return 0
    }
    return types.count - 1
}

/**
 * Give a place to every type a type refers to directly, so each is described after the types before it.
 *
 * Only the types it names itself are added, not theirs: schema_try_write reaches each type in turn, so they're
 * placed breadth first.
 *
 * @param type The type whose references are placed; a type it refers to more than once is placed once.
 * @param types The types reached so far, added to at the end.
 * @param out The bytes being written, whose error is set when there isn't the memory to add a type.
 */
schema_reach :: fn(type: ptr[compiler.TypeInfo], types: ptr[mut uintptr[..]], out: ptr[mut SchemaBytes]) {
    variant :: type.variant
    if variant == .ALIAS {
        _ = schema_place(cast[ptr[compiler.TypeInfoAlias]](type).base_type, types, out)
    }
    else if variant == .ARRAY {
        _ = schema_place(cast[ptr[compiler.TypeInfoArray]](type).base_type, types, out)
    }
    else if variant == .ENUM {
        _ = schema_place(cast[ptr[compiler.TypeInfoEnum]](type).backing_type, types, out)
    }
    else if variant == .FUNCTION {
        function :: cast[ptr[compiler.TypeInfoFunction]](type)
        for input in function.input {
            _ = schema_place(input.type, types, out)
        }
        for output in function.output {
            _ = schema_place(output.type, types, out)
        }
    }
    else if variant == .POINTER {
        pointer :: cast[ptr[compiler.TypeInfoPointer]](type)
        match pointer.base_type {
            case Some(pointed) => _ = schema_place(pointed, types, out)
            case None => {}
        }
    }
    else if variant == .STRUCT {
        for member in cast[ptr[compiler.TypeInfoStruct]](type).members {
            _ = schema_place(member.member_type, types, out)
        }
    }
    else if variant == .UNION {
        union_info :: cast[ptr[compiler.TypeInfoUnion]](type)
        match union_info.tag_type {
            case Some(tag) => _ = schema_place(tag, types, out)
            case None => {}
        }
        for each_variant in union_info.variants {
            for held in each_variant.types {
                _ = schema_place(held, types, out)
            }
        }
    }
    else if variant == .VECTOR {
        _ = schema_place(cast[ptr[compiler.TypeInfoVector]](type).element_type, types, out)
    }
}

/**
 * Write one type's part of a schema: its kind, its size, and what its kind has.
 *
 * @param type The type described, which has to be among types already, as every type it refers to should be.
 * @param types The types reached, by whose places the types it refers to are written.
 * @param out The bytes being written; nothing is added after an error.
 */
schema_describe :: fn(type: ptr[compiler.TypeInfo], types: ptr[mut uintptr[..]], out: ptr[mut SchemaBytes]) {
    variant :: type.variant
    schema_add(out, cast[u8](schema_kind_of(variant)))
    schema_number(out, cast[u64](type.size), 8)
    if variant == .ALIAS {
        alias :: cast[ptr[compiler.TypeInfoAlias]](type)
        schema_name(out, alias.name)
        schema_reference(out, alias.base_type, types)
    }
    else if variant == .ARRAY {
        array :: cast[ptr[compiler.TypeInfoArray]](type)
        schema_reference(out, array.base_type, types)
        schema_number(out, cast[u64](array.dimensions.count), 4)
        for dimension in array.dimensions {
            kind : u8 = if dimension.type == .STATIC { 1 } else if dimension.type == .DYNAMIC { 2 } else { 3 }
            schema_add(out, kind)
            schema_number(out, cast[u64](dimension.count), 8)
            schema_flag(out, dimension.is_mutable)
        }
    }
    else if variant == .ENUM {
        enumeration :: cast[ptr[compiler.TypeInfoEnum]](type)
        schema_name(out, enumeration.name)
        schema_reference(out, enumeration.backing_type, types)
        schema_number(out, cast[u64](enumeration.members.count), 4)
        for member, i in enumeration.members {
            schema_name(out, member)
            value : u128 = if i < enumeration.values.count { enumeration.values[i] } else { 0 }
            schema_number(out, cast[u64](value), 8)
            schema_number(out, cast[u64](value >> 64), 8)
        }
    }
    else if variant == .FLOAT {
        schema_endianness(out, cast[ptr[compiler.TypeInfoFloat]](type).endianness)
    }
    else if variant == .FUNCTION {
        function :: cast[ptr[compiler.TypeInfoFunction]](type)
        schema_number(out, cast[u64](function.input.count), 4)
        for input in function.input {
            schema_name(out, input.name)
            schema_reference(out, input.type, types)
            schema_flag(out, input.is_varargs)
            schema_flag(out, input.is_escaping)
        }
        schema_number(out, cast[u64](function.output.count), 4)
        for output in function.output {
            schema_reference(out, output.type, types)
        }
        schema_flag(out, function.never_returns)
    }
    else if variant == .INTEGER {
        integer :: cast[ptr[compiler.TypeInfoInteger]](type)
        schema_flag(out, integer.is_signed)
        schema_endianness(out, integer.endianness)
    }
    else if variant == .POINTER {
        pointer :: cast[ptr[compiler.TypeInfoPointer]](type)
        match pointer.base_type {
            case Some(pointed) => {
                schema_flag(out, true)
                schema_reference(out, pointed, types)
            }
            case None => schema_flag(out, false)
        }
        schema_flag(out, pointer.is_relative)
        schema_flag(out, pointer.is_mutable)
    }
    else if variant == .STRING {
        schema_flag(out, cast[ptr[compiler.TypeInfoString]](type).is_raw)
    }
    else if variant == .STRUCT {
        structure :: cast[ptr[compiler.TypeInfoStruct]](type)
        schema_name(out, structure.name)
        schema_number(out, cast[u64](structure.alignment), 8)
        schema_flag(out, structure.is_packed)
        schema_flag(out, structure.is_union)
        schema_number(out, cast[u64](structure.members.count), 4)
        for member in structure.members {
            schema_name(out, member.name)
            schema_reference(out, member.member_type, types)
            schema_number(out, cast[u64](member.offset), 8)
            schema_flag(out, member.is_using)
        }
    }
    else if variant == .UNION {
        union_info :: cast[ptr[compiler.TypeInfoUnion]](type)
        schema_name(out, union_info.name)
        schema_flag(out, union_info.null_is_none)
        match union_info.tag_type {
            case Some(tag) => {
                schema_flag(out, true)
                schema_reference(out, tag, types)
            }
            case None => schema_flag(out, false)
        }
        schema_number(out, cast[u64](union_info.variants.count), 4)
        for each_variant in union_info.variants {
            schema_name(out, each_variant.name)
            schema_number(out, cast[u64](each_variant.types.count), 4)
            for held, i in each_variant.types {
                schema_reference(out, held, types)
                offset : usize = if i < each_variant.offsets.count { each_variant.offsets[i] } else { 0 }
                schema_number(out, cast[u64](offset), 8)
            }
        }
    }
    else if variant == .VECTOR {
        vector :: cast[ptr[compiler.TypeInfoVector]](type)
        schema_reference(out, vector.element_type, types)
        schema_number(out, cast[u64](vector.count), 8)
        schema_flag(out, vector.is_bits)
    }
}

/**
 * Find the fixed kind a schema writes for a type's variant.
 *
 * @param variant The variant of the type described.
 * @return The kind whose value is written in the bytes; every variant has one.
 */
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

/**
 * Write a number's lowest bytes, little-endian.
 *
 * @param out The bytes being written; nothing is added after an error.
 * @param value The number; bytes above the ones written are dropped.
 * @param bytes How many bytes are written, from 0 to 8: 2 for a u16, 4 for a u32, 8 for a u64.
 */
schema_number :: fn(out: ptr[mut SchemaBytes], value: u64, bytes: usize) {
    for i in cast[usize](0)..<bytes {
        schema_add(out, cast[u8]((value >> (8 * i)) & 0xff))
    }
}

/**
 * Write a flag as one byte.
 *
 * @param out The bytes being written; nothing is added after an error.
 * @param value The flag, written as 1 when it's true and 0 when it's false.
 */
schema_flag :: fn(out: ptr[mut SchemaBytes], value: bool) {
    schema_add(out, if value { cast[u8](1) } else { cast[u8](0) })
}

/**
 * Write a name: its length, as a u32, then its bytes.
 *
 * @param out The bytes being written; nothing is added after an error.
 * @param text The name, which may be empty; its bytes are written as they are, with no terminator.
 */
schema_name :: fn(out: ptr[mut SchemaBytes], text: string) {
    schema_number(out, cast[u64](text.count), 4)
    for byte in view_of(cast[ptr[u8]](text.data), text.count) {
        schema_add(out, byte)
    }
}

/**
 * Write an endianness as one byte.
 *
 * @param out The bytes being written; nothing is added after an error.
 * @param value The endianness, written as 1 for big, 2 for little and 3 for the system's.
 */
schema_endianness :: fn(out: ptr[mut SchemaBytes], value: compiler.Endianness) {
    schema_add(out, if value == .BIG { cast[u8](1) } else if value == .LITTLE { cast[u8](2) } else { cast[u8](3) })
}

/**
 * Write a type that another refers to, as its place, a u32.
 *
 * @param out The bytes being written; nothing is added after an error.
 * @param type The type referred to, which schema_reach placed already; were it new, it would be placed now.
 * @param types The types reached, which give the place.
 */
schema_reference :: fn(out: ptr[mut SchemaBytes], type: ptr[compiler.TypeInfo], types: ptr[mut uintptr[..]]) {
    schema_number(out, cast[u64](schema_place(type, types, out)), 4)
}

/*
 * A value written for something that reads it elsewhere, by its type's schema (docs/types.md, Schemas): its bytes in
 * its own layout, then what it points to, copied after it, each pointer in it replaced by the distance from the
 * value's start to what it pointed to, or 0 for null. So nothing written says where anything was in the writer's
 * memory, and a reader with the schema finds everything from the value's start.
 *
 * Followed: a string's bytes, a cstring's to its zero (at most SCHEMA_CSTRING_LIMIT of them), an array view's and a
 * dynamic array's elements (a dynamic array's capacity and allocator written as 0), what a pointer points to, up to
 * SCHEMA_MAX_DEPTH pointers deep, and an optional pointer's when it's Some. Written as 0, as nothing elsewhere could
 * use them: rawptr, functions, type values, any, a pointer past SCHEMA_MAX_DEPTH, and a #union struct holding
 * pointers, since which member it holds isn't known. A relative pointer is a distance already, and is written as it is.
 */

/**
 * How many pointers deep a value is followed, so one that points to itself is written once per level, and ends.
 * A pointer deeper than this is written as 0.
 */
SCHEMA_MAX_DEPTH :: 8
/** The most bytes of a cstring followed, its zero included; a longer one is cut to this many, without its zero. */
SCHEMA_CSTRING_LIMIT : usize : 4096

/**
 * Write a value to the end of an array, with what it points to after it, for something that reads it elsewhere.
 *
 * Without the memory, calls context.assertion_handler, as array_add does; schema_try_write_value is for code that
 * handles running out.
 *
 * @param value The value; every pointer in it that's followed has to point to memory that can be read.
 * @param into The array the bytes are added to, grown with its own allocator; what it held already is left as it is,
 *     and distances in what's written are from where the value starts in it.
 * @param location Where the call is, given to the assertion handler; the caller's location by default.
 */
schema_write_value :: fn(value: any, into: ptr[mut u8[..]], location := #caller_location) {
    if schema_try_write_value(value, into) != null {
        context.assertion_handler(location, "out of memory")
    }
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
schema_try_write_value :: fn(value: any, into: ptr[mut u8[..]]) -> AllocatorError? {
    info :: type_info_of(value.type)
    start :: into.count
    out := SchemaBytes.{into = into, error = null}
    schema_copy_in(&out, value.data, info.size)
    schema_fix(&out, start, start, info, 0)
    if out.error != null {
        resizable(into).count = start
    }
    return out.error
}

/**
 * Write a value given by its address and type, as schema_try_write_value writes one, for code that has no any.
 *
 * @param data Where the value is: type.size bytes that can be read, and every pointer in it that's followed has to
 *     point to memory that can be read too.
 * @param type The value's type, which says how big it is and where its pointers are.
 * @param into The array the bytes are added to, grown with its own allocator; what it held already is left as it is.
 * @return Null when the whole value was written; otherwise the allocator's error, and into's count is as it was.
 */
schema_try_write_value_at :: fn(data: rawptr, type: ptr[compiler.TypeInfo], into: ptr[mut u8[..]]) -> AllocatorError? {
    start :: into.count
    out := SchemaBytes.{into = into, error = null}
    schema_copy_in(&out, data, type.size)
    schema_fix(&out, start, start, type, 0)
    if out.error != null {
        resizable(into).count = start
    }
    return out.error
}

/**
 * Read a value back from bytes written as schema_write_value writes one.
 *
 * The bytes are copied to memory from context.allocator, each distance in the copy from its start made a pointer
 * into the copy again, and then the value itself copied to into. The copy isn't freed: the value's pointers point
 * into it, so it stays for as long as they're used, and nothing here frees it later.
 *
 * @param bytes What was written, starting at the value; they're copied, so they needn't outlive the call.
 * @param type The value's type, whose schema it was written with; read as another type, the value is garbage,
 *     though its pointers still don't point outside the copy.
 * @param into Where the value goes: type.size bytes that can be written, left as they were when it fails.
 * @return Whether the value was read. False, with nothing stored, when bytes are fewer than the type's size or
 *     empty, when there isn't the memory for the copy, when a distance points past what was written, when a union's
 *     tag names no variant, or when pointers go more than SCHEMA_MAX_DEPTH deep; the copy is freed then.
 */
schema_read_value :: fn(bytes: u8[], type: ptr[compiler.TypeInfo], into: rawptr) -> bool {
    size :: type.size
    if bytes.count < size || bytes.count == 0 {
        return false
    }
    copy, error :: new_array(u8, bytes.count)
    if error != null {
        return false
    }
    for byte, i in bytes {
        if i < copy.count {
            copy[i] = byte
        }
    }
    if !schema_relocate(copy, 0, type, 0) {
        free_array(copy)
        return false
    }
    target :: view_of(cast[ptr[mut u8]](into), size)
    for i in cast[usize](0)..<size {
        if i < copy.count {
            target[i] = copy[i]
        }
    }
    return true
}

/**
 * Read a little-endian 64-bit word from a copy being read back.
 *
 * @param copy The bytes being read back, only read; they may end before at + 8.
 * @param at Where in copy the word starts, in bytes; bytes past the copy's end read as 0.
 * @return The 8 bytes from at, the first the lowest; any past the copy's end count as 0.
 */
schema_read_word :: fn(copy: u8[], at: usize) -> u64 {
    result : u64 = 0
    for i in cast[usize](0)..<8 {
        j :: at + i
        if j < copy.count {
            result |= cast[u64](copy[j]) << (8 * i)
        }
    }
    return result
}

/**
 * Write a little-endian 64-bit word into a copy being read back.
 *
 * @param copy The bytes being read back, changed in place from at; their count doesn't change.
 * @param at Where in copy the word starts, in bytes; bytes that would be past the copy's end aren't written.
 * @param value Any 64-bit value, written lowest byte first.
 */
schema_write_word :: fn(copy: mut u8[], at: usize, value: u64) {
    for i in cast[usize](0)..<8 {
        j :: at + i
        if j < copy.count {
            copy[j] = cast[u8]((value >> (8 * i)) & 0xff)
        }
    }
}

/**
 * Make the distance written at a place in a copy a pointer into the copy again.
 *
 * @param copy The copy being read back, whose address the pointer is made from, so it has to stay where it is.
 * @param at Where in copy the distance is, in bytes; it's replaced by the pointer.
 * @param count How many bytes what it points to takes, all of which have to be inside the copy.
 * @param ok Set to false when the distance, its word or what it points to would be past the copy's end; never set
 *     to true, so one flag gathers every failure.
 * @return Where in the copy what it points to starts, in bytes. None for a distance of 0, a null pointer, which is
 *     left as it is, and when it doesn't fit, which leaves the word as it was.
 */
schema_relocate_word :: fn(copy: mut u8[], at: usize, count: usize, ok: ptr[mut bool]) -> usize? {
    distance :: schema_read_word(copy, at)
    if distance == 0 {
        return null
    }
    if distance >= cast[u64](copy.count) || cast[u64](count) > cast[u64](copy.count) - distance || at + 8 > copy.count {
        ok^ = false
        return null
    }
    schema_write_word(copy, at, cast[u64](cast[uintptr](&copy[0])) + distance)
    return cast[usize](distance)
}

/**
 * Make each distance in a value in a copy a pointer into the copy again, as schema_fix made pointers distances.
 *
 * @param copy The copy being read back.
 * @param at Where in copy the value starts, in bytes.
 * @param type The value's type, which says where its distances are.
 * @param depth How many pointers deep the value is, 0 for the value read; deeper than SCHEMA_MAX_DEPTH fails.
 * @return Whether every distance fit inside the copy; false too when the value runs past the copy's end, when a
 *     union's tag names no variant, or when it's too deep. Distances made pointers before a failure stay pointers.
 */
schema_relocate :: fn(copy: mut u8[], at: usize, type: ptr[compiler.TypeInfo], depth: int) -> bool {
    if depth > SCHEMA_MAX_DEPTH || at + type.size > copy.count {
        return false
    }
    ok := true
    info :: schema_unaliased(type)
    variant :: info.variant
    if variant == .STRING {
        if cast[ptr[compiler.TypeInfoString]](info).is_raw {
            _ = schema_relocate_word(copy, at, 1, &ok)
            return ok
        }
        _ = schema_relocate_word(copy, at + 8, cast[usize](schema_read_word(copy, at)), &ok)
        return ok
    }
    if variant == .ARRAY {
        return schema_relocate_array(copy, at, cast[ptr[compiler.TypeInfoArray]](info), 0, depth)
    }
    if variant == .POINTER {
        pointer :: cast[ptr[compiler.TypeInfoPointer]](info)
        if pointer.is_relative {
            return true
        }
        target :: pointer.base_type or_return true
        match schema_relocate_word(copy, at, target.size, &ok) {
            case Some(copied) => return ok && schema_relocate(copy, copied, target, depth + 1)
            case None => return ok
        }
    }
    if variant == .STRUCT {
        structure :: cast[ptr[compiler.TypeInfoStruct]](info)
        if structure.is_union {
            return true
        }
        for member in structure.members {
            if !schema_relocate(copy, at + member.offset, member.member_type, depth) {
                return false
            }
        }
        return true
    }
    if variant == .UNION {
        union_info :: cast[ptr[compiler.TypeInfoUnion]](info)
        if union_info.null_is_none {
            for each in union_info.variants {
                if each.types.count == 1 {
                    return schema_relocate(copy, at, each.types[0], depth)
                }
            }
            return true
        }
        tag_size :: match union_info.tag_type {
            case Some(tag) => tag.size
            case None => cast[usize](0)
        }
        tag :: cast[usize](schema_read_word(copy, at) & schema_mask_of(tag_size))
        if tag >= union_info.variants.count {
            return false
        }
        chosen :: union_info.variants[tag]
        for held, i in chosen.types {
            if i < chosen.offsets.count && !schema_relocate(copy, at + chosen.offsets[i], held, depth) {
                return false
            }
        }
        return true
    }
    return true
}

/**
 * Make each distance in an array in a copy a pointer into the copy again, from one of its dimensions on.
 *
 * @param copy The copy being read back.
 * @param at Where in copy the array starts, in bytes.
 * @param info The array's type information, not null and only read: its dimensions, outermost first, each static, a
 *     view or dynamic, and the base type of its elements.
 * @param dimension The first dimension handled, from 0; past the last, the array's element is handled.
 * @param depth How many pointers deep the array is, as schema_relocate counts it.
 * @return Whether every distance fit inside the copy, as schema_relocate gives it; false too when a view's or
 *     dynamic array's count is more elements than the whole copy could hold.
 */
schema_relocate_array :: fn(copy: mut u8[], at: usize, info: ptr[compiler.TypeInfoArray], dimension: usize, depth: int) -> bool {
    dimensions :: info.dimensions
    if dimension >= dimensions.count {
        return schema_relocate(copy, at, info.base_type, depth)
    }
    element_size :: schema_dimension_element_size(info, dimension)
    array_type :: dimensions[dimension].type
    elements := at
    count := dimensions[dimension].count
    if array_type == .VIEW || array_type == .DYNAMIC {
        ok := true
        count = cast[usize](schema_read_word(copy, at))
        if element_size > 0 && count > copy.count / element_size {
            return false
        }
        match schema_relocate_word(copy, at + 8, count * element_size, &ok) {
            case Some(copied) => elements = copied
            case None => return ok
        }
    }
    if !schema_holds_pointers_array(info, dimension) {
        return true
    }
    for index in cast[usize](0)..<count {
        if !schema_relocate_array(copy, elements + index * element_size, info, dimension + 1, depth) {
            return false
        }
    }
    return true
}

/**
 * Add a byte at the end of the bytes being written, unless adding one has failed already.
 *
 * @param out The bytes being written, whose error is set when there isn't the memory for this one.
 * @param byte Any byte, added after the last one; not added once out's error is set.
 */
schema_add :: fn(out: ptr[mut SchemaBytes], byte: u8) {
    if out.error == null {
        out.error = array_try_add(out.into, byte)
    }
}

/**
 * Add bytes from memory at the end of the bytes being written.
 *
 * @param out The bytes being written; nothing is added after an error.
 * @param data Where the bytes are, which has to be count bytes that can be read.
 * @param count How many bytes, which may be 0.
 */
schema_copy_in :: fn(out: ptr[mut SchemaBytes], data: rawptr, count: usize) {
    for byte in view_of(cast[ptr[u8]](data), count) {
        schema_add(out, byte)
    }
}

/**
 * Read a little-endian 64-bit word from the bytes being written.
 *
 * @param out The bytes being written.
 * @param at Where in them the word starts, in bytes from the array's start; bytes past its end read as 0.
 * @return The 8 bytes from at, the first the lowest; any past the array's end count as 0.
 */
schema_word :: fn(out: ptr[mut SchemaBytes], at: usize) -> u64 {
    bytes : u8[] = out.into^
    result : u64 = 0
    for i in cast[usize](0)..<8 {
        j :: at + i
        if j < bytes.count {
            result |= cast[u64](bytes[j]) << (8 * i)
        }
    }
    return result
}

/**
 * Write a little-endian 64-bit word over the bytes being written.
 *
 * @param out The bytes being written, whose count doesn't change.
 * @param at Where in them the word starts, in bytes from the array's start; bytes that would be past its end aren't
 *     written.
 * @param value Any 64-bit value, written lowest byte first.
 */
schema_set_word :: fn(out: ptr[mut SchemaBytes], at: usize, value: u64) {
    bytes : mut u8[] = out.into^
    for i in cast[usize](0)..<8 {
        j :: at + i
        if j < bytes.count {
            bytes[j] = cast[u8]((value >> (8 * i)) & 0xff)
        }
    }
}

/**
 * Set bytes already written to 0, for what means nothing elsewhere.
 *
 * @param out The bytes being written, whose count doesn't change.
 * @param at Where in them the first byte is, from the array's start.
 * @param count How many bytes; those past the array's end are left alone.
 */
schema_zero :: fn(out: ptr[mut SchemaBytes], at: usize, count: usize) {
    bytes : mut u8[] = out.into^
    for i in cast[usize](0)..<count {
        j :: at + i
        if j < bytes.count {
            bytes[j] = 0
        }
    }
}

/**
 * Copy what a pointer in the bytes being written points to, to their end, and replace the pointer with its distance.
 *
 * @param out The bytes being written.
 * @param start Where the value being written starts in them, from which distances are measured.
 * @param at Where the pointer is in them, in bytes; it's replaced by the distance from start to the copy.
 * @param count How many bytes it points to, which are copied and have to be readable.
 * @return Where the copy starts in the bytes. None when the pointer is null, which stays 0, or when there's an
 *     error, before or now, which leaves the pointer as it was.
 */
schema_follow :: fn(out: ptr[mut SchemaBytes], start: usize, at: usize, count: usize) -> usize? {
    pointer :: schema_word(out, at)
    if pointer == 0 || out.error != null {
        return null
    }
    copied :: out.into.count
    schema_copy_in(out, cast[rawptr](cast[uintptr](pointer)), count)
    if out.error != null {
        return null
    }
    schema_set_word(out, at, cast[u64](copied - start))
    return copied
}

/**
 * Follow each pointer in a value in the bytes being written, or write it as 0.
 *
 * Positions are kept as indices, since into grows as what's followed is appended.
 *
 * @param out The bytes being written.
 * @param start Where the whole value being written starts in them, from which distances are measured.
 * @param at Where in them the value being fixed starts: start for the whole value, and after it for what it points
 *     to.
 * @param type The value's type, which says where its pointers are.
 * @param depth How many pointers deep the value is, 0 for the value written.
 */
schema_fix :: fn(out: ptr[mut SchemaBytes], start: usize, at: usize, type: ptr[compiler.TypeInfo], depth: int) {
    info :: schema_unaliased(type)
    variant :: info.variant
    if variant == .STRING {
        if cast[ptr[compiler.TypeInfoString]](info).is_raw {
            pointer :: schema_word(out, at)
            if pointer != 0 {
                bytes :: view_of(cast[ptr[u8]](cast[uintptr](pointer)), SCHEMA_CSTRING_LIMIT)
                length := SCHEMA_CSTRING_LIMIT
                for byte, i in bytes {
                    if byte == 0 {
                        length = i + 1
                        break
                    }
                }
                _ = schema_follow(out, start, at, length)
            }
            return void
        }
        // count, then data
        _ = schema_follow(out, start, at + 8, cast[usize](schema_word(out, at)))
    }
    else if variant == .ARRAY {
        schema_fix_array(out, start, at, cast[ptr[compiler.TypeInfoArray]](info), 0, depth)
    }
    else if variant == .POINTER {
        pointer :: cast[ptr[compiler.TypeInfoPointer]](info)
        if pointer.is_relative {
            return void
        }
        schema_fix_pointer(out, start, at, pointer.base_type, depth)
    }
    else if variant == .STRUCT {
        structure :: cast[ptr[compiler.TypeInfoStruct]](info)
        if structure.is_union {
            if schema_holds_pointers(info, 0) {
                schema_zero(out, at, info.size)
            }
            return void
        }
        for member in structure.members {
            schema_fix(out, start, at + member.offset, member.member_type, depth)
        }
    }
    else if variant == .UNION {
        union_info :: cast[ptr[compiler.TypeInfoUnion]](info)
        if union_info.null_is_none {
            // Just the pointer: Some's only value
            for each in union_info.variants {
                if each.types.count == 1 {
                    schema_fix(out, start, at, each.types[0], depth)
                    break
                }
            }
            return void
        }
        tag_size :: match union_info.tag_type {
            case Some(tag) => tag.size
            case None => cast[usize](0)
        }
        tag :: cast[usize](schema_word(out, at) & schema_mask_of(tag_size))
        if tag >= union_info.variants.count {
            return void
        }
        chosen :: union_info.variants[tag]
        for held, i in chosen.types {
            if i < chosen.offsets.count {
                schema_fix(out, start, at + chosen.offsets[i], held, depth)
            }
        }
    }
    else if variant == .ANY || variant == .FUNCTION || variant == .TYPE {
        schema_zero(out, at, info.size)
    }
}

/**
 * Follow a pointer in the bytes being written, unless it's a rawptr or too deep, which are written as 0.
 *
 * @param out The bytes being written.
 * @param start Where the whole value being written starts in them, from which distances are measured.
 * @param at Where the pointer is in them, in bytes.
 * @param pointed The type it points to, or None for a rawptr, whose target's size isn't known.
 * @param depth How many pointers deep the pointer is; at SCHEMA_MAX_DEPTH or more, it's written as 0.
 */
schema_fix_pointer :: fn(out: ptr[mut SchemaBytes], start: usize, at: usize, pointed: ptr[compiler.TypeInfo]?, depth: int) {
    if (pointed is_none) || depth >= SCHEMA_MAX_DEPTH {
        schema_set_word(out, at, 0)
        return void
    }
    target :: pointed or_return void
    match schema_follow(out, start, at, target.size) {
        case Some(copied) => schema_fix(out, start, copied, target, depth + 1)
        case None => {}
    }
}

/**
 * Fix the pointers of an array in the bytes being written, from one of its dimensions on.
 *
 * A static array's elements are fixed in place; a view's or dynamic array's are copied after, with a dynamic array's
 * capacity and allocator written as 0, since they mean nothing elsewhere.
 *
 * @param out The bytes being written.
 * @param start Where the whole value being written starts in them, from which distances are measured.
 * @param at Where the array starts in them, in bytes.
 * @param info The array's type information, not null and only read: its dimensions, outermost first, each static, a
 *     view or dynamic, and the base type of its elements.
 * @param dimension The first dimension handled, from 0; past the last, the array's element is handled.
 * @param depth How many pointers deep the array is, as schema_fix counts it.
 */
schema_fix_array :: fn(out: ptr[mut SchemaBytes], start: usize, at: usize, info: ptr[compiler.TypeInfoArray], dimension: usize, depth: int) {
    dimensions :: info.dimensions
    if dimension >= dimensions.count {
        schema_fix(out, start, at, info.base_type, depth)
        return void
    }
    element_size :: schema_dimension_element_size(info, dimension)
    array_type :: dimensions[dimension].type
    elements := at
    count := dimensions[dimension].count
    if array_type == .VIEW || array_type == .DYNAMIC {
        // count, then data; a dynamic array's capacity and allocator after them mean nothing elsewhere
        count = cast[usize](schema_word(out, at))
        if array_type == .DYNAMIC {
            schema_zero(out, at + 16, size_of(ResizableArray) - 16)
        }
        elements = schema_follow(out, start, at + 8, count * element_size) or_return void
    }
    if !schema_holds_pointers_array(info, dimension) {
        return void
    }
    for index in cast[usize](0)..<count {
        schema_fix_array(out, start, elements + index * element_size, info, dimension + 1, depth)
    }
}

/**
 * Make a mask of the bits of a union's tag.
 *
 * @param size The tag's size in bytes, 0 for no tag; 8 or more is the whole word.
 * @return The size's lowest bits set: 0 for 0 bytes, all of them for 8 or more.
 */
schema_mask_of :: fn(size: usize) -> u64 {
    if size >= 8 {
        return 0xffffffffffffffff
    }
    return (cast[u64](1) << (8 * size)) - 1
}

/**
 * Find whether a value of a type holds anything schema_fix changes, so a value without any can be skipped.
 *
 * @param type A type's information, not null, only read; its aliases are seen through.
 * @param depth How many types in the search is, 0 at the start; at SCHEMA_MAX_DEPTH, the answer is true, the safe one.
 * @return Whether it holds a string, pointer, any, function, type value or union, or an array other than a static
 *     one, directly or in a member; true too when the search goes too deep to tell.
 */
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

/**
 * Find whether an array holds anything schema_fix changes, from one of its dimensions on.
 *
 * @param info The array's type information, not null and only read: its dimensions, outermost first, each static, a
 *     view or dynamic, and the base type of its elements.
 * @param dimension The first dimension looked at, from 0.
 * @return Whether a dimension from there on is a view or a dynamic array, or its element holds pointers.
 */
schema_holds_pointers_array :: fn(info: ptr[compiler.TypeInfoArray], dimension: usize) -> bool {
    for i in dimension..<info.dimensions.count {
        if info.dimensions[i].type != .STATIC {
            return true
        }
    }
    return schema_holds_pointers(info.base_type, 0)
}

/**
 * Find the type an alias names, distinct or not, through any number of them, since a value's layout is its base type's.
 *
 * @param info A type's information, not null, only read; it may be an alias or anything else.
 * @return The first type that isn't an alias: info itself when it isn't one.
 */
schema_unaliased :: fn(info: ptr[compiler.TypeInfo]) -> ptr[compiler.TypeInfo] {
    result := info
    loop {
        if result.variant != .ALIAS {
            return result
        }
        result = cast[ptr[compiler.TypeInfoAlias]](result).base_type
    }
}

/**
 * Compute the size of each element of one of an array's dimensions.
 *
 * @param info The array's type information, not null and only read: its dimensions, outermost first, each static, a
 *     view or dynamic, and the base type of its elements.
 * @param dimension The dimension, from 0, whose elements are the next dimension's arrays or, for the last, the base
 *     type's values.
 * @return The size in bytes: the base type's for the last dimension, an ArrayView's or a ResizableArray's when the
 *     next is a view or dynamic, and a static one's count times its own elements' size.
 */
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
