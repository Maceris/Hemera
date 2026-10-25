package os

import intrinsics from "base"
import runtime from "base"

/*
 * Windows' side of std/os, through kernel32's wide (UTF-16) functions. Paths and names are
 * converted from UTF-8 into memory from the context's allocator for each call, with a terminator.
 */
#if OS == .Windows {
    KERNEL32 :: #library("kernel32")

    GetLastError #foreign(KERNEL32) : fn() -> u32 : ---
    GetEnvironmentVariableW #foreign(KERNEL32) : fn(name: rawptr, buffer: rawptr, size: u32) -> u32 : ---
    CreateFileW #foreign(KERNEL32) : fn(
        name: rawptr,
        access: u32,
        share: u32,
        security: rawptr,
        disposition: u32,
        flags: u32,
        template: rawptr,
    ) -> rawptr : ---
    CloseHandle #foreign(KERNEL32) : fn(handle: rawptr) -> i32 : ---
    ReadFile #foreign(KERNEL32) : fn(file: rawptr, buffer: rawptr, count: u32, read: ptr[mut u32], overlapped: rawptr) -> i32 : ---
    WriteFile #foreign(KERNEL32) : fn(file: rawptr, bytes: rawptr, count: u32, written: ptr[mut u32], overlapped: rawptr) -> i32 : ---
    SetFilePointerEx #foreign(KERNEL32) : fn(file: rawptr, distance: i64, position: rawptr, method: u32) -> i32 : ---
    GetFileSizeEx #foreign(KERNEL32) : fn(file: rawptr, size: ptr[mut i64]) -> i32 : ---
    DeleteFileW #foreign(KERNEL32) : fn(name: rawptr) -> i32 : ---
    MoveFileExW #foreign(KERNEL32) : fn(from: rawptr, to: rawptr, flags: u32) -> i32 : ---
    GetFileAttributesW #foreign(KERNEL32) : fn(name: rawptr) -> u32 : ---
    CreateDirectoryW #foreign(KERNEL32) : fn(name: rawptr, security: rawptr) -> i32 : ---
    RemoveDirectoryW #foreign(KERNEL32) : fn(name: rawptr) -> i32 : ---
    FindFirstFileW #foreign(KERNEL32) : fn(pattern: rawptr, data: rawptr) -> rawptr : ---
    FindNextFileW #foreign(KERNEL32) : fn(search: rawptr, data: rawptr) -> i32 : ---
    FindClose #foreign(KERNEL32) : fn(search: rawptr) -> i32 : ---
    GetCurrentDirectoryW #foreign(KERNEL32) : fn(size: u32, buffer: rawptr) -> u32 : ---
    SetCurrentDirectoryW #foreign(KERNEL32) : fn(name: rawptr) -> i32 : ---

    GENERIC_READ : u32 : 0x80000000
    GENERIC_WRITE : u32 : 0x40000000
    FILE_SHARE_ALL : u32 : 7
    CREATE_ALWAYS : u32 : 2
    OPEN_EXISTING : u32 : 3
    OPEN_ALWAYS : u32 : 4
    FILE_ATTRIBUTE_NORMAL : u32 : 0x80
    FILE_ATTRIBUTE_DIRECTORY : u32 : 0x10
    INVALID_FILE_ATTRIBUTES : u32 : 0xffffffff
    FILE_END : u32 : 2
    MOVEFILE_REPLACE_EXISTING : u32 : 1
    MOVEFILE_COPY_ALLOWED : u32 : 2
    INVALID_HANDLE : u64 : 0xffff_ffff_ffff_ffff
    ERROR_BROKEN_PIPE : u32 : 109
    ERROR_ENVVAR_NOT_FOUND : u32 : 203

    // The OsError for GetLastError's code.
    error_of :: fn(code: u32) -> OsError {
        // FILE_NOT_FOUND, PATH_NOT_FOUND, INVALID_DRIVE, BAD_NETPATH, ENVVAR_NOT_FOUND
        if code == 2 || code == 3 || code == 15 || code == 53 || code == 203 {
            return .NotFound
        }
        // ACCESS_DENIED, WRITE_PROTECT, SHARING_VIOLATION, LOCK_VIOLATION
        if code == 5 || code == 19 || code == 32 || code == 33 {
            return .AccessDenied
        }
        // FILE_EXISTS, ALREADY_EXISTS
        if code == 80 || code == 183 {
            return .AlreadyExists
        }
        // DIRECTORY (the name isn't a folder)
        if code == 267 {
            return .NotADirectory
        }
        // DIR_NOT_EMPTY
        if code == 145 {
            return .DirectoryNotEmpty
        }
        // INVALID_NAME, BAD_PATHNAME, FILENAME_EXCED_RANGE, INVALID_PARAMETER
        if code == 123 || code == 161 || code == 206 || code == 87 {
            return .InvalidPath
        }
        // NOT_ENOUGH_MEMORY, OUTOFMEMORY
        if code == 8 || code == 14 {
            return .OutOfMemory
        }
        return .Other
    }

    last_error :: fn() -> OsError {
        return error_of(GetLastError())
    }

    // text as UTF-16 with a terminator, from the context's allocator, which free_wide gives back. Empty if memory ran out.
    wide :: fn(text: string) -> u16[] {
        units, error :: runtime.new_array(u16, text.count + 1, context.allocator)
        if error != null {
            empty : u16[]
            return empty
        }
        count :: runtime.utf8_to_utf16(text, units)
        if count < units.count {
            units[count] = 0
        }
        return units
    }

    free_wide :: fn(units: u16[]) {
        runtime.free_array(units, context.allocator)
    }

    // A path as UTF-16, or InvalidPath for one holding a 0, which would cut it short.
    wide_path :: fn(path: string) -> (units : u16[], error : OsError?) {
        empty : u16[]
        for character in path {
            if character == cast[char](0) {
                return empty, OsError.InvalidPath
            }
        }
        units :: wide(path)
        if units.count == 0 {
            return empty, OsError.OutOfMemory
        }
        return units, null
    }

    // count UTF-16 units at start as UTF-8, from allocator.
    narrow :: fn(start: rawptr, count: usize, allocator: runtime.Allocator) -> (text #unrestricted : string, error : OsError?) {
        if count == 0 {
            return "", null
        }
        units :: view_of(cast[ptr[u16]](start), count)
        none : mut u8[]
        length :: runtime.utf16_to_utf8(units, none)
        bytes, error :: runtime.new_array(u8, length, allocator)
        if error != null || bytes.count == 0 {
            return "", OsError.OutOfMemory
        }
        runtime.utf16_to_utf8(units, bytes)
        return string_of(&bytes[0], bytes.count), null
    }

    system_get_environment :: fn(name: string, allocator: runtime.Allocator) -> (value #unrestricted : string, error : OsError?) {
        name_units, name_error :: wide_path(name)
        if name_error != null {
            return "", name_error
        }
        defer free_wide(name_units)
        // The size with its terminator, then the value, which may change in between
        loop {
            needed :: GetEnvironmentVariableW(cast[rawptr](name_units.data), null, 0)
            if needed == 0 {
                return "", last_error()
            }
            buffer, buffer_error :: runtime.new_array(u16, cast[usize](needed), context.allocator)
            if buffer_error != null {
                return "", OsError.OutOfMemory
            }
            length :: GetEnvironmentVariableW(cast[rawptr](name_units.data), cast[rawptr](buffer.data), needed)
            if length < needed {
                value, error :: narrow(cast[rawptr](buffer.data), cast[usize](length), allocator)
                free_wide(buffer)
                return value, error
            }
            free_wide(buffer)
        }
    }

    system_open :: fn(path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        units, path_error :: wide_path(path)
        if path_error != null {
            return File.{0}, path_error
        }
        defer free_wide(units)
        access := GENERIC_READ
        disposition := OPEN_EXISTING
        if mode == .WRITE {
            access = GENERIC_WRITE
            disposition = CREATE_ALWAYS
        }
        else if mode == .APPEND {
            access = GENERIC_WRITE
            disposition = OPEN_ALWAYS
        }
        else if mode == .READ_WRITE {
            access = GENERIC_READ | GENERIC_WRITE
        }
        handle :: CreateFileW(cast[rawptr](units.data), access, FILE_SHARE_ALL, null, disposition, FILE_ATTRIBUTE_NORMAL, null)
        if cast[u64](handle) == INVALID_HANDLE {
            code :: GetLastError()
            // Opening a folder as a file
            if code == 5 && system_path_kind(path) == .DIRECTORY {
                return File.{0}, OsError.IsADirectory
            }
            return File.{0}, error_of(code)
        }
        if mode == .APPEND {
            SetFilePointerEx(handle, 0, null, FILE_END)
        }
        return File.{cast[u64](handle)}, null
    }

    system_close :: fn(file: File) {
        CloseHandle(cast[rawptr](file.handle))
    }

    // At most this many bytes a ReadFile or WriteFile, which take a u32
    MOST_PER_CALL : usize : 0x40000000

    system_read :: fn(file: File, buffer: mut u8[]) -> (count : usize, error : OsError?) {
        if buffer.count == 0 {
            return 0, null
        }
        asked :: if buffer.count > MOST_PER_CALL { MOST_PER_CALL } else { buffer.count }
        read : u32 = 0
        if ReadFile(cast[rawptr](file.handle), cast[rawptr](buffer.data), cast[u32](asked), &read, null) == 0 {
            code :: GetLastError()
            // A pipe whose writer closed it: the end
            if code == ERROR_BROKEN_PIPE {
                return 0, null
            }
            return 0, error_of(code)
        }
        return cast[usize](read), null
    }

    system_write :: fn(file: File, bytes: rawptr, count: usize) -> (written : usize, error : OsError?) {
        asked :: if count > MOST_PER_CALL { MOST_PER_CALL } else { count }
        written : u32 = 0
        if WriteFile(cast[rawptr](file.handle), bytes, cast[u32](asked), &written, null) == 0 {
            return 0, last_error()
        }
        return cast[usize](written), null
    }

    system_file_size :: fn(file: File) -> (size : u64, error : OsError?) {
        size : i64 = 0
        if GetFileSizeEx(cast[rawptr](file.handle), &size) == 0 {
            return 0, last_error()
        }
        return cast[u64](size), null
    }

    system_delete_file :: fn(path: string) -> OsError? {
        units, path_error :: wide_path(path)
        if path_error != null {
            return path_error
        }
        defer free_wide(units)
        if DeleteFileW(cast[rawptr](units.data)) == 0 {
            return last_error()
        }
        return null
    }

    system_rename :: fn(from: string, to: string) -> OsError? {
        source, source_error :: wide_path(from)
        if source_error != null {
            return source_error
        }
        defer free_wide(source)
        target, target_error :: wide_path(to)
        if target_error != null {
            return target_error
        }
        defer free_wide(target)
        if MoveFileExW(cast[rawptr](source.data), cast[rawptr](target.data), MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED) == 0 {
            return last_error()
        }
        return null
    }

    system_path_kind :: fn(path: string) -> PathKind {
        units, path_error :: wide_path(path)
        if path_error != null {
            return .NOTHING
        }
        defer free_wide(units)
        attributes :: GetFileAttributesW(cast[rawptr](units.data))
        if attributes == INVALID_FILE_ATTRIBUTES {
            return .NOTHING
        }
        if attributes & FILE_ATTRIBUTE_DIRECTORY != 0 {
            return .DIRECTORY
        }
        return .FILE
    }

    system_make_directory :: fn(path: string) -> OsError? {
        units, path_error :: wide_path(path)
        if path_error != null {
            return path_error
        }
        defer free_wide(units)
        if CreateDirectoryW(cast[rawptr](units.data), null) == 0 {
            return last_error()
        }
        return null
    }

    system_remove_directory :: fn(path: string) -> OsError? {
        units, path_error :: wide_path(path)
        if path_error != null {
            return path_error
        }
        defer free_wide(units)
        if RemoveDirectoryW(cast[rawptr](units.data)) == 0 {
            return last_error()
        }
        return null
    }

    /*
     * WIN32_FIND_DATAW: 592 bytes, the attributes first and the name, 260 UTF-16 units with a
     * terminator, at 44.
     */
    FindData :: struct {
        words : u32[148],
    }
    FIND_NAME_OFFSET :: 44
    FIND_NAME_UNITS :: 260

    system_list_directory :: fn(path: string, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        // Everything in it: path\*
        units, path_error :: wide_path(path)
        if path_error != null {
            return path_error
        }
        defer free_wide(units)
        pattern, pattern_error :: runtime.new_array(u16, units.count + 2, context.allocator)
        if pattern_error != null || pattern.count < 3 {
            return OsError.OutOfMemory
        }
        defer free_wide(pattern)
        // units ends with its terminator, which the separator goes in place of
        length :: units.count - 1
        intrinsics.mem_copy_non_overlapping(cast[mut rawptr](pattern.data), cast[rawptr](units.data), length * 2)
        position := length
        if length > 0 && (units[length - 1] == cast[u16]('\\') || units[length - 1] == cast[u16]('/')) {
            position -= 1
        }
        if position + 2 < pattern.count {
            pattern[position] = cast[u16]('\\')
            pattern[position + 1] = cast[u16]('*')
            pattern[position + 2] = 0
        }
        data : FindData
        search :: FindFirstFileW(cast[rawptr](pattern.data), cast[rawptr](&data))
        if cast[u64](search) == INVALID_HANDLE {
            code :: GetLastError()
            // FILE_NOT_FOUND: an empty folder (a drive's root has no . or ..)
            if code == 2 {
                return null
            }
            return error_of(code)
        }
        defer FindClose(search)
        loop {
            name_start :: cast[rawptr](&data) + FIND_NAME_OFFSET
            name_units : usize = 0
            loop {
                if name_units >= FIND_NAME_UNITS || cast[ptr[u16]](name_start + name_units * 2)^ == 0 {
                    break
                }
                name_units += 1
            }
            first :: cast[ptr[u16]](name_start)^
            second :: cast[ptr[u16]](name_start + 2)^
            dot :: cast[u16]('.')
            is_dots :: (name_units == 1 && first == dot) || (name_units == 2 && first == dot && second == dot)
            if !is_dots {
                name, error :: narrow(name_start, name_units, allocator)
                if error != null {
                    return error
                }
                is_folder :: data.words[0] & FILE_ATTRIBUTE_DIRECTORY != 0
                runtime.array_add(entries, DirectoryEntry.{name = name, is_directory = is_folder})
            }
            if FindNextFileW(search, cast[rawptr](&data)) == 0 {
                break
            }
        }
        return null
    }

    system_current_directory :: fn(allocator: runtime.Allocator) -> (path #unrestricted : string, error : OsError?) {
        loop {
            // The size with its terminator, then the path, which may change in between
            needed :: GetCurrentDirectoryW(0, null)
            if needed == 0 {
                return "", last_error()
            }
            buffer, buffer_error :: runtime.new_array(u16, cast[usize](needed), context.allocator)
            if buffer_error != null {
                return "", OsError.OutOfMemory
            }
            length :: GetCurrentDirectoryW(needed, cast[rawptr](buffer.data))
            if length > 0 && length < needed {
                path, error :: narrow(cast[rawptr](buffer.data), cast[usize](length), allocator)
                free_wide(buffer)
                return path, error
            }
            free_wide(buffer)
            if length == 0 {
                return "", last_error()
            }
        }
    }

    system_set_current_directory :: fn(path: string) -> OsError? {
        units, path_error :: wide_path(path)
        if path_error != null {
            return path_error
        }
        defer free_wide(units)
        if SetCurrentDirectoryW(cast[rawptr](units.data)) == 0 {
            return last_error()
        }
        return null
    }
    /*
     * Directories, and paths beneath them (files.hsc): opened relative to the directory's handle with ntdll's
     * NtCreateFile, its ObjectAttributes' root, so they reach the directory wherever it's moved to; a path's '/' are
     * '\' to it. Listing reads the open directory with GetFileInformationByHandleEx.
     */
    NTDLL :: #library("ntdll")

    NtCreateFile #foreign(NTDLL) : fn(handle: ptr[mut rawptr], access: u32, attributes: rawptr, status: rawptr, size: rawptr, file_attributes: u32,
        share: u32, disposition: u32, options: u32, extended: rawptr, extended_length: u32) -> i32 : ---
    NtQueryAttributesFile #foreign(NTDLL) : fn(attributes: rawptr, information: rawptr) -> i32 : ---
    NtSetInformationFile #foreign(NTDLL) : fn(handle: rawptr, status: rawptr, information: rawptr, length: u32, class: u32) -> i32 : ---
    GetFileInformationByHandleEx #foreign(KERNEL32) : fn(handle: rawptr, class: u32, buffer: rawptr, size: u32) -> i32 : ---

    // UNICODE_STRING: its length and room in bytes, without a terminator, and its units.
    UnicodeString :: struct #scoped {
        length : u16,
        maximum : u16,
        padding : u32,
        buffer : rawptr,
    }

    // OBJECT_ATTRIBUTES: the name, relative to root.
    ObjectAttributes :: struct #scoped {
        length : u32,
        padding : u32,
        root : rawptr,
        name : rawptr,
        attributes : u32,
        padding_after : u32,
        security : rawptr,
        quality : rawptr,
    }

    // IO_STATUS_BLOCK
    IoStatus :: struct {
        status : u64,
        information : u64,
    }

    OBJ_CASE_INSENSITIVE : u32 : 0x40
    SYNCHRONIZE : u32 : 0x00100000
    DELETE : u32 : 0x00010000
    FILE_LIST_DIRECTORY : u32 : 0x0001
    FILE_APPEND_DATA : u32 : 0x0004
    FILE_TRAVERSE : u32 : 0x0020
    FILE_READ_ATTRIBUTES : u32 : 0x0080
    // NtCreateFile's dispositions
    FILE_OPEN : u32 : 1
    FILE_CREATE : u32 : 2
    FILE_OPEN_IF : u32 : 3
    FILE_OVERWRITE_IF : u32 : 5
    // and its options
    FILE_DIRECTORY_FILE : u32 : 0x0001
    FILE_SYNCHRONOUS_IO_NONALERT : u32 : 0x0020
    FILE_NON_DIRECTORY_FILE : u32 : 0x0040
    FILE_FLAG_BACKUP_SEMANTICS : u32 : 0x02000000
    // NtSetInformationFile's classes, and GetFileInformationByHandleEx's
    FILE_RENAME_INFORMATION : u32 : 10
    FILE_DISPOSITION_INFORMATION : u32 : 13
    FILE_FULL_DIRECTORY_INFO : u32 : 14
    FILE_FULL_DIRECTORY_RESTART_INFO : u32 : 15
    ERROR_NO_MORE_FILES : u32 : 18
    // FILE_FULL_DIR_INFO: the next record's offset first, then the attributes, the name's bytes and the name
    DIRECTORY_INFO_ATTRIBUTES :: 56
    DIRECTORY_INFO_NAME_BYTES :: 60
    DIRECTORY_INFO_NAME :: 68
    LISTING_BYTES :: 65536
    DIRECTORY_ACCESS :: FILE_LIST_DIRECTORY | FILE_TRAVERSE | FILE_READ_ATTRIBUTES | SYNCHRONIZE

    // The OsError for an NTSTATUS that failed.
    status_error :: fn(status: i32) -> OsError {
        code :: cast[u32](status)
        // NO_SUCH_FILE, OBJECT_NAME_NOT_FOUND, OBJECT_PATH_NOT_FOUND
        if code == 0xc000000f || code == 0xc0000034 || code == 0xc000003a {
            return .NotFound
        }
        if code == 0xc0000035 {
            return .AlreadyExists
        }
        // ACCESS_DENIED, SHARING_VIOLATION, MEDIA_WRITE_PROTECTED, CANNOT_DELETE
        if code == 0xc0000022 || code == 0xc0000043 || code == 0xc00000a2 || code == 0xc0000121 {
            return .AccessDenied
        }
        if code == 0xc0000103 {
            return .NotADirectory
        }
        if code == 0xc00000ba {
            return .IsADirectory
        }
        if code == 0xc0000101 {
            return .DirectoryNotEmpty
        }
        // INVALID_PARAMETER, OBJECT_NAME_INVALID, OBJECT_PATH_SYNTAX_BAD
        if code == 0xc000000d || code == 0xc0000033 || code == 0xc000003b {
            return .InvalidPath
        }
        // NO_MEMORY, INSUFFICIENT_RESOURCES
        if code == 0xc0000017 || code == 0xc000009a {
            return .OutOfMemory
        }
        return .Other
    }

    // A path beneath a directory as NT wants it: UTF-16, '/' as '\', from the context's allocator.
    relative_name :: fn(path: string) -> (units : u16[], error : OsError?) {
        units, error :: wide_path(path)
        if error != null {
            return units, error
        }
        for &unit in view_of(cast[ptr[mut u16]](units.data), units.count) {
            if unit^ == cast[u16]('/') {
                unit^ = cast[u16]('\\')
            }
        }
        return units, null
    }

    // NtCreateFile of path relative to root: the handle, or the error.
    open_relative :: fn(root: rawptr, path: string, access: u32, disposition: u32, options: u32) -> (handle : rawptr, error : OsError?) {
        units, path_error :: relative_name(path)
        if path_error != null {
            return null, path_error
        }
        defer free_wide(units)
        // Its bytes, without the terminator
        bytes :: (units.count - 1) * 2
        if bytes > 0xfffe {
            return null, OsError.InvalidPath
        }
        name := UnicodeString.{length = cast[u16](bytes), maximum = cast[u16](bytes), buffer = cast[rawptr](units.data)}
        attributes := ObjectAttributes.{length = cast[u32](size_of(ObjectAttributes)), root = root, name = cast[rawptr](&name),
            attributes = OBJ_CASE_INSENSITIVE}
        io : IoStatus
        handle : rawptr = null
        status :: NtCreateFile(&handle, access | SYNCHRONIZE, cast[rawptr](&attributes), cast[rawptr](&io), null, FILE_ATTRIBUTE_NORMAL,
            FILE_SHARE_ALL, disposition, options | FILE_SYNCHRONOUS_IO_NONALERT, null, 0)
        if status < 0 {
            return null, status_error(status)
        }
        return handle, null
    }

    system_open_in :: fn(directory: Directory, path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        access := GENERIC_READ
        disposition := FILE_OPEN
        if mode == .WRITE {
            access = GENERIC_WRITE
            disposition = FILE_OVERWRITE_IF
        }
        else if mode == .APPEND {
            // Appending only: every write goes at the end
            access = FILE_APPEND_DATA | FILE_READ_ATTRIBUTES
            disposition = FILE_OPEN_IF
        }
        else if mode == .READ_WRITE {
            access = GENERIC_READ | GENERIC_WRITE
        }
        handle, error :: open_relative(cast[rawptr](directory.handle), path, access, disposition, FILE_NON_DIRECTORY_FILE)
        if error != null {
            return File.{0}, error
        }
        return File.{cast[u64](handle)}, null
    }

    system_open_directory :: fn(path: string) -> (directory : Directory, error : OsError?) {
        if system_path_kind(path) == .FILE {
            return Directory.{0}, OsError.NotADirectory
        }
        units, path_error :: wide_path(path)
        if path_error != null {
            return Directory.{0}, path_error
        }
        defer free_wide(units)
        handle :: CreateFileW(cast[rawptr](units.data), DIRECTORY_ACCESS, FILE_SHARE_ALL, null, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, null)
        if cast[u64](handle) == INVALID_HANDLE {
            return Directory.{0}, last_error()
        }
        return Directory.{cast[u64](handle)}, null
    }

    system_working_directory :: fn() -> (directory : Directory, error : OsError?) {
        return system_open_directory(".")
    }

    system_open_directory_in :: fn(directory: Directory, path: string) -> (opened : Directory, error : OsError?) {
        handle, error :: open_relative(cast[rawptr](directory.handle), path, DIRECTORY_ACCESS, FILE_OPEN, FILE_DIRECTORY_FILE)
        if error != null {
            return Directory.{0}, error
        }
        return Directory.{cast[u64](handle)}, null
    }

    system_close_directory :: fn(directory: Directory) {
        CloseHandle(cast[rawptr](directory.handle))
    }

    system_make_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        handle, error :: open_relative(cast[rawptr](directory.handle), path, FILE_LIST_DIRECTORY, FILE_CREATE, FILE_DIRECTORY_FILE)
        if error != null {
            return error
        }
        CloseHandle(handle)
        return null
    }

    // What's at path, a file or a directory as options says, deleted: marked to go, and gone once it's closed.
    delete_relative :: fn(directory: Directory, path: string, options: u32) -> OsError? {
        handle, error :: open_relative(cast[rawptr](directory.handle), path, DELETE, FILE_OPEN, options)
        if error != null {
            return error
        }
        defer CloseHandle(handle)
        // FILE_DISPOSITION_INFORMATION: DeleteFile, true
        disposition : u8[8]
        disposition[0] = 1
        io : IoStatus
        status :: NtSetInformationFile(handle, cast[rawptr](&io), cast[rawptr](&disposition[0]), 1, FILE_DISPOSITION_INFORMATION)
        if status < 0 {
            return status_error(status)
        }
        return null
    }

    system_delete_file_in :: fn(directory: Directory, path: string) -> OsError? {
        return delete_relative(directory, path, FILE_NON_DIRECTORY_FILE)
    }

    system_remove_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        return delete_relative(directory, path, FILE_DIRECTORY_FILE)
    }

    /*
     * from opened for deleting, then given to as its new name relative to the directory, replacing a file there:
     * FILE_RENAME_INFORMATION's ReplaceIfExists, padded, its root at 8, the name's bytes at 16 and the name at 20.
     */
    system_rename_in :: fn(directory: Directory, from: string, to: string) -> OsError? {
        handle, error :: open_relative(cast[rawptr](directory.handle), from, DELETE, FILE_OPEN, 0)
        if error != null {
            return error
        }
        defer CloseHandle(handle)
        units, path_error :: relative_name(to)
        if path_error != null {
            return path_error
        }
        defer free_wide(units)
        bytes :: (units.count - 1) * 2
        information, allocation_error :: runtime.new_array(u8, 20 + bytes, context.allocator)
        if allocation_error != null || information.count < 20 + bytes {
            return OsError.OutOfMemory
        }
        defer runtime.free_array(information, context.allocator)
        cast[ptr[mut u8]](information.data)^ = 1
        cast[ptr[mut u64]](cast[rawptr](information.data) + 8)^ = directory.handle
        cast[ptr[mut u32]](cast[rawptr](information.data) + 16)^ = cast[u32](bytes)
        intrinsics.mem_copy_non_overlapping(cast[mut rawptr](information.data) + 20, cast[rawptr](units.data), bytes)
        io : IoStatus
        status :: NtSetInformationFile(handle, cast[rawptr](&io), cast[rawptr](information.data), cast[u32](information.count), FILE_RENAME_INFORMATION)
        if status < 0 {
            return status_error(status)
        }
        return null
    }

    // FILE_BASIC_INFORMATION: four times, then the attributes at 32.
    system_path_kind_in :: fn(directory: Directory, path: string) -> PathKind {
        units, path_error :: relative_name(path)
        if path_error != null {
            return .NOTHING
        }
        defer free_wide(units)
        bytes :: (units.count - 1) * 2
        name := UnicodeString.{length = cast[u16](bytes), maximum = cast[u16](bytes), buffer = cast[rawptr](units.data)}
        attributes := ObjectAttributes.{length = cast[u32](size_of(ObjectAttributes)), root = cast[rawptr](directory.handle),
            name = cast[rawptr](&name), attributes = OBJ_CASE_INSENSITIVE}
        basic : u64[5]
        if NtQueryAttributesFile(cast[rawptr](&attributes), cast[rawptr](&basic[0])) < 0 {
            return .NOTHING
        }
        if cast[u32](basic[4] & 0xffffffff) & FILE_ATTRIBUTE_DIRECTORY != 0 {
            return .DIRECTORY
        }
        return .FILE
    }

    system_list_directory_in :: fn(directory: Directory, path: string, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        // A handle of its own to list through, even for the directory itself (an empty name, relative to it), so it lists from the start
        handle, error :: open_relative(cast[rawptr](directory.handle), path, DIRECTORY_ACCESS, FILE_OPEN,
            FILE_DIRECTORY_FILE)
        if error != null {
            return error
        }
        defer CloseHandle(handle)
        records, allocation_error :: runtime.new_array(u64, LISTING_BYTES / 8, context.allocator)
        if allocation_error != null || records.count == 0 {
            return OsError.OutOfMemory
        }
        defer runtime.free_array(records, context.allocator)
        start :: cast[rawptr](records.data)
        class := FILE_FULL_DIRECTORY_RESTART_INFO
        loop {
            if GetFileInformationByHandleEx(handle, class, start, cast[u32](LISTING_BYTES)) == 0 {
                code :: GetLastError()
                if code == ERROR_NO_MORE_FILES {
                    return null
                }
                return error_of(code)
            }
            class = FILE_FULL_DIRECTORY_INFO
            offset : usize = 0
            loop {
                record :: start + offset
                name_bytes :: cast[usize](cast[ptr[u32]](record + DIRECTORY_INFO_NAME_BYTES)^)
                name_start :: record + DIRECTORY_INFO_NAME
                units :: name_bytes / 2
                first :: if units > 0 { cast[ptr[u16]](name_start)^ } else { cast[u16](0) }
                second :: if units > 1 { cast[ptr[u16]](name_start + 2)^ } else { cast[u16](0) }
                dot :: cast[u16]('.')
                if !((units == 1 && first == dot) || (units == 2 && first == dot && second == dot)) {
                    name, name_error :: narrow(name_start, units, allocator)
                    if name_error != null {
                        return name_error
                    }
                    is_folder :: cast[ptr[u32]](record + DIRECTORY_INFO_ATTRIBUTES)^ & FILE_ATTRIBUTE_DIRECTORY != 0
                    runtime.array_add(entries, DirectoryEntry.{name = name, is_directory = is_folder})
                }
                next :: cast[usize](cast[ptr[u32]](record)^)
                if next == 0 {
                    break
                }
                offset += next
            }
        }
    }
}
