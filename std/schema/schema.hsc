package schema

import compiler from "base"
import runtime from "base"
import crypto from "std"

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
 */

VERSION : u16 : 1

// What each kind is in the bytes: fixed, whatever compiler.TypeInfoVariant's order becomes.
Kind :: enum #backed_by(u8) {
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
write :: fn(type: ptr[compiler.TypeInfo], into: ptr[mut u8[..]]) {
    // Each type by its address, as a number, so where they're kept isn't a question
    types : uintptr[..]
    defer runtime.array_free(&types)
    runtime.array_add(&types, cast[uintptr](plain(type)))
    // Each type reached, from the first, adds those it refers to that are new
    at : usize = 0
    loop {
        if at >= types.count {
            break
        }
        reach(cast[ptr[compiler.TypeInfo]](types[at]), &types)
        at += 1
    }
    for byte in u8.[0x48, 0x53, 0x43, 0x48] {
        runtime.array_add(into, byte)
    }
    number(into, cast[u64](VERSION), 2)
    number(into, cast[u64](types.count), 4)
    for each in types {
        describe(cast[ptr[compiler.TypeInfo]](each), &types, into)
    }
}

// A type's schema hash: BLAKE3-256 of its schema's bytes.
hash :: fn(type: ptr[compiler.TypeInfo]) -> u8[32] {
    bytes : u8[..]
    defer runtime.array_free(&bytes)
    write(type, &bytes)
    result : u8[32]
    crypto.blake3(bytes, result)
    return result
}

// The type a plain alias names, through any number of them.
plain :: fn(type: ptr[compiler.TypeInfo]) -> ptr[compiler.TypeInfo] {
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
place :: fn(type: ptr[compiler.TypeInfo], types: ptr[mut uintptr[..]]) -> usize {
    found :: cast[uintptr](plain(type))
    for each, i in types^ {
        if each == found {
            return i
        }
    }
    runtime.array_add(types, found)
    return types.count - 1
}

// Every type a type refers to, given a place.
reach :: fn(type: ptr[compiler.TypeInfo], types: ptr[mut uintptr[..]]) {
    variant :: type.variant
    if variant == .ALIAS {
        _ = place(cast[ptr[compiler.TypeInfoAlias]](type).base_type, types)
    }
    else if variant == .ARRAY {
        _ = place(cast[ptr[compiler.TypeInfoArray]](type).base_type, types)
    }
    else if variant == .ENUM {
        _ = place(cast[ptr[compiler.TypeInfoEnum]](type).backing_type, types)
    }
    else if variant == .FUNCTION {
        function :: cast[ptr[compiler.TypeInfoFunction]](type)
        for input in function.input {
            _ = place(input.type, types)
        }
        for output in function.output {
            _ = place(output.type, types)
        }
    }
    else if variant == .POINTER {
        pointer :: cast[ptr[compiler.TypeInfoPointer]](type)
        match pointer.base_type {
            case Some(pointed) => _ = place(pointed, types)
            case None => {}
        }
    }
    else if variant == .STRUCT {
        for member in cast[ptr[compiler.TypeInfoStruct]](type).members {
            _ = place(member.member_type, types)
        }
    }
    else if variant == .UNION {
        union_info :: cast[ptr[compiler.TypeInfoUnion]](type)
        match union_info.tag_type {
            case Some(tag) => _ = place(tag, types)
            case None => {}
        }
        for each_variant in union_info.variants {
            for held in each_variant.types {
                _ = place(held, types)
            }
        }
    }
    else if variant == .VECTOR {
        _ = place(cast[ptr[compiler.TypeInfoVector]](type).element_type, types)
    }
}

// One type's part of the bytes.
describe :: fn(type: ptr[compiler.TypeInfo], types: ptr[mut uintptr[..]], into: ptr[mut u8[..]]) {
    variant :: type.variant
    runtime.array_add(into, cast[u8](kind_of(variant)))
    number(into, cast[u64](type.size), 8)
    if variant == .ALIAS {
        alias :: cast[ptr[compiler.TypeInfoAlias]](type)
        name(into, alias.name)
        reference(into, alias.base_type, types)
    }
    else if variant == .ARRAY {
        array :: cast[ptr[compiler.TypeInfoArray]](type)
        reference(into, array.base_type, types)
        number(into, cast[u64](array.dimensions.count), 4)
        for dimension in array.dimensions {
            kind : u8 = if dimension.type == .STATIC { 1 } else if dimension.type == .DYNAMIC { 2 } else { 3 }
            runtime.array_add(into, kind)
            number(into, cast[u64](dimension.count), 8)
            flag(into, dimension.is_mutable)
        }
    }
    else if variant == .ENUM {
        enumeration :: cast[ptr[compiler.TypeInfoEnum]](type)
        name(into, enumeration.name)
        reference(into, enumeration.backing_type, types)
        number(into, cast[u64](enumeration.members.count), 4)
        for member, i in enumeration.members {
            name(into, member)
            value : u128 = if i < enumeration.values.count { enumeration.values[i] } else { 0 }
            number(into, cast[u64](value), 8)
            number(into, cast[u64](value >> 64), 8)
        }
    }
    else if variant == .FLOAT {
        endianness(into, cast[ptr[compiler.TypeInfoFloat]](type).endianness)
    }
    else if variant == .FUNCTION {
        function :: cast[ptr[compiler.TypeInfoFunction]](type)
        number(into, cast[u64](function.input.count), 4)
        for input in function.input {
            name(into, input.name)
            reference(into, input.type, types)
            flag(into, input.is_varargs)
            flag(into, input.is_escaping)
        }
        number(into, cast[u64](function.output.count), 4)
        for output in function.output {
            reference(into, output.type, types)
        }
        flag(into, function.never_returns)
    }
    else if variant == .INTEGER {
        integer :: cast[ptr[compiler.TypeInfoInteger]](type)
        flag(into, integer.is_signed)
        endianness(into, integer.endianness)
    }
    else if variant == .POINTER {
        pointer :: cast[ptr[compiler.TypeInfoPointer]](type)
        match pointer.base_type {
            case Some(pointed) => {
                flag(into, true)
                reference(into, pointed, types)
            }
            case None => flag(into, false)
        }
        flag(into, pointer.is_relative)
        flag(into, pointer.is_mutable)
    }
    else if variant == .STRING {
        flag(into, cast[ptr[compiler.TypeInfoString]](type).is_raw)
    }
    else if variant == .STRUCT {
        structure :: cast[ptr[compiler.TypeInfoStruct]](type)
        name(into, structure.name)
        number(into, cast[u64](structure.alignment), 8)
        flag(into, structure.is_packed)
        flag(into, structure.is_union)
        number(into, cast[u64](structure.members.count), 4)
        for member in structure.members {
            name(into, member.name)
            reference(into, member.member_type, types)
            number(into, cast[u64](member.offset), 8)
            flag(into, member.is_using)
        }
    }
    else if variant == .UNION {
        union_info :: cast[ptr[compiler.TypeInfoUnion]](type)
        name(into, union_info.name)
        flag(into, union_info.null_is_none)
        match union_info.tag_type {
            case Some(tag) => {
                flag(into, true)
                reference(into, tag, types)
            }
            case None => flag(into, false)
        }
        number(into, cast[u64](union_info.variants.count), 4)
        for each_variant in union_info.variants {
            name(into, each_variant.name)
            number(into, cast[u64](each_variant.types.count), 4)
            for held, i in each_variant.types {
                reference(into, held, types)
                offset : usize = if i < each_variant.offsets.count { each_variant.offsets[i] } else { 0 }
                number(into, cast[u64](offset), 8)
            }
        }
    }
    else if variant == .VECTOR {
        vector :: cast[ptr[compiler.TypeInfoVector]](type)
        reference(into, vector.element_type, types)
        number(into, cast[u64](vector.count), 8)
        flag(into, vector.is_bits)
    }
}

kind_of :: fn(variant: compiler.TypeInfoVariant) -> Kind {
    return match variant {
        case .ALIAS => Kind.Alias
        case .ANY => Kind.Any
        case .ARRAY => Kind.Array
        case .BOOLEAN => Kind.Boolean
        case .CHAR => Kind.Char
        case .COMPLEX => Kind.Complex
        case .ENUM => Kind.Enum
        case .FLOAT => Kind.Float
        case .FUNCTION => Kind.Function
        case .INTEGER => Kind.Integer
        case .POINTER => Kind.Pointer
        case .QUATERNION => Kind.Quaternion
        case .STRING => Kind.String
        case .STRUCT => Kind.Struct
        case .TYPE => Kind.Type
        case .UNION => Kind.Union
        case .VECTOR => Kind.Vector
        case .VOID => Kind.Void
    }
}

// A number's lowest bytes, little-endian.
number :: fn(into: ptr[mut u8[..]], value: u64, bytes: usize) {
    for i in cast[usize](0)..<bytes {
        runtime.array_add(into, cast[u8]((value >> (8 * i)) & 0xff))
    }
}

flag :: fn(into: ptr[mut u8[..]], value: bool) {
    runtime.array_add(into, if value { cast[u8](1) } else { cast[u8](0) })
}

name :: fn(into: ptr[mut u8[..]], text: string) {
    number(into, cast[u64](text.count), 4)
    for byte in view_of(cast[ptr[u8]](text.data), text.count) {
        runtime.array_add(into, byte)
    }
}

endianness :: fn(into: ptr[mut u8[..]], value: compiler.Endianness) {
    runtime.array_add(into, if value == .BIG { cast[u8](1) } else if value == .LITTLE { cast[u8](2) } else { cast[u8](3) })
}

// A type it refers to, by its place, which reach gave it.
reference :: fn(into: ptr[mut u8[..]], type: ptr[compiler.TypeInfo], types: ptr[mut uintptr[..]]) {
    number(into, cast[u64](place(type, types)), 4)
}
