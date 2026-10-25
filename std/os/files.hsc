package os

import intrinsics from "base"
import runtime from "base"

/*
 * What went wrong in a call to the operating system. Functions that give back something give a
 * Result, and those that don't give an OsError?, null when it worked:
 *
 *     match os.open("notes.txt", .READ) {
 *         case Ok(file) => use(file)
 *         case Error(error) => report(error)
 *     }
 *     if os.delete_file("old.txt") != null { ... }
 */
OsError :: enum {
    // Nothing is at the path, or a folder on the way to it is missing
    NotFound,
    // The system doesn't allow it, like writing a read-only file
    AccessDenied,
    // Something is already at the path
    AlreadyExists,
    // Part of the path, or the path itself, should be a folder and isn't
    NotADirectory,
    // The path is a folder, where a file was needed
    IsADirectory,
    // Removing a folder that still has something in it
    DirectoryNotEmpty,
    // The path can't be used: it's too long, or has a character the system doesn't allow
    InvalidPath,
    OutOfMemory,
    // The target has no file system, like OS == .None
    Unsupported,
    // Anything else the system reported
    Other,
}

/*
 * The process's command-line arguments, the program's name first, as UTF-8. They last as long as
 * the process, so there's nothing to free (runtime.process_arguments):
 *
 *     for argument in os.arguments()[1..] { ... }
 */
arguments :: fn() -> string[] {
    return runtime.process_arguments()
}

/*
 * The value of the environment variable called name, in a new string from allocator, which
 * strings.free_string gives back. NotFound if it isn't set.
 */
get_environment :: fn(name: string, allocator := context.allocator) -> Result[string, OsError] #unrestricted {
    value, error :: system_get_environment(name, allocator)
    return as_result(value, error)
}

// What a system_ function gave, as a Result.
as_result :: fn[T](value: T, error: OsError?) -> Result[T, OsError] {
    match error {
        case Some(failure) => return .Error(failure)
        case None => return .Ok(value)
    }
}

// An open file, from open, which close closes. A handle the system gave, so it can be kept anywhere.
File :: struct #unrestricted {
    handle : u64,
}

OpenMode :: enum {
    // Reading a file that's there
    READ,
    // Writing a new file, or replacing what's in one that's there
    WRITE,
    // Writing at the end, making the file if it isn't there
    APPEND,
    // Reading and writing a file that's there, from the start
    READ_WRITE,
}

// Opens the file at path. Paths are UTF-8, relative to the current directory unless they're absolute.
open :: fn(path: string, mode: OpenMode) -> Result[File, OsError] {
    file, error :: system_open(path, mode)
    return as_result(file, error)
}

close :: fn(file: File) {
    system_close(file)
}

// Reads into buffer, giving back how many bytes it read: fewer than it holds near the end, and 0 at the end.
read :: fn(file: File, buffer: mut u8[]) -> Result[usize, OsError] {
    count, error :: system_read(file, buffer)
    return as_result(count, error)
}

// Writes all of bytes, a write at a time until they're all written or one fails.
write :: fn(file: File, bytes: string) -> OsError? {
    done : usize = 0
    loop {
        if done >= bytes.count {
            break
        }
        written, error :: system_write(file, cast[rawptr](bytes.data) + done, bytes.count - done)
        if error != null {
            return error
        }
        if written == 0 {
            return OsError.Other
        }
        done += written
    }
    return null
}

// How many bytes the file holds.
file_size :: fn(file: File) -> Result[u64, OsError] {
    size, error :: system_file_size(file)
    return as_result(size, error)
}

/*
 * Everything in the file at path, in a new string from allocator, which strings.free_string gives
 * back. Read until the end, so it works for files whose size isn't known ahead, like pipes.
 */
read_entire_file :: fn(path: string, allocator := context.allocator) -> Result[string, OsError] #unrestricted {
    file, open_error :: system_open(path, .READ)
    match open_error {
        case Some(failure) => return .Error(failure)
        case None => {}
    }
    defer close(file)
    return read_all(file, allocator)
}

// Everything in an open file from where it's read, in a new string from allocator: read_entire_file's reading.
read_all :: fn(file: File, allocator: runtime.Allocator) -> Result[string, OsError] #unrestricted {
    size, size_error :: system_file_size(file)
    capacity : usize = 4096
    if size_error == null && size > 0 {
        capacity = cast[usize](size) + 1
    }
    bytes : mut u8[]
    count : usize = 0
    loop {
        if count == bytes.count {
            // Full: room for more, twice as big after the first time
            next_capacity := capacity
            if bytes.count > 0 {
                next_capacity = bytes.count * 2
            }
            larger, allocation_error :: runtime.new_array(u8, next_capacity, allocator)
            if allocation_error != null {
                runtime.free_array(bytes, allocator)
                return .Error(.OutOfMemory)
            }
            if count > 0 {
                intrinsics.mem_copy_non_overlapping(cast[mut rawptr](larger.data), cast[rawptr](bytes.data), count)
            }
            runtime.free_array(bytes, allocator)
            bytes = larger
        }
        if count > bytes.count {
            break
        }
        read_count, read_error :: system_read(file, bytes[count..<bytes.count])
        match read_error {
            case Some(failure) => {
                runtime.free_array(bytes, allocator)
                return .Error(failure)
            }
            case None => {}
        }
        if read_count == 0 {
            break
        }
        count += read_count
    }
    if count == 0 || count > bytes.count {
        runtime.free_array(bytes, allocator)
        return .Ok("")
    }
    // What was read, with the spare room at the end given back
    contents, allocation_error :: runtime.new_array(u8, count, allocator)
    if allocation_error != null || contents.count == 0 {
        runtime.free_array(bytes, allocator)
        return .Error(.OutOfMemory)
    }
    intrinsics.mem_copy_non_overlapping(cast[mut rawptr](contents.data), cast[rawptr](bytes.data), count)
    runtime.free_array(bytes, allocator)
    return .Ok(string_of(&contents[0], contents.count))
}

// Replaces what's in the file at path with contents, making it if it isn't there.
write_entire_file :: fn(path: string, contents: string) -> OsError? {
    file, open_error :: system_open(path, .WRITE)
    if open_error != null {
        return open_error
    }
    error :: write(file, contents)
    close(file)
    return error
}

delete_file :: fn(path: string) -> OsError? {
    return system_delete_file(path)
}

// Moves what's at from to to, replacing a file that's there.
rename :: fn(from: string, to: string) -> OsError? {
    return system_rename(from, to)
}

PathKind :: enum {
    NOTHING,
    FILE,
    DIRECTORY,
}

// What's at path: a file, a folder, or nothing (including when it can't be looked at).
path_kind :: fn(path: string) -> PathKind {
    return system_path_kind(path)
}

exists :: fn(path: string) -> bool {
    return path_kind(path) != .NOTHING
}

is_directory :: fn(path: string) -> bool {
    return path_kind(path) == .DIRECTORY
}

// Makes a folder at path. Its parent must be there already.
make_directory :: fn(path: string) -> OsError? {
    return system_make_directory(path)
}

// Removes the folder at path, which must be empty.
remove_directory :: fn(path: string) -> OsError? {
    return system_remove_directory(path)
}

// Something in a folder: its name, without the folder's path, and whether it's a folder itself.
DirectoryEntry :: struct {
    name : string,
    is_directory : bool,
}

/*
 * What's in the folder at path, apart from . and .., in the order the system gives them, with
 * the names and the array from allocator, which free_directory_listing gives back:
 *
 *     match os.list_directory("assets") {
 *         case Ok(entries) => {
 *             for entry in entries { ... }
 *             os.free_directory_listing(entries)
 *         }
 *         case Error(error) => report(error)
 *     }
 */
list_directory :: fn(path: string, allocator := context.allocator) -> Result[DirectoryEntry[..], OsError] #unrestricted {
    listing : DirectoryEntry[..]
    push_context listing_context (allocator = allocator) {
        error :: system_list_directory(path, &listing, allocator)
        match error {
            case Some(failure) => {
                free_directory_listing(listing, allocator)
                return .Error(failure)
            }
            case None => {}
        }
    }
    return .Ok(listing)
}

// Gives back a listing from list_directory: its names, then the array.
free_directory_listing :: fn(entries: DirectoryEntry[..], allocator := context.allocator, location := #caller_location) {
    for entry in entries {
        if entry.name.count > 0 {
            runtime.free_array(bit_cast[u8[]](entry.name), allocator)
        }
    }
    // The array's own block, to the allocator it took (runtime.array_free, for an array given by value)
    raw :: bit_cast[runtime.ResizableArray](entries)
    if raw.capacity > 0 {
        raw.allocator.function(raw.allocator.data, 0, align_of(DirectoryEntry), raw.data, raw.capacity * size_of(DirectoryEntry), location)
    }
}

// The current directory, as an absolute path in a new string from allocator, which strings.free_string gives back.
current_directory :: fn(allocator := context.allocator) -> Result[string, OsError] #unrestricted {
    path, error :: system_current_directory(allocator)
    return as_result(path, error)
}

// Makes path the current directory, which relative paths start from, for the whole process.
set_current_directory :: fn(path: string) -> OsError? {
    return system_set_current_directory(path)
}

// Directories, and paths beneath them

/*
 * An open directory, from open_directory, working_directory or open_directory_in, which close_directory closes. The
 * _in functions take one, and a path beneath it: relative, its components separated by '/', none of them empty, "."
 * or "..", so nothing it names is above the directory (on Windows, '\\' and ':' aren't allowed either). They open
 * relative to the directory itself, not to its path, so they reach it wherever it's moved to: through openat and its
 * kin on Linux, NtCreateFile with the directory as the root on Windows, and the directory's own connection on SlopOS,
 * which has no paths but these (the SlopOS repository's decisions 0046, 0087):
 *
 *     assets :: os.open_directory("assets") or_return
 *     defer os.close_directory(assets)
 *     text :: os.read_entire_file_in(assets, "fonts/readme.txt") or_return
 *
 * Symbolic links within the directory are followed, so on Linux and Windows one can lead outside it.
 */
Directory :: struct #unrestricted {
    handle : u64,
}

// Backslashes and colons separate a path's parts on Windows, and only there
SEPARATORS_ON_WINDOWS :: OS == .Windows

// Whether a path is one the _in functions take: beneath the directory it's given with.
is_beneath :: fn(path: string) -> bool {
    if path.count == 0 {
        return false
    }
    start : usize = 0
    for i in 0..<path.count + 1 {
        if i < path.count {
            character :: path[i]
            if character == cast[char](0) || (SEPARATORS_ON_WINDOWS && (character == '\\' || character == ':')) {
                return false
            }
            if character != '/' {
                continue
            }
        }
        component :: string_of(cast[ptr[u8]](cast[u64](path.data) + cast[u64](start)), i - start)
        if component.count == 0 || component == "." || component == ".." {
            return false
        }
        start = i + 1
    }
    return true
}

// Opens the directory at path, as open opens a file.
open_directory :: fn(path: string) -> Result[Directory, OsError] {
    directory, error :: system_open_directory(path)
    return as_result(directory, error)
}

/*
 * The directory relative paths start from, open: the current directory on Linux and Windows, and on SlopOS the
 * directory the program was given as its "working_directory" grant, or NotFound without one.
 */
working_directory :: fn() -> Result[Directory, OsError] {
    directory, error :: system_working_directory()
    return as_result(directory, error)
}

// The directory at path beneath directory, open.
open_directory_in :: fn(directory: Directory, path: string) -> Result[Directory, OsError] {
    if !is_beneath(path) {
        return .Error(.InvalidPath)
    }
    opened, error :: system_open_directory_in(directory, path)
    return as_result(opened, error)
}

close_directory :: fn(directory: Directory) {
    system_close_directory(directory)
}

// Opens the file at path beneath directory, as open does.
open_in :: fn(directory: Directory, path: string, mode: OpenMode) -> Result[File, OsError] {
    if !is_beneath(path) {
        return .Error(.InvalidPath)
    }
    file, error :: system_open_in(directory, path, mode)
    return as_result(file, error)
}

// Everything in the file at path beneath directory, as read_entire_file reads it.
read_entire_file_in :: fn(directory: Directory, path: string, allocator := context.allocator) -> Result[string, OsError] #unrestricted {
    file :: open_in(directory, path, .READ)?
    defer close(file)
    return read_all(file, allocator)
}

// Replaces what's in the file at path beneath directory with contents, making it if it isn't there.
write_entire_file_in :: fn(directory: Directory, path: string, contents: string) -> OsError? {
    if !is_beneath(path) {
        return OsError.InvalidPath
    }
    file, open_error :: system_open_in(directory, path, .WRITE)
    if open_error != null {
        return open_error
    }
    error :: write(file, contents)
    close(file)
    return error
}

delete_file_in :: fn(directory: Directory, path: string) -> OsError? {
    if !is_beneath(path) {
        return OsError.InvalidPath
    }
    return system_delete_file_in(directory, path)
}

// Moves what's at from to to, both beneath directory, replacing a file that's there.
rename_in :: fn(directory: Directory, from: string, to: string) -> OsError? {
    if !is_beneath(from) || !is_beneath(to) {
        return OsError.InvalidPath
    }
    return system_rename_in(directory, from, to)
}

// What's at path beneath directory: a file, a folder, or nothing.
path_kind_in :: fn(directory: Directory, path: string) -> PathKind {
    if !is_beneath(path) {
        return .NOTHING
    }
    return system_path_kind_in(directory, path)
}

// Makes a folder at path beneath directory. Its parent must be there already.
make_directory_in :: fn(directory: Directory, path: string) -> OsError? {
    if !is_beneath(path) {
        return OsError.InvalidPath
    }
    return system_make_directory_in(directory, path)
}

// Removes the folder at path beneath directory, which must be empty.
remove_directory_in :: fn(directory: Directory, path: string) -> OsError? {
    if !is_beneath(path) {
        return OsError.InvalidPath
    }
    return system_remove_directory_in(directory, path)
}

// What's in the folder at path beneath directory, or with "", in directory itself, as list_directory lists it.
list_directory_in :: fn(directory: Directory, path: string, allocator := context.allocator) -> Result[DirectoryEntry[..], OsError] #unrestricted {
    if path.count != 0 && !is_beneath(path) {
        return .Error(.InvalidPath)
    }
    listing : DirectoryEntry[..]
    push_context listing_context (allocator = allocator) {
        error :: system_list_directory_in(directory, path, &listing, allocator)
        match error {
            case Some(failure) => {
                free_directory_listing(listing, allocator)
                return .Error(failure)
            }
            case None => {}
        }
    }
    return .Ok(listing)
}

// bytes as a string in memory from allocator, or OutOfMemory: for names and values the system gave.
copy_string :: fn(bytes: string, allocator: runtime.Allocator) -> (copy #unrestricted : string, error : OsError?) {
    if bytes.count == 0 {
        return "", null
    }
    memory, error :: runtime.new_array(u8, bytes.count, allocator)
    if error != null || memory.count == 0 {
        return "", OsError.OutOfMemory
    }
    intrinsics.mem_copy_non_overlapping(cast[mut rawptr](memory.data), cast[rawptr](bytes.data), bytes.count)
    return string_of(&memory[0], memory.count), null
}
