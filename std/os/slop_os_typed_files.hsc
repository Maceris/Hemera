package os

/*
 * Typed files (the SlopOS repository's decisions 0046, 0108): a file whose bytes are a value of one type, laid out as a
 * protocol message's value is (position-independent, through Relatives), with that type's schema hash, which the file
 * system keeps. Opening one asks for its type, and is refused (WrongType) if the file is of another; reading one checks
 * its bytes as a message's are checked before anything uses them.
 *
 *     settings :: os.read_typed_in[Settings](directory, "settings") or_return 1
 *     defer runtime.free_array(settings)
 *     value :: os.typed_value[Settings](settings)
 */
#if OS == .SlopOS {
    import compiler from "base"
    import runtime from "base"
    import schema from "std"
    import slop_os from "std/os"

    // T's schema hash, as a typed file of T carries it.
    schema_hash_of :: fn[T]() -> u8[32] {
        return schema.hash(type_info_of(T))
    }

    // A value's bytes, built in out as a message is (begin, then append), for a typed file.
    value_bytes :: fn(out: ptr[Outgoing]) -> u8[] {
        return view_of(cast[ptr[u8]](&out.words[0]), cast[usize](out.used))
    }

    // A Relative's items, in a typed file's bytes that holds_value checked: from the value's start, as in a message.
    items_of :: fn[E](bytes: u8[], relative: slop_os.Relative[E]) -> E[] {
        return view_of(cast[ptr[E]](cast[u64](bytes.data) + cast[u64](relative.offset)), cast[usize](relative.count))
    }

    // Whether bytes hold a T, checked as a message's value is: booleans and enums in range, Relatives within the bytes.
    holds_value :: fn[T](bytes: u8[]) -> bool {
        return value_holds(type_info_of(T), bytes)
    }

    // The T at the start of bytes that holds_value checked.
    typed_value :: fn[T](bytes: u8[]) -> ptr[T] {
        return cast[ptr[T]](bytes.data)
    }

    // Whether bytes hold a value of type, as holds_value checks it: what protocol_code's checks check, from type's info.
    value_holds :: fn(type: ptr[compiler.TypeInfo], bytes: u8[]) -> bool {
        if bytes.count < type.size || cast[u64](bytes.count) > 0xffffffff {
            return false
        }
        return part_holds(type, 0, bytes, type.size)
    }

    // Whether the part of type at offset holds: a file can't hold a handle, a pointer, a view or a union, so none does.
    part_holds :: fn(type: ptr[compiler.TypeInfo], offset: usize, bytes: u8[], fixed: usize) -> bool {
        if type.variant == .INTEGER || type.variant == .FLOAT || type.variant == .CHAR {
            return true
        }
        if type.variant == .BOOLEAN {
            return read_message(bytes, offset, 1) <= 1
        }
        if type.variant == .ENUM {
            enumeration :: cast[ptr[compiler.TypeInfoEnum]](type)
            value :: read_message(bytes, offset, type.size)
            for each in enumeration.values {
                if cast[u64](each) == value {
                    return true
                }
            }
            return false
        }
        if type.variant == .ALIAS {
            return !is_handle(type) && part_holds(cast[ptr[compiler.TypeInfoAlias]](type).base_type, offset, bytes, fixed)
        }
        if type.variant == .ARRAY {
            array :: cast[ptr[compiler.TypeInfoArray]](type)
            count := cast[usize](1)
            for dimension in array.dimensions {
                if dimension.type != .STATIC {
                    return false
                }
                count *= dimension.count
            }
            element_size :: if count == 0 { cast[usize](0) } else { type.size / count }
            for i in 0..<count {
                if !part_holds(array.base_type, offset + i * element_size, bytes, fixed) {
                    return false
                }
            }
            return true
        }
        if type.variant == .STRUCT {
            structure :: cast[ptr[compiler.TypeInfoStruct]](type)
            if starts_with(structure.name, "Channel[") || starts_with(structure.name, "Listener[") {
                return false
            }
            if starts_with(structure.name, "Relative[") {
                for member in structure.members {
                    if member.name == "elements" {
                        held :: cast[ptr[compiler.TypeInfoArray]](member.member_type).base_type
                        // Plain data only, as in a message: its elements aren't checked one by one
                        return plain(held) && relative_fits(bytes, cast[u32](bytes.count), offset, fixed, held.size, alignment_of(held))
                    }
                }
                return false
            }
            for member in structure.members {
                if !part_holds(member.member_type, offset + member.offset, bytes, fixed) {
                    return false
                }
            }
            return true
        }
        return false
    }

    // Whether every value of type is one: integers, floats and characters, and arrays and structs of only those.
    plain :: fn(type: ptr[compiler.TypeInfo]) -> bool {
        if type.variant == .INTEGER || type.variant == .FLOAT || type.variant == .CHAR {
            return true
        }
        if type.variant == .ALIAS {
            return !is_handle(type) && plain(cast[ptr[compiler.TypeInfoAlias]](type).base_type)
        }
        if type.variant == .ARRAY {
            return plain(cast[ptr[compiler.TypeInfoArray]](type).base_type)
        }
        if type.variant == .STRUCT {
            structure :: cast[ptr[compiler.TypeInfoStruct]](type)
            if starts_with(structure.name, "Channel[") || starts_with(structure.name, "Listener[") || starts_with(structure.name, "Relative[") {
                return false
            }
            for member in structure.members {
                if !plain(member.member_type) {
                    return false
                }
            }
            return true
        }
        return false
    }

    // The file of T at path beneath directory, opened as mode: one made has T's type; one there must have it.
    open_typed_in :: fn[T](directory: Directory, path: string, mode: OpenMode) -> Result[File, OsError] {
        if !is_beneath(path) {
            return .Error(.InvalidPath)
        }
        file, error :: open_with_schema(directory, path, mode, schema_hash_of[T]())
        return as_result(file, error)
    }

    // The bytes of the file of T at path beneath directory, checked to hold a T (WrongType if they don't).
    read_typed_in :: fn[T](directory: Directory, path: string, allocator := context.allocator) -> Result[u8[], OsError] #unrestricted {
        file :: open_typed_in[T](directory, path, .READ)?
        defer close(file)
        read :: read_all(file, allocator)?
        bytes :: string_bytes(read)
        if !holds_value[T](bytes) {
            runtime.free_array(bytes, allocator)
            return .Error(.WrongType)
        }
        return .Ok(bytes)
    }

    // The file of T at path beneath directory made, or replaced, with value's bytes, which must hold a T.
    write_typed_in :: fn[T](directory: Directory, path: string, value: u8[]) -> OsError? {
        if !holds_value[T](value) {
            return OsError.WrongType
        }
        file := File.{0}
        match open_typed_in[T](directory, path, .WRITE) {
            case Ok(opened) => file = opened
            case Error(error) => return error
        }
        error :: write(file, string_of(cast[ptr[u8]](value.data), value.count))
        close(file)
        return error
    }
}
