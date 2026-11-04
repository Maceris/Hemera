package reflection

import compiler from "base"
import runtime from "base"

/**
 * Give a string, boolean or enum value as text, without allocating.
 *
 * Numbers need somewhere to be written, so they're left to as_text.
 *
 * @param value The value, of any type; aliases are followed to the type they're based on.
 * @return result The text: a string as it is, a view of the value's own bytes, good while they are; "true" or "false";
 *     or an enum member's name, from the type information, good for the program's life. Empty when valid is false.
 * @return valid Whether the value could be given as text: false for any other type, a cstring, or an enum value that
 *     matches no member.
 */
as_string :: fn(value: any) -> (result: string, valid: bool) {
    info :: unaliased(type_info_of(value.type))
    if info.variant == .STRING {
        string_info :: cast[ptr[compiler.TypeInfoString]](info)
        if string_info.is_raw {
            return "", false
        }
        text :: cast[ptr[string]](value.data)
        return text^, true
    }
    if info.variant == .BOOLEAN {
        if read_unsigned(value.data, info.size) != 0 {
            return "true", true
        }
        return "false", true
    }
    if info.variant == .ENUM {
        name :: enum_member_name(value)
        if name is_none {
            return "", false
        }
        text :: name or_else ""
        return text, true
    }
    // Numbers need somewhere to be written: as_text
    return "", false
}

/**
 * Give a value as text as as_string does, and numbers too, written into storage.
 *
 * An integer is written in decimal, with a - when it's negative, and a float as the shortest text that reads back as
 * it (runtime.format_shortest_float).
 *
 * @param value The value, of any type; aliases are followed to the type they're based on.
 * @param storage Where a number's text is written; untouched for what as_string gives. An integer takes at most 20
 *     bytes, sign included.
 * @return result The text: as as_string gives it, or a view of storage, good while storage is. Empty when valid is
 *     false.
 * @return valid Whether the value could be given as text: false for other types, integers wider than 8 bytes, floats
 *     other than 16, 32 and 64 bits, or a number storage is too small for (in which case some of storage may have been
 *     written).
 */
as_text :: fn(value: any, storage: mut u8[]) -> (result: string, valid: bool) {
    text, valid :: as_string(value)
    if valid {
        return text, true
    }
    info :: unaliased(type_info_of(value.type))
    written := StorageSink.{bytes = storage}
    sink :: runtime.FormatSink.{target = cast[rawptr](&written), emit = storage_sink_byte}
    if info.variant == .INTEGER && info.size <= 8 {
        raw :: cast[u64](read_unsigned(value.data, info.size))
        if cast[ptr[compiler.TypeInfoInteger]](info).is_signed {
            // Its sign carried up from its top bit
            shift :: 64 - cast[u64](info.size) * 8
            signed :: bit_cast[i64](raw << shift) >> shift
            runtime.format_integer(sink, runtime.FormatSpec.{}, signed < 0, if signed < 0 { 0 - bit_cast[u64](signed) } else { raw })
        }
        else {
            runtime.format_integer(sink, runtime.FormatSpec.{}, false, raw)
        }
    }
    else if info.variant == .FLOAT && (info.size == 2 || info.size == 4 || info.size == 8) {
        exponent_bits : u64 = if info.size == 2 { 5 } else if info.size == 4 { 8 } else { 11 }
        fraction_bits : u64 = if info.size == 2 { 10 } else if info.size == 4 { 23 } else { 52 }
        runtime.format_shortest_float(sink, cast[u64](read_unsigned(value.data, info.size)), exponent_bits, fraction_bits)
    }
    else {
        return "", false
    }
    if written.overflowed || written.count == 0 || storage.count == 0 {
        return "", false
    }
    return string_of(&storage[0], written.count), true
}

/** Bytes written into a view, and whether more came than it holds; #scoped, since the view may be of the stack. */
StorageSink :: struct #scoped {
    /** Where the bytes go. */
    bytes : mut u8[],
    /** How many bytes have been written, from bytes' start, up to bytes.count. */
    count : usize,
    /** Whether a byte came with no room left for it, and was dropped. */
    overflowed : bool,
}

/**
 * Write one byte to a StorageSink: the emit function of a runtime.FormatSink over one.
 *
 * @param target The StorageSink, as a ptr[mut StorageSink].
 * @param byte The byte, added after those written, or dropped, setting overflowed, if there's no room.
 */
storage_sink_byte :: fn(target: rawptr, byte: u8) {
    sink :: cast[ptr[mut StorageSink]](target)
    if sink.count < sink.bytes.count {
        sink.bytes[sink.count] = byte
        sink.count += 1
    }
    else {
        sink.overflowed = true
    }
}

/**
 * Find the name of the enum member a value holds.
 *
 * This lets compile-time checks compare enum values from another program by name, since the enum type itself differs
 * between programs.
 *
 * @param value The value, of any type; aliases are followed to the type they're based on.
 * @return The member's name, from the type information, good for the program's life; the first member's when several
 *     have the value. Null if the value isn't an enum, or matches no member, like flags combined.
 */
enum_member_name :: fn(value: any) -> string? {
    info :: unaliased(type_info_of(value.type))
    if info.variant != .ENUM {
        return null
    }
    enum_info :: cast[ptr[compiler.TypeInfoEnum]](info)
    raw :: read_unsigned(value.data, info.size)
    for member_value, index in enum_info.values {
        if member_value == raw && index < enum_info.members.count {
            return enum_info.members[index]
        }
    }
    return null
}

/**
 * Tell whether two values have the same type and value.
 *
 * Strings compare by contents, arrays element by element, and structs member by member. Pointers compare by address,
 * and aren't followed, so cycles can't recurse forever. Floats compare with ==, so NaN never equals anything. #union
 * structs and unions compare their bytes, since type info doesn't say which variant is in use, so padding and bytes
 * an unused variant left can make equal values unequal. Values in an any are compared by what they hold.
 *
 * @param a A value of any type, its data only read; either side of the comparison, as equal is symmetric.
 * @param b The value compared with a, of any type; its data only read.
 * @return True if their types are the same, not just alike, and their values are equal as above; false otherwise.
 */
equal :: fn(a, b: any) -> bool {
    if a.type != b.type {
        return false
    }
    return values_equal(a.data, b.data, type_info_of(a.type))
}

/**
 * Tell whether two values of one type are equal, as equal compares them.
 *
 * @param a The first value's address.
 * @param b The second value's address.
 * @param type_info Their type.
 * @return True if they're equal.
 */
values_equal :: fn(a, b: rawptr, type_info: ptr[compiler.TypeInfo]) -> bool {
    info :: unaliased(type_info)
    if info.variant == .VOID {
        return true
    }
    if info.variant == .ANY {
        any_a :: cast[ptr[any]](a)
        any_b :: cast[ptr[any]](b)
        return equal(any_a^, any_b^)
    }
    if info.variant == .STRING {
        string_info :: cast[ptr[compiler.TypeInfoString]](info)
        return strings_equal(a, b, string_info.is_raw)
    }
    if info.variant == .FLOAT {
        return floats_equal(a, b, info.size)
    }
    if info.variant == .COMPLEX {
        half :: info.size / 2
        return floats_equal(a, b, half) && floats_equal(a + half, b + half, half)
    }
    if info.variant == .QUATERNION {
        quarter :: info.size / 4
        for part in 0..<4 {
            offset :: cast[usize](part) * quarter
            if !floats_equal(a + offset, b + offset, quarter) {
                return false
            }
        }
        return true
    }
    if info.variant == .STRUCT {
        struct_info :: cast[ptr[compiler.TypeInfoStruct]](info)
        if struct_info.is_union {
            return bytes_equal(a, b, info.size)
        }
        for &member in struct_info.members {
            if !values_equal(a + member.offset, b + member.offset, member.member_type) {
                return false
            }
        }
        return true
    }
    if info.variant == .ARRAY {
        return arrays_equal(a, b, cast[ptr[compiler.TypeInfoArray]](info), 0)
    }
    // Integers, booleans, characters, enums, pointers, functions, types and unions
    return bytes_equal(a, b, info.size)
}

/**
 * Compare two arrays element by element, from a dimension onwards.
 *
 * @param a The first array's address: of a fixed array's elements, or of a view or a dynamic array.
 * @param b The second array's address, of the same type.
 * @param info Their type.
 * @param dimension Which dimension a and b are at, from 0 for the outermost; at the last, the elements are compared.
 * @return True if they have the same counts and every element is equal; false otherwise.
 */
arrays_equal :: fn(a, b: rawptr, info: ptr[compiler.TypeInfoArray], dimension: usize) -> bool {
    if dimension >= info.dimensions.count {
        return values_equal(a, b, info.base_type)
    }
    data_a := a
    data_b := b
    count := info.dimensions[dimension].count
    array_type :: info.dimensions[dimension].type
    if array_type == .VIEW {
        view_a :: cast[ptr[runtime.ArrayView]](a)
        view_b :: cast[ptr[runtime.ArrayView]](b)
        if view_a.count != view_b.count {
            return false
        }
        data_a = view_a.data
        data_b = view_b.data
        count = view_a.count
    }
    else if array_type == .DYNAMIC {
        dynamic_a :: cast[ptr[runtime.ResizableArray]](a)
        dynamic_b :: cast[ptr[runtime.ResizableArray]](b)
        if dynamic_a.count != dynamic_b.count {
            return false
        }
        data_a = dynamic_a.data
        data_b = dynamic_b.data
        count = dynamic_a.count
    }

    element_size :: dimension_element_size(info, dimension)
    for index in 0..<count {
        offset :: index * element_size
        if !arrays_equal(data_a + offset, data_b + offset, info, dimension + 1) {
            return false
        }
    }
    return true
}

/**
 * Find the size of one element of an array at a dimension, which is itself an array unless it's the last one.
 *
 * @param info The array's type.
 * @param dimension The dimension, from 0 for the outermost.
 * @return The element's size in bytes: the base type's at the last dimension, a view's or dynamic array's header when
 *     the next dimension is one, and otherwise a fixed array's count times its element's size.
 */
dimension_element_size :: fn(info: ptr[compiler.TypeInfoArray], dimension: usize) -> usize {
    inner :: dimension + 1
    if inner >= info.dimensions.count {
        return info.base_type.size
    }
    inner_type :: info.dimensions[inner].type
    if inner_type == .VIEW {
        return size_of(runtime.ArrayView)
    }
    if inner_type == .DYNAMIC {
        return size_of(runtime.ResizableArray)
    }
    return info.dimensions[inner].count * dimension_element_size(info, inner)
}

/**
 * Tell whether two strings have the same bytes.
 *
 * @param a The first string's address: of a string, or of a cstring.
 * @param b The second string's address, of the same type.
 * @param is_raw True for cstrings, which are compared up to their zero bytes, and must have them.
 * @return True if their bytes are the same; false otherwise.
 */
strings_equal :: fn(a, b: rawptr, is_raw: bool) -> bool {
    if is_raw {
        // cstrings: pointers to bytes ending at the first 0
        pointer_a :: cast[ptr[rawptr]](a)
        pointer_b :: cast[ptr[rawptr]](b)
        index : usize = 0
        loop {
            byte_a :: cast[ptr[u8]](pointer_a^ + index)
            byte_b :: cast[ptr[u8]](pointer_b^ + index)
            if byte_a^ != byte_b^ {
                return false
            }
            if byte_a^ == 0 {
                return true
            }
            index += 1
        }
    }
    string_a :: cast[ptr[runtime.StringView]](a)
    string_b :: cast[ptr[runtime.StringView]](b)
    return string_a.count == string_b.count && bytes_equal(string_a.data, string_b.data, string_a.count)
}

/**
 * Tell whether two floats are equal, as == compares them.
 *
 * @param a The first float's address.
 * @param b The second float's address.
 * @param size Their size in bytes: 2, 4 or 8. Other sizes compare their bytes.
 * @return True if they're equal: never for NaN, and always for 0 and -0.
 */
floats_equal :: fn(a, b: rawptr, size: usize) -> bool {
    if size == 2 {
        float_a :: cast[ptr[f16]](a)
        float_b :: cast[ptr[f16]](b)
        return float_a^ == float_b^
    }
    if size == 4 {
        float_a :: cast[ptr[f32]](a)
        float_b :: cast[ptr[f32]](b)
        return float_a^ == float_b^
    }
    if size == 8 {
        float_a :: cast[ptr[f64]](a)
        float_b :: cast[ptr[f64]](b)
        return float_a^ == float_b^
    }
    return bytes_equal(a, b, size)
}

/**
 * Tell whether two runs of bytes are the same.
 *
 * @param a The first run's start.
 * @param b The second run's start.
 * @param count How many bytes to compare; 0 is always equal.
 * @return True if every byte is the same; false otherwise.
 */
bytes_equal :: fn(a, b: rawptr, count: usize) -> bool {
    for index in 0..<count {
        byte_a :: cast[ptr[u8]](a + index)
        byte_b :: cast[ptr[u8]](b + index)
        if byte_a^ != byte_b^ {
            return false
        }
    }
    return true
}

/**
 * Read an unsigned integer, like an enum's or boolean's backing value.
 *
 * @param data Where it is.
 * @param size Its size in bytes: 1, 2, 4 or 8; anything else reads 16 bytes.
 * @return Its value, zero-extended.
 */
read_unsigned :: fn(data: rawptr, size: usize) -> u128 {
    if size == 1 {
        value :: cast[ptr[u8]](data)
        return value^
    }
    if size == 2 {
        value :: cast[ptr[u16]](data)
        return value^
    }
    if size == 4 {
        value :: cast[ptr[u32]](data)
        return value^
    }
    if size == 8 {
        value :: cast[ptr[u64]](data)
        return value^
    }
    value :: cast[ptr[u128]](data)
    return value^
}

/**
 * Follow aliases, including distinct ones, to the type they're based on.
 *
 * @param info A type.
 * @return The type it's based on; info itself when it isn't an alias.
 */
unaliased :: fn(info: ptr[compiler.TypeInfo]) -> ptr[compiler.TypeInfo] {
    result := info
    loop {
        alias_info :: cast[ptr[compiler.TypeInfoAlias]](result)
        result = alias_info.base_type
    }
    while result.variant == .ALIAS
    return result
}
