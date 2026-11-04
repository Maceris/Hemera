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

    /**
     * Compute T's schema hash, as a typed file of T carries it.
     *
     * @tparam T The file's value's type.
     * @return Its 32-byte schema hash (std/schema's hash), which the file system keeps with the file.
     */
    schema_hash_of :: fn[T]() -> u8[32] {
        return schema.hash(type_info_of(T))
    }

    /**
     * View a value built in out as a message is (begin, then append), as its bytes, for a typed file.
     *
     * @param out The value being built; its handles, if any, are ignored, as a file can't hold one.
     * @return Its used bytes, in out, good as long as out is and isn't begun again.
     */
    value_bytes :: fn(out: ptr[Outgoing]) -> u8[] {
        return view_of(cast[ptr[u8]](&out.words[0]), cast[usize](out.used))
    }

    /**
     * View a Relative's items in a typed file's bytes, from the value's start, as in a message.
     *
     * @tparam E The items' type.
     * @param bytes The file's bytes, which holds_value checked, so the Relative is inside them.
     * @param relative The Relative field, from the value.
     * @return Its items, in bytes, good as long as bytes are.
     */
    items_of :: fn[E](bytes: u8[], relative: slop_os.Relative[E]) -> E[] {
        return view_of(cast[ptr[E]](cast[u64](bytes.data) + cast[u64](relative.offset)), cast[usize](relative.count))
    }

    /**
     * Check whether bytes hold a T, as a message's value is checked.
     *
     * @tparam T The value's type.
     * @param bytes The bytes; only read.
     * @return True if they're at least T's size and at most 4 GiB, its bools and enums are in range, and its Relatives
     *     are within the bytes; false otherwise, and always for a T holding a handle, a channel, a pointer, a view or a
     *     union.
     */
    holds_value :: fn[T](bytes: u8[]) -> bool {
        return value_holds(type_info_of(T), bytes)
    }

    /**
     * View the T at the start of a typed file's bytes.
     *
     * @tparam T The value's type.
     * @param bytes The file's bytes, which holds_value[T] checked; anything else isn't safe to read as a T.
     * @return The value, in bytes, good as long as bytes are.
     */
    typed_value :: fn[T](bytes: u8[]) -> ptr[T] {
        return cast[ptr[T]](bytes.data)
    }

    /**
     * Check whether bytes hold a value of type, as holds_value checks it: what protocol_code's checks check, from
     * type's info.
     *
     * @param type The type checked for, not null and only read: its size is the value's fixed part, and its parts are
     *     checked as part_holds checks them.
     * @param bytes The bytes; only read.
     * @return True if they're at least type's size and at most 4 GiB, and every part of it holds (part_holds).
     */
    value_holds :: fn(type: ptr[compiler.TypeInfo], bytes: u8[]) -> bool {
        if bytes.count < type.size || cast[u64](bytes.count) > 0xffffffff {
            return false
        }
        return part_holds(type, 0, bytes, type.size)
    }

    /**
     * Check whether the part of a value of type at offset holds.
     *
     * A file can't hold a handle, a channel, a pointer, a view or a union, so none does.
     *
     * @param type The part's type, not null and only read; an alias is checked as what it stands for, unless it's a
     *     handle, which never holds.
     * @param offset Where the part is, in bytes from the value's start.
     * @param bytes The whole value's bytes, only read; offset is counted from their start, and a part past their end
     *     reads as 0.
     * @param fixed The size of the value's fixed part in bytes, which Relatives' items start at or after.
     * @return True for integers, floats and characters; bools of 0 or 1; enums holding one of their members' values;
     *     static arrays and structs whose parts all hold; and Relatives of plain data within the bytes. false for
     *     anything else.
     */
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

    /**
     * Check whether every bit pattern of type is a value of it, so its items needn't be checked one by one.
     *
     * @param type Any type, followed through its aliases and into its arrays and structs; it isn't changed.
     * @return True for integers, floats and characters, and arrays and structs of only those; false for anything else,
     *     handles, channels and Relatives among them.
     */
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

    /**
     * Open the file of T at path beneath directory, as open_in opens one.
     *
     * A file made has T's type; one that's there has to have it already.
     *
     * @tparam T The file's value's type.
     * @param directory The open directory path starts from; it stays open.
     * @param path The file's path beneath it, as is_beneath takes it.
     * @param mode Whether it's read, written or both, and whether it's made or emptied (OpenMode).
     * @return The open file, which the caller owns and closes with close.
     * @error InvalidPath The path isn't beneath directory (is_beneath).
     * @error WrongType The file that's there is of another type, or the file system keeps no types.
     * @error NotFound Nothing is at path, with a mode that doesn't make one.
     * @error AccessDenied The directory doesn't allow it, or was revoked.
     * @error IsADirectory The path is a folder.
     * @error OutOfMemory What opening it needed couldn't be allocated.
     * @error Other The directory's server didn't answer, or reported anything else.
     */
    open_typed_in :: fn[T](directory: Directory, path: string, mode: OpenMode) -> Result[File, OsError] {
        if !is_beneath(path) {
            return .Error(.InvalidPath)
        }
        file, error :: open_with_schema(directory, path, mode, schema_hash_of[T]())
        return as_result(file, error)
    }

    /**
     * Read the file of T at path beneath directory, checked to hold a T.
     *
     * @tparam T The file's value's type.
     * @param directory The open directory path starts from; it stays open.
     * @param path The file's path beneath it, as is_beneath takes it.
     * @param allocator Where the bytes are allocated from.
     * @return The file's bytes, which typed_value[T] reads, in a new array from allocator that the caller owns and
     *     gives back with runtime.free_array.
     * @error WrongType The file is of another type, or its bytes don't hold a T (as an empty file doesn't); nothing
     *     is left allocated.
     * @error InvalidPath The path isn't beneath directory (is_beneath).
     * @error NotFound Nothing is at path.
     * @error AccessDenied The directory doesn't allow it, or was revoked.
     * @error IsADirectory The path is a folder.
     * @error OutOfMemory The bytes couldn't be allocated.
     * @error Other The directory's server didn't answer, or reported anything else.
     */
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

    /**
     * Make, or replace, the file of T at path beneath directory, with a value's bytes.
     *
     * A file that's there has to be of T's type already, and is emptied when it's opened, so a failure while writing
     * leaves it holding only part of value.
     *
     * @tparam T The file's value's type.
     * @param directory The open directory path starts from; it stays open.
     * @param path The file's path beneath it, as is_beneath takes it.
     * @param value The value's bytes, as value_bytes gives them; only read.
     * @return Null if it worked; otherwise why not: WrongType when value doesn't hold a T (nothing is written) or the
     *     file is of another type, InvalidPath when path isn't beneath directory, or what open_typed_in or write gives.
     */
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
