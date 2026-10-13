package reflection

import compiler from "base"
import runtime from "base"

/*
 * Strings, booleans and enum member names, without allocating.
 * valid is false for anything else.
 */
as_string :: fn(value: any) -> (result: string, valid: bool) {
    info :: unaliased(type_info_of(value.type_))
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
    //TODO numbers, which need std's string conversions, and so an allocator
    return "", false
}

/*
 * The name of the enum member value holds, or none if it isn't an enum or matches no member.
 * Lets compile-time checks compare enum values from another program by name, since the
 * enum type itself differs between programs.
 */
enum_member_name :: fn(value: any) -> string? {
    info :: unaliased(type_info_of(value.type_))
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

/*
 * Whether a and b have the same type and value.
 *
 * Strings compare by contents, arrays element by element, and structs member by member.
 * Pointers compare by address, and aren't followed, so cycles can't recurse forever.
 * Floats compare with ==, so NaN never equals anything. #union structs and unions compare
 * their bytes, since type info doesn't say which variant is in use.
 */
equal :: fn(a, b: any) -> bool {
    if a.type_ != b.type_ {
        return false
    }
    return values_equal(a.data, b.data, type_info_of(a.type_))
}

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
            offset :: part * quarter
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

// Compares the arrays a and b point to, from dimension onwards.
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

// Size of one element of the array at dimension, which is itself an array unless it's the last one.
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

// An unsigned integer of size bytes at data, like an enum's or boolean's backing value.
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

// Follows aliases, including distinct ones, to the type they're based on.
unaliased :: fn(info: ptr[compiler.TypeInfo]) -> ptr[compiler.TypeInfo] {
    result := info
    loop {
        alias_info :: cast[ptr[compiler.TypeInfoAlias]](result)
        result = alias_info.base_type
    }
    while result.variant == .ALIAS
    return result
}
