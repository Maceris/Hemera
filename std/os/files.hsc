package os

import intrinsics from "base"
import runtime from "base"

/**
 * What went wrong in a call to the operating system.
 *
 * Functions that give back something give a Result, and those that don't give an OsError?, null when it worked:
 *
 *     match os.open("notes.txt", .READ) {
 *         case Ok(file) => use(file)
 *         case Error(error) => report(error)
 *     }
 *     if os.delete_file("old.txt") != null { ... }
 *
 * Each system's own errors are mapped onto these few, and what has no member of its own is Other, so those can't be
 * told apart.
 */
OsError :: enum {
    /** Nothing is at the path, or a folder on the way to it is missing; also an environment variable that isn't set. */
    NotFound,
    /** The system doesn't allow it, like writing a read-only file, or a grant that was revoked. */
    AccessDenied,
    /** Something is already at the path. */
    AlreadyExists,
    /** Part of the path, or the path itself, should be a folder and isn't. */
    NotADirectory,
    /** The path is a folder, where a file was needed. */
    IsADirectory,
    /** Removing a folder that still has something in it. */
    DirectoryNotEmpty,
    /**
     * The path can't be used: it's too long, has a character the system doesn't allow (a 0 byte anywhere), or, for
     * the _in functions, isn't beneath the directory (is_beneath).
     */
    InvalidPath,
    /** Memory for a result, or for a path's conversion for the system, couldn't be had. */
    OutOfMemory,
    /** A typed file isn't of the type asked for, or the file system keeps no types. */
    WrongType,
    /** The target has no file system, like OS == .None; every call there gives this. */
    Unsupported,
    /** Anything else the system reported, like a full volume or a device error. */
    Other,
}

/**
 * Get the process's command-line arguments, the program's name first.
 *
 * They come from runtime.process_arguments:
 *
 *     for argument in os.arguments()[1..] { ... }
 *
 * @return The arguments as UTF-8, the first being the program's name as it was started. They last as long as the
 *     process, so there's nothing to free, and they mustn't be freed.
 */
arguments :: fn() -> string[] {
    return runtime.process_arguments()
}

/**
 * Look up an environment variable's value.
 *
 * @param name The variable's name, matched exactly. An empty name is never found.
 * @param allocator Where the value's copy is allocated from.
 * @return The value, in a new string from allocator that the caller owns and gives back with strings.free_string. A
 *     variable that's set but empty gives "", which owns nothing.
 * @error NotFound The variable isn't set, or name is empty.
 * @error OutOfMemory The value's copy couldn't be allocated.
 * @error Unsupported The target has no environment, like OS == .None.
 */
get_environment :: fn(name: string, allocator := context.allocator) -> Result[string, OsError] #unrestricted {
    value, error :: system_get_environment(name, allocator)
    return as_result(value, error)
}

/**
 * Turn what a system_ function gave, a value and an optional error, into a Result.
 *
 * @tparam T The value's type.
 * @param value The value, used only when error is null.
 * @param error The error, or null if the call worked.
 * @return Ok with value when error is null; otherwise Error with error, and value is dropped, not freed.
 */
as_result :: fn[T](value: T, error: OsError?) -> Result[T, OsError] {
    match error {
        case Some(failure) => return .Error(failure)
        case None => return .Ok(value)
    }
}

/**
 * An open file, from open or open_in, which close closes.
 *
 * It's only a handle the system gave, not memory, so it can be copied and kept anywhere; every copy is the same open
 * file, closed once for all of them.
 */
File :: struct #unrestricted {
    /**
     * What the system knows it by: a file descriptor on Linux, a HANDLE on Windows, and on SlopOS the address of this
     * package's own record of its connection.
     */
    handle : u64,
}

/** How a file is opened: for reading, writing or both, and what happens to a file that's there or isn't. */
OpenMode :: enum {
    /** Reading a file that's there, from the start; a missing file is NotFound. */
    READ,
    /** Writing a new file, or emptying one that's there and writing it from the start. */
    WRITE,
    /** Writing at the end, making the file if it isn't there; every write goes to the end. */
    APPEND,
    /** Reading and writing a file that's there, from the start, without emptying it; a missing file is NotFound. */
    READ_WRITE,
}

/**
 * Open the file at path.
 *
 * @param path The file's path, UTF-8, relative to the current directory unless it's absolute. On SlopOS, which has
 *     no paths of its own, it has to be beneath the working directory (is_beneath), and is opened in that.
 * @param mode Whether it's read, written or both, and whether it's made or emptied (OpenMode).
 * @return The open file, which the caller owns and closes with close.
 * @error NotFound Nothing is at path, with a mode that doesn't make one, or a folder on the way is missing.
 * @error AccessDenied The system doesn't allow opening it in that mode.
 * @error IsADirectory The path is a folder.
 * @error NotADirectory A part of the path on the way is a file.
 * @error InvalidPath The path is too long or holds a 0 byte, or on SlopOS isn't beneath the working directory.
 * @error OutOfMemory The path's conversion for the system couldn't be allocated.
 * @error WrongType On SlopOS, what's at path is a typed file of another type.
 * @error Unsupported The target has no file system.
 * @error Other Anything else the system reported.
 */
open :: fn(path: string, mode: OpenMode) -> Result[File, OsError] {
    file, error :: system_open(path, mode)
    return as_result(file, error)
}

/**
 * Close a file, giving its handle back to the system.
 *
 * @param file The file, from open or open_in. It, and every copy of it, mustn't be used again: the system may give
 *     the same handle to the next file opened.
 */
close :: fn(file: File) {
    system_close(file)
}

/**
 * Read bytes from a file into a buffer, from where the last read or write ended.
 *
 * It's one read of the system's, so fewer bytes than the buffer holds can come back before the end, as from a pipe.
 *
 * @param file The file, opened for reading.
 * @param buffer Where the bytes go; at most its count are read.
 * @return How many bytes were read into the start of buffer: 0 at the file's end (or for an empty buffer), and
 *     otherwise from 1 to the buffer's count.
 * @error AccessDenied The file wasn't opened for reading.
 * @error IsADirectory The handle is a folder's.
 * @error Unsupported The target has no file system.
 * @error Other Anything else the system reported, like a device error or a handle that isn't open.
 */
read :: fn(file: File, buffer: mut u8[]) -> Result[usize, OsError] {
    count, error :: system_read(file, buffer)
    return as_result(count, error)
}

/**
 * Write all of bytes to a file, from where the last read or write ended (or at the end, for APPEND).
 *
 * The system's writes are repeated until every byte is written or one fails, so a failure can leave some of the bytes
 * written; how many isn't reported.
 *
 * @param file The file, opened for writing.
 * @param bytes What's written, as bytes; it needn't be UTF-8. Empty writes nothing and succeeds.
 * @return Null if every byte was written; otherwise why it stopped: the system's error, or Other when a write wrote
 *     nothing without one.
 */
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

/**
 * Find how many bytes a file holds.
 *
 * @param file An open file.
 * @return Its size in bytes: 0 for an empty file, and possibly 0 for a pipe or a device, whose size isn't known ahead.
 * @error AccessDenied The system doesn't allow asking.
 * @error Unsupported The target has no file system.
 * @error Other Anything else the system reported.
 */
file_size :: fn(file: File) -> Result[u64, OsError] {
    size, error :: system_file_size(file)
    return as_result(size, error)
}

/**
 * Read everything in the file at path.
 *
 * The file is read until its end, not to the size it gave, so it works for files whose size isn't known ahead, like
 * pipes. It's opened, read and closed here.
 *
 * @param path The file's path, as open takes it.
 * @param allocator Where the contents are allocated from.
 * @return The file's bytes, in a new string from allocator that the caller owns and gives back with
 *     strings.free_string; they needn't be UTF-8. An empty file gives "", which owns nothing.
 * @error NotFound Nothing is at path, or a folder on the way is missing.
 * @error AccessDenied The system doesn't allow reading it.
 * @error IsADirectory The path is a folder.
 * @error InvalidPath The path is too long or holds a 0 byte.
 * @error OutOfMemory The contents couldn't be allocated; nothing is left allocated.
 * @error Unsupported The target has no file system.
 * @error Other Anything else the system reported.
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

/**
 * Read everything left in an open file, from where it's read to its end: read_entire_file's reading.
 *
 * The buffer starts at the file's size and a byte, or 4096 bytes when the size isn't known, and doubles when it
 * fills; what's read is then copied into a string of exactly its length.
 *
 * @param file The file, opened for reading. It's left open, read to its end.
 * @param allocator Where the contents, and the buffer while reading, are allocated from.
 * @return What was read, in a new string from allocator that the caller owns and gives back with
 *     strings.free_string. Nothing left gives "", which owns nothing.
 * @error OutOfMemory The buffer or the contents couldn't be allocated; nothing is left allocated.
 * @error AccessDenied The file wasn't opened for reading.
 * @error IsADirectory The handle is a folder's.
 * @error Unsupported The target has no file system.
 * @error Other Anything else the system reported while reading.
 */
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

/**
 * Replace what's in the file at path with contents, making it if it isn't there.
 *
 * The file is emptied when it's opened, so a failure while writing leaves it holding only part of contents.
 *
 * @param path The file's path, as open takes it. Its folder has to be there already.
 * @param contents What the file holds afterwards, as bytes. Empty leaves an empty file.
 * @return Null if it worked; otherwise why not, as open or write gives it (NotFound when the folder is missing).
 */
write_entire_file :: fn(path: string, contents: string) -> OsError? {
    file, open_error :: system_open(path, .WRITE)
    if open_error != null {
        return open_error
    }
    error :: write(file, contents)
    close(file)
    return error
}

/**
 * Delete the file at path.
 *
 * @param path The file's path, as open takes it. A folder isn't deleted: remove_directory does that.
 * @return Null if it was deleted; otherwise why not: NotFound when nothing is there, AccessDenied when it isn't
 *     allowed, and the system's error for a folder (IsADirectory, or AccessDenied on some systems).
 */
delete_file :: fn(path: string) -> OsError? {
    return system_delete_file(path)
}

/**
 * Move a file or folder to another path, replacing a file that's at the new one.
 *
 * On Linux it has to stay on the same volume; on Windows a file may be copied to another volume and then deleted.
 *
 * @param from What's moved: its path, as open takes it.
 * @param to Where it goes: its new path, whose folder has to be there already.
 * @return Null if it was moved; otherwise why not: NotFound when nothing is at from, AccessDenied when it isn't
 *     allowed, and the system's other errors.
 */
rename :: fn(from: string, to: string) -> OsError? {
    return system_rename(from, to)
}

/** What's at a path, as path_kind tells it. */
PathKind :: enum {
    /** Nothing, or something that couldn't be looked at. */
    NOTHING,
    /** A file, or anything else that isn't a folder. */
    FILE,
    /** A folder. */
    DIRECTORY,
}

/**
 * Find what's at path.
 *
 * @param path The path, as open takes it.
 * @return FILE or DIRECTORY for what's there, and NOTHING both when nothing is and when it can't be looked at (a
 *     too-long path, one that isn't allowed, or a target without a file system), which aren't told apart.
 */
path_kind :: fn(path: string) -> PathKind {
    return system_path_kind(path)
}

/**
 * Find whether anything is at path, a file or a folder.
 *
 * @param path The path, as open takes it.
 * @return True if something is there; false if nothing is, or it can't be looked at (path_kind's NOTHING).
 */
exists :: fn(path: string) -> bool {
    return path_kind(path) != .NOTHING
}

/**
 * Find whether a folder is at path.
 *
 * @param path The path, as open takes it.
 * @return True if a folder is there; false for a file, nothing, or what can't be looked at.
 */
is_directory :: fn(path: string) -> bool {
    return path_kind(path) == .DIRECTORY
}

/**
 * Make a folder at path.
 *
 * Only the last folder is made; its parent has to be there already.
 *
 * @param path The new folder's path, as open takes it.
 * @return Null if it was made; otherwise why not: AlreadyExists when something is at path (even a folder), NotFound
 *     when its parent is missing, AccessDenied when it isn't allowed.
 */
make_directory :: fn(path: string) -> OsError? {
    return system_make_directory(path)
}

/**
 * Remove the folder at path, which has to be empty.
 *
 * @param path The folder's path, as open takes it.
 * @return Null if it was removed; otherwise why not: DirectoryNotEmpty when something is in it, NotFound when
 *     nothing is at path, NotADirectory when a file is.
 */
remove_directory :: fn(path: string) -> OsError? {
    return system_remove_directory(path)
}

/** Something in a folder, from list_directory or list_directory_in. */
DirectoryEntry :: struct {
    /**
     * Its name, without the folder's path, as UTF-8; never "." or "..". It's allocated with the listing, and
     * free_directory_listing gives it back.
     */
    name : string,
    /** Whether it's a folder itself. */
    is_directory : bool,
}

/**
 * List what's in the folder at path, apart from . and ..
 *
 *     match os.list_directory("assets") {
 *         case Ok(entries) => {
 *             for entry in entries { ... }
 *             os.free_directory_listing(entries)
 *         }
 *         case Error(error) => report(error)
 *     }
 *
 * @param path The folder's path, as open takes it.
 * @param allocator Where the names and the array are allocated from.
 * @return The entries, in the order the system gives them (not sorted), empty for an empty folder. The caller owns
 *     the names and the array, and gives them back with free_directory_listing and the same allocator.
 * @error NotFound Nothing is at path.
 * @error NotADirectory The path is a file.
 * @error AccessDenied The system doesn't allow listing it.
 * @error InvalidPath The path is too long or holds a 0 byte.
 * @error OutOfMemory A name or the array couldn't be allocated; what was allocated is given back.
 * @error Unsupported The target has no file system.
 * @error Other Anything else the system reported.
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

/**
 * Give back a listing from list_directory or list_directory_in: its names, then the array.
 *
 * @param entries The listing. It, and every name in it, mustn't be used afterwards. An empty listing is fine.
 * @param allocator The allocator the names were allocated from; the array goes back to the one it records itself.
 * @param location Where it's called from, given to the allocator for its reports.
 */
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

/**
 * Get the process's current directory, which relative paths start from.
 *
 * @param allocator Where the path is allocated from.
 * @return The current directory as an absolute UTF-8 path, in a new string from allocator that the caller owns and
 *     gives back with strings.free_string.
 * @error OutOfMemory The path couldn't be allocated.
 * @error NotFound The current directory was removed.
 * @error Unsupported The target has no current directory, like SlopOS, or no file system.
 * @error Other Anything else the system reported.
 */
current_directory :: fn(allocator := context.allocator) -> Result[string, OsError] #unrestricted {
    path, error :: system_current_directory(allocator)
    return as_result(path, error)
}

/**
 * Make path the current directory, which relative paths start from, for the whole process and every thread in it.
 *
 * @param path The folder's path, as open takes it; relative to the current directory unless it's absolute.
 * @return Null if it worked; otherwise why not: NotFound when nothing is at path, NotADirectory when a file is.
 */
set_current_directory :: fn(path: string) -> OsError? {
    return system_set_current_directory(path)
}

// Directories, and paths beneath them

/**
 * An open directory, from open_directory, working_directory or open_directory_in, which close_directory closes.
 *
 * The _in functions take one, and a path beneath it: relative, its components separated by '/', none of them empty,
 * "." or "..", so nothing it names is above the directory (on Windows, '\\' and ':' aren't allowed either). They open
 * relative to the directory itself, not to its path, so they reach it wherever it's moved to: through openat and its
 * kin on Linux, NtCreateFile with the directory as the root on Windows, and the directory's own connection on SlopOS,
 * which has no paths but these (the SlopOS repository's decisions 0046, 0087):
 *
 *     assets :: os.open_directory("assets") or_return
 *     defer os.close_directory(assets)
 *     text :: os.read_entire_file_in(assets, "fonts/readme.txt") or_return
 *
 * Symbolic links within the directory are followed, so on Linux and Windows one can lead outside it. Like File, it's
 * only a handle, so copies are the same open directory, closed once.
 */
Directory :: struct #unrestricted {
    /**
     * What the system knows it by: a file descriptor on Linux, a HANDLE on Windows, and on SlopOS the address of this
     * package's own record of its connection.
     */
    handle : u64,
}

/** Whether backslashes and colons separate a path's parts, so is_beneath refuses them: true on Windows only. */
SEPARATORS_ON_WINDOWS :: OS == .Windows

/**
 * Check whether a path is one the _in functions take: beneath the directory it's given with.
 *
 * Only the text is looked at, not what's there.
 *
 * @param path The path: relative, its components separated by '/'.
 * @return True if it isn't empty, has no 0 byte, and none of its components is empty, "." or ".." (so a leading or
 *     trailing '/', or "a//b", gives false); on Windows it mustn't hold '\\' or ':' either.
 */
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

/**
 * Open the directory at path, for the _in functions.
 *
 * @param path The directory's path, as open takes a file's.
 * @return The open directory, which the caller owns and closes with close_directory.
 * @error NotFound Nothing is at path.
 * @error NotADirectory The path is a file.
 * @error AccessDenied The system doesn't allow opening it.
 * @error InvalidPath The path is too long or holds a 0 byte, or on SlopOS isn't beneath the working directory.
 * @error OutOfMemory The path's conversion for the system couldn't be allocated.
 * @error Unsupported The target has no file system.
 * @error Other Anything else the system reported.
 */
open_directory :: fn(path: string) -> Result[Directory, OsError] {
    directory, error :: system_open_directory(path)
    return as_result(directory, error)
}

/**
 * Open the directory relative paths start from.
 *
 * That's the current directory on Linux and Windows, opened as it is now, and on SlopOS the directory the program was
 * given as its "working_directory" grant.
 *
 * @return The open directory, which the caller owns and closes with close_directory.
 * @error NotFound On SlopOS, the program was given no "working_directory" grant.
 * @error AccessDenied The system doesn't allow opening it.
 * @error OutOfMemory What opening it needed couldn't be allocated.
 * @error Unsupported The target has no file system.
 * @error Other Anything else the system reported, like a grant that isn't a directory.
 */
working_directory :: fn() -> Result[Directory, OsError] {
    directory, error :: system_working_directory()
    return as_result(directory, error)
}

/**
 * Open the directory at path beneath another.
 *
 * @param directory The open directory path starts from. It stays open, and the new one doesn't depend on it.
 * @param path The directory's path beneath it, as is_beneath takes it.
 * @return The open directory, which the caller owns and closes with close_directory.
 * @error InvalidPath The path isn't beneath directory (is_beneath), or is too long.
 * @error NotFound Nothing is at path.
 * @error NotADirectory The path is a file, or a part on the way is.
 * @error AccessDenied The system doesn't allow opening it.
 * @error OutOfMemory What opening it needed couldn't be allocated.
 * @error Unsupported The target has no file system.
 * @error Other Anything else the system reported.
 */
open_directory_in :: fn(directory: Directory, path: string) -> Result[Directory, OsError] {
    if !is_beneath(path) {
        return .Error(.InvalidPath)
    }
    opened, error :: system_open_directory_in(directory, path)
    return as_result(opened, error)
}

/**
 * Close an open directory, giving its handle back to the system.
 *
 * @param directory The directory, from open_directory, working_directory or open_directory_in. It, and every copy
 *     of it, mustn't be used again; files and directories opened in it stay open.
 */
close_directory :: fn(directory: Directory) {
    system_close_directory(directory)
}

/**
 * Open the file at path beneath directory, as open opens one.
 *
 * @param directory The open directory path starts from. It stays open, and the file doesn't depend on it.
 * @param path The file's path beneath it, as is_beneath takes it.
 * @param mode Whether it's read, written or both, and whether it's made or emptied (OpenMode).
 * @return The open file, which the caller owns and closes with close.
 * @error InvalidPath The path isn't beneath directory (is_beneath), or is too long.
 * @error NotFound Nothing is at path, with a mode that doesn't make one, or a folder on the way is missing.
 * @error AccessDenied The system doesn't allow opening it in that mode.
 * @error IsADirectory The path is a folder.
 * @error NotADirectory A part of the path on the way is a file.
 * @error OutOfMemory What opening it needed couldn't be allocated.
 * @error Unsupported The target has no file system.
 * @error Other Anything else the system reported.
 */
open_in :: fn(directory: Directory, path: string, mode: OpenMode) -> Result[File, OsError] {
    if !is_beneath(path) {
        return .Error(.InvalidPath)
    }
    file, error :: system_open_in(directory, path, mode)
    return as_result(file, error)
}

/**
 * Read everything in the file at path beneath directory, as read_entire_file reads it.
 *
 * @param directory The open directory path starts from; it stays open.
 * @param path The file's path beneath it, as is_beneath takes it.
 * @param allocator Where the contents are allocated from.
 * @return The file's bytes, in a new string from allocator that the caller owns and gives back with
 *     strings.free_string. An empty file gives "", which owns nothing.
 * @error InvalidPath The path isn't beneath directory (is_beneath), or is too long.
 * @error NotFound Nothing is at path, or a folder on the way is missing.
 * @error AccessDenied The system doesn't allow reading it.
 * @error IsADirectory The path is a folder.
 * @error OutOfMemory The contents couldn't be allocated; nothing is left allocated.
 * @error Unsupported The target has no file system.
 * @error Other Anything else the system reported.
 */
read_entire_file_in :: fn(directory: Directory, path: string, allocator := context.allocator) -> Result[string, OsError] #unrestricted {
    file :: open_in(directory, path, .READ)?
    defer close(file)
    return read_all(file, allocator)
}

/**
 * Replace what's in the file at path beneath directory with contents, making it if it isn't there.
 *
 * The file is emptied when it's opened, so a failure while writing leaves it holding only part of contents.
 *
 * @param directory The open directory path starts from; it stays open.
 * @param path The file's path beneath it, as is_beneath takes it. Its folder has to be there already.
 * @param contents What the file holds afterwards, as bytes. Empty leaves an empty file.
 * @return Null if it worked; otherwise why not: InvalidPath when path isn't beneath directory, or what open_in or
 *     write gives.
 */
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

/**
 * Delete the file at path beneath directory.
 *
 * @param directory The open directory path starts from; it stays open.
 * @param path The file's path beneath it, as is_beneath takes it. A folder isn't deleted: remove_directory_in does
 *     that.
 * @return Null if it was deleted; otherwise why not: InvalidPath when path isn't beneath directory, NotFound when
 *     nothing is there, AccessDenied when it isn't allowed, and the system's error for a folder.
 */
delete_file_in :: fn(directory: Directory, path: string) -> OsError? {
    if !is_beneath(path) {
        return OsError.InvalidPath
    }
    return system_delete_file_in(directory, path)
}

/**
 * Move a file or folder from one path beneath directory to another, replacing a file that's at the new one.
 *
 * @param directory The open directory both paths start from; it stays open.
 * @param from What's moved: its path beneath directory, as is_beneath takes it.
 * @param to Where it goes: its new path beneath directory, whose folder has to be there already.
 * @return Null if it was moved; otherwise why not: InvalidPath when either path isn't beneath directory, NotFound
 *     when nothing is at from, and the system's other errors.
 */
rename_in :: fn(directory: Directory, from: string, to: string) -> OsError? {
    if !is_beneath(from) || !is_beneath(to) {
        return OsError.InvalidPath
    }
    return system_rename_in(directory, from, to)
}

/**
 * Find what's at path beneath directory.
 *
 * @param directory The open directory path starts from; it stays open.
 * @param path The path beneath it, as is_beneath takes it.
 * @return FILE or DIRECTORY for what's there; NOTHING when nothing is, when it can't be looked at, or when path
 *     isn't beneath directory.
 */
path_kind_in :: fn(directory: Directory, path: string) -> PathKind {
    if !is_beneath(path) {
        return .NOTHING
    }
    return system_path_kind_in(directory, path)
}

/**
 * Make a folder at path beneath directory.
 *
 * Only the last folder is made; its parent has to be there already.
 *
 * @param directory The open directory path starts from; it stays open.
 * @param path The new folder's path beneath it, as is_beneath takes it.
 * @return Null if it was made; otherwise why not: InvalidPath when path isn't beneath directory, AlreadyExists when
 *     something is at path, NotFound when its parent is missing.
 */
make_directory_in :: fn(directory: Directory, path: string) -> OsError? {
    if !is_beneath(path) {
        return OsError.InvalidPath
    }
    return system_make_directory_in(directory, path)
}

/**
 * Remove the folder at path beneath directory, which has to be empty.
 *
 * @param directory The open directory path starts from; it stays open.
 * @param path The folder's path beneath it, as is_beneath takes it.
 * @return Null if it was removed; otherwise why not: InvalidPath when path isn't beneath directory,
 *     DirectoryNotEmpty when something is in it, NotFound when nothing is at path.
 */
remove_directory_in :: fn(directory: Directory, path: string) -> OsError? {
    if !is_beneath(path) {
        return OsError.InvalidPath
    }
    return system_remove_directory_in(directory, path)
}

/**
 * List what's in the folder at path beneath directory, as list_directory lists it.
 *
 * @param directory The open directory path starts from; it stays open.
 * @param path The folder's path beneath it, as is_beneath takes it, or "" for directory itself.
 * @param allocator Where the names and the array are allocated from.
 * @return The entries, in the order the system gives them, empty for an empty folder. The caller owns the names and
 *     the array, and gives them back with free_directory_listing and the same allocator.
 * @error InvalidPath The path isn't "" and isn't beneath directory (is_beneath), or is too long.
 * @error NotFound Nothing is at path.
 * @error NotADirectory The path is a file.
 * @error AccessDenied The system doesn't allow listing it.
 * @error OutOfMemory A name or the array couldn't be allocated; what was allocated is given back.
 * @error Unsupported The target has no file system.
 * @error Other Anything else the system reported.
 */
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

/**
 * Copy bytes into a new string from allocator: for names and values the system gave, whose memory it keeps.
 *
 * @param bytes What's copied; only read here.
 * @param allocator Where the copy is allocated from.
 * @return copy The copy, which the caller owns and gives back with strings.free_string; "", owning nothing, when
 *     bytes is empty or the allocation failed.
 * @return error OutOfMemory when the copy couldn't be allocated, or null.
 */
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
