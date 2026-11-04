package os

import intrinsics from "base"
import runtime from "base"

/*
 * Windows' side of std/os, through kernel32's wide (UTF-16) functions. Paths and names are
 * converted from UTF-8 into memory from the context's allocator for each call, with a terminator.
 */
#if OS == .Windows {
    /** The kernel32.dll library, where the Win32 functions here are. */
    KERNEL32 :: #library("kernel32")

    /**
     * Give the calling thread's last error code, which a failed Win32 call sets.
     *
     * @return The code, like 2 (ERROR_FILE_NOT_FOUND), which error_of translates; good only right after the call
     *     that failed.
     */
    GetLastError #foreign(KERNEL32) : fn() -> u32 : ---
    /**
     * Read an environment variable.
     *
     * @param name The variable's name, UTF-16 with a terminator; case doesn't matter.
     * @param buffer Where the value goes, UTF-16 with a terminator, or null to ask only its size.
     * @param size The size of buffer in UTF-16 units, the terminator included.
     * @return The value's length in units without the terminator, once it's in buffer; if it doesn't fit, the size
     *     needed with the terminator; 0 if it isn't set (ERROR_ENVVAR_NOT_FOUND), or is empty.
     */
    GetEnvironmentVariableW #foreign(KERNEL32) : fn(name: rawptr, buffer: rawptr, size: u32) -> u32 : ---
    /**
     * Open or make a file, or open a folder.
     *
     * @param name The path, UTF-16 with a terminator.
     * @param access What the handle may do, like GENERIC_READ.
     * @param share What others may do with it while it's open, like FILE_SHARE_ALL.
     * @param security Security attributes, or null for the defaults, with a handle that isn't inherited.
     * @param disposition What's done to a file that's there or isn't, like OPEN_EXISTING.
     * @param flags Attributes and flags, like FILE_ATTRIBUTE_NORMAL, or FILE_FLAG_BACKUP_SEMANTICS to open a folder.
     * @param template A file whose attributes a new one copies, or null.
     * @return The handle, which CloseHandle closes; INVALID_HANDLE on failure, with GetLastError saying why.
     */
    CreateFileW #foreign(KERNEL32) : fn(
        name: rawptr,
        access: u32,
        share: u32,
        security: rawptr,
        disposition: u32,
        flags: u32,
        template: rawptr,
    ) -> rawptr : ---
    /**
     * Close a handle, which mustn't be used after.
     *
     * @param handle An open handle of the process's, like one CreateFileW or CreatePipe gave; once this returns
     *     nonzero, it's no good.
     * @return Nonzero if it was closed; 0 if not.
     */
    CloseHandle #foreign(KERNEL32) : fn(handle: rawptr) -> i32 : ---
    /**
     * Read from a file or pipe, waiting for it.
     *
     * @param file The handle, opened to read.
     * @param buffer Where the bytes go.
     * @param count The most bytes to read.
     * @param read Where how many bytes were read is stored: 0 at a file's end.
     * @param overlapped Null, for a handle that isn't overlapped.
     * @return Nonzero if it worked; 0 if not, with GetLastError saying why, ERROR_BROKEN_PIPE for a pipe whose
     *     writers have all closed it.
     */
    ReadFile #foreign(KERNEL32) : fn(file: rawptr, buffer: rawptr, count: u32, read: ptr[mut u32], overlapped: rawptr) -> i32 : ---
    /**
     * Write to a file or pipe, waiting for it.
     *
     * @param file The handle, opened to write.
     * @param bytes The first of count bytes to write; they're read, not kept past the call.
     * @param count How many bytes to write.
     * @param written Where how many bytes were written is stored.
     * @param overlapped Null, for a handle that isn't overlapped.
     * @return Nonzero if it worked; 0 if not, with GetLastError saying why.
     */
    WriteFile #foreign(KERNEL32) : fn(file: rawptr, bytes: rawptr, count: u32, written: ptr[mut u32], overlapped: rawptr) -> i32 : ---
    /**
     * Move a file's offset.
     *
     * @param file An open handle to a file on disk, whose offset the next ReadFile or WriteFile uses; only used, not
     *     closed. A pipe or console has no offset, so it fails.
     * @param distance How far to move it in bytes, which may be negative.
     * @param position Where the new offset is stored, or null.
     * @param method What distance is from, like FILE_END.
     * @return Nonzero if it worked; 0 if not.
     */
    SetFilePointerEx #foreign(KERNEL32) : fn(file: rawptr, distance: i64, position: rawptr, method: u32) -> i32 : ---
    /**
     * Give a file's size.
     *
     * @param file An open handle to the file, opened with at least the right to read its attributes; only used, not
     *     closed.
     * @param size Where its size in bytes is stored.
     * @return Nonzero if it worked; 0 if not, as for a pipe, with GetLastError saying why.
     */
    GetFileSizeEx #foreign(KERNEL32) : fn(file: rawptr, size: ptr[mut i64]) -> i32 : ---
    /**
     * Delete a file.
     *
     * @param name The file's path, UTF-16 with a terminator.
     * @return Nonzero if it was deleted, or marked to go once every handle to it is closed; 0 if not.
     */
    DeleteFileW #foreign(KERNEL32) : fn(name: rawptr) -> i32 : ---
    /**
     * Move a file or folder.
     *
     * @param from Its path, UTF-16 with a terminator.
     * @param to Its new path, UTF-16 with a terminator.
     * @param flags Like MOVEFILE_REPLACE_EXISTING and MOVEFILE_COPY_ALLOWED.
     * @return Nonzero once it's moved; 0 if not, with GetLastError saying why.
     */
    MoveFileExW #foreign(KERNEL32) : fn(from: rawptr, to: rawptr, flags: u32) -> i32 : ---
    /**
     * Give a path's attributes.
     *
     * @param name The path, UTF-16 with a terminator.
     * @return Its attributes, like FILE_ATTRIBUTE_DIRECTORY; INVALID_FILE_ATTRIBUTES if nothing's there or it can't be
     *     looked at.
     */
    GetFileAttributesW #foreign(KERNEL32) : fn(name: rawptr) -> u32 : ---
    /**
     * Make a folder.
     *
     * @param name Its path, UTF-16 with a terminator; the folder it's in has to exist.
     * @param security Security attributes, or null for the defaults.
     * @return Nonzero once it's made; 0 if not, with GetLastError saying why.
     */
    CreateDirectoryW #foreign(KERNEL32) : fn(name: rawptr, security: rawptr) -> i32 : ---
    /**
     * Remove an empty folder.
     *
     * @param name Its path, UTF-16 with a terminator.
     * @return Nonzero once it's removed; 0 if not, with GetLastError saying why.
     */
    RemoveDirectoryW #foreign(KERNEL32) : fn(name: rawptr) -> i32 : ---
    /**
     * Start a search of a folder, giving its first match.
     *
     * @param pattern What to match, UTF-16 with a terminator, like a folder's path and "\*".
     * @param data Where the first match is stored, a FindData.
     * @return The search's handle, which FindClose closes; INVALID_HANDLE on failure, with GetLastError saying why,
     *     ERROR_FILE_NOT_FOUND when nothing matches.
     */
    FindFirstFileW #foreign(KERNEL32) : fn(pattern: rawptr, data: rawptr) -> rawptr : ---
    /**
     * Give a search's next match.
     *
     * @param search The search's handle, from FindFirstFileW.
     * @param data Where the match is stored, a FindData.
     * @return Nonzero if there was one; 0 at the end (ERROR_NO_MORE_FILES) or on failure.
     */
    FindNextFileW #foreign(KERNEL32) : fn(search: rawptr, data: rawptr) -> i32 : ---
    /**
     * End a search.
     *
     * @param search The search's handle, which mustn't be used after.
     * @return Nonzero if it was closed; 0 if not.
     */
    FindClose #foreign(KERNEL32) : fn(search: rawptr) -> i32 : ---
    /**
     * Give the process's current directory.
     *
     * @param size The size of buffer in UTF-16 units, the terminator included.
     * @param buffer Where the path goes, UTF-16 with a terminator, or null with a size of 0 to ask only its size.
     * @return The path's length in units without the terminator, once it's in buffer; if it doesn't fit, the size
     *     needed with the terminator; 0 on failure.
     */
    GetCurrentDirectoryW #foreign(KERNEL32) : fn(size: u32, buffer: rawptr) -> u32 : ---
    /**
     * Change the process's current directory, for every thread.
     *
     * @param name The new one's path, UTF-16 with a terminator.
     * @return Nonzero once it's changed; 0 if not, with GetLastError saying why.
     */
    SetCurrentDirectoryW #foreign(KERNEL32) : fn(name: rawptr) -> i32 : ---

    /** CreateFileW's access to read. */
    GENERIC_READ : u32 : 0x80000000
    /** CreateFileW's access to write. */
    GENERIC_WRITE : u32 : 0x40000000
    /** FILE_SHARE_READ, FILE_SHARE_WRITE and FILE_SHARE_DELETE: others may read, write, delete and rename it. */
    FILE_SHARE_ALL : u32 : 7
    /** CreateFileW's disposition to make a file, or empty one that's there. */
    CREATE_ALWAYS : u32 : 2
    /** CreateFileW's disposition to open only what's there. */
    OPEN_EXISTING : u32 : 3
    /** CreateFileW's disposition to open a file that's there, or make it. */
    OPEN_ALWAYS : u32 : 4
    /** The attribute of a file with no other attributes. */
    FILE_ATTRIBUTE_NORMAL : u32 : 0x80
    /** The attribute of a folder. */
    FILE_ATTRIBUTE_DIRECTORY : u32 : 0x10
    /** What GetFileAttributesW gives on failure. */
    INVALID_FILE_ATTRIBUTES : u32 : 0xffffffff
    /** SetFilePointerEx's method for a distance from the file's end. */
    FILE_END : u32 : 2
    /** MoveFileExW's flag to replace a file at the new path. */
    MOVEFILE_REPLACE_EXISTING : u32 : 1
    /** MoveFileExW's flag to move to another volume by copying, then deleting. */
    MOVEFILE_COPY_ALLOWED : u32 : 2
    /** INVALID_HANDLE_VALUE, what CreateFileW and FindFirstFileW give on failure, as a u64. */
    INVALID_HANDLE : u64 : 0xffff_ffff_ffff_ffff
    /** The error for a pipe whose other end has closed. */
    ERROR_BROKEN_PIPE : u32 : 109
    /** The error for an environment variable that isn't set. */
    ERROR_ENVVAR_NOT_FOUND : u32 : 203

    /**
     * Translate a Win32 error code into an OsError.
     *
     * FILE_NOT_FOUND, PATH_NOT_FOUND, INVALID_DRIVE, BAD_NETPATH and ENVVAR_NOT_FOUND are NotFound; ACCESS_DENIED,
     * WRITE_PROTECT, SHARING_VIOLATION and LOCK_VIOLATION AccessDenied; FILE_EXISTS and ALREADY_EXISTS AlreadyExists;
     * DIRECTORY NotADirectory; DIR_NOT_EMPTY DirectoryNotEmpty; INVALID_NAME, BAD_PATHNAME, FILENAME_EXCED_RANGE and
     * INVALID_PARAMETER InvalidPath; NOT_ENOUGH_MEMORY and OUTOFMEMORY OutOfMemory; and anything else Other.
     *
     * @param code The code, as GetLastError gives it.
     * @return The OsError a caller sees.
     */
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

    /**
     * Translate the calling thread's last error into an OsError.
     *
     * @return The OsError error_of gives for GetLastError's code, so good only right after the call that failed.
     */
    last_error :: fn() -> OsError {
        return error_of(GetLastError())
    }

    /**
     * Convert text to UTF-16 with a terminator, as the wide functions take it.
     *
     * @param text The UTF-8; invalid bytes become U+FFFD.
     * @return The units, from the context's allocator, which free_wide gives back. It's text.count + 1 units long
     *     whatever the conversion's length: the converted text, then 0s to the end, so for text that isn't ASCII the
     *     count is more than the length and a 0. Empty, owning nothing, if memory ran out.
     */
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

    /**
     * Give back what wide, wide_path or relative_name gave.
     *
     * @param units The units, from the context's allocator, which mustn't be used after; empty ones are ignored.
     */
    free_wide :: fn(units: u16[]) {
        runtime.free_array(units, context.allocator)
    }

    /**
     * Convert a path to UTF-16 with a terminator, as wide does, refusing a 0 in it.
     *
     * @param path The path, UTF-8.
     * @return units As wide's, which free_wide gives back; empty, owning nothing, on failure.
     * @return error InvalidPath for a path holding a 0 byte, which would cut it short; OutOfMemory if the units
     *     couldn't be allocated; or null.
     */
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

    /**
     * Convert UTF-16 units to UTF-8.
     *
     * @param start The first unit; unpaired surrogates become U+FFFD.
     * @param count How many units, without a terminator; 0 gives "".
     * @param allocator Where the text is allocated from.
     * @return text The text, which the caller owns; "", owning nothing, for no units or on failure.
     * @return error OutOfMemory if the text couldn't be allocated, or null.
     */
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

    /**
     * Look up an environment variable, with GetEnvironmentVariableW.
     *
     * @param name The variable's name; case doesn't matter, as on Windows generally.
     * @param allocator Where the value's copy is allocated from.
     * @return value The value as UTF-8, which the caller owns; "", owning nothing, on failure.
     * @return error NotFound when it isn't set (or is set but empty, which Windows can't tell apart); InvalidPath for
     *     a name holding a 0 byte; OutOfMemory if a conversion couldn't be allocated; otherwise error_of's; or null.
     */
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

    /**
     * Open a file, relative to the current directory unless its path is absolute, with CreateFileW.
     *
     * Others may read, write, delete and rename it while it's open. READ opens what's there to read; WRITE makes it,
     * or empties what's there, to write; APPEND opens or makes it to write, its offset moved to the end once, here,
     * not before each write; READ_WRITE opens what's there for both. The handle isn't inherited by programs
     * run_process starts.
     *
     * @param path The file's path, UTF-8.
     * @param mode How it's opened.
     * @return file The open file, whose handle is a HANDLE, which the caller closes with system_close; the zero File
     *     on failure.
     * @return error IsADirectory for a folder; InvalidPath for a path holding a 0 byte; OutOfMemory if its conversion
     *     couldn't be allocated; otherwise CreateFileW's error (error_of), like NotFound or AccessDenied (a file
     *     another process has opened without sharing it, too); or null.
     */
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

    /**
     * Close a file's handle; a failure is ignored.
     *
     * @param file The open file, which isn't good afterwards.
     */
    system_close :: fn(file: File) {
        CloseHandle(cast[rawptr](file.handle))
    }

    /** The most bytes one ReadFile or WriteFile is asked for, 1 GiB, since they take a u32. */
    MOST_PER_CALL : usize : 0x40000000

    /**
     * Read from a file, with one ReadFile.
     *
     * @param file The open file, read from where its offset is, which moves past what's read.
     * @param buffer Where the bytes go; at most its count, and at most MOST_PER_CALL, are read. An empty one reads
     *     nothing, without a call.
     * @return count How many bytes were read into buffer's start: 0 at the end, or for a pipe whose writers have all
     *     closed it; fewer than asked when less was there. 0 on failure.
     * @return error ReadFile's error (error_of), like AccessDenied for a file not opened to read; or null.
     */
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

    /**
     * Write to a file, with one WriteFile.
     *
     * @param file The open file, written where its offset is.
     * @param bytes The bytes to write, only read.
     * @param count How many bytes to write, which may be 0; at most MOST_PER_CALL are written.
     * @return written How many were written, which can be fewer than count; the caller writes the rest. 0 on failure.
     * @return error WriteFile's error (error_of): AccessDenied for a file not opened to write, Other for a full
     *     volume; or null.
     */
    system_write :: fn(file: File, bytes: rawptr, count: usize) -> (written : usize, error : OsError?) {
        asked :: if count > MOST_PER_CALL { MOST_PER_CALL } else { count }
        written : u32 = 0
        if WriteFile(cast[rawptr](file.handle), bytes, cast[u32](asked), &written, null) == 0 {
            return 0, last_error()
        }
        return cast[usize](written), null
    }

    /**
     * Give a file's size, with GetFileSizeEx.
     *
     * @param file A File system_open gave that isn't closed; its offset isn't moved.
     * @return size Its size in bytes; 0 on failure.
     * @return error GetFileSizeEx's error (error_of), like Other for a pipe or a console; or null.
     */
    system_file_size :: fn(file: File) -> (size : u64, error : OsError?) {
        size : i64 = 0
        if GetFileSizeEx(cast[rawptr](file.handle), &size) == 0 {
            return 0, last_error()
        }
        return cast[u64](size), null
    }

    /**
     * Delete a file, with DeleteFileW. One another process has open, sharing deletion, goes once they close it.
     *
     * @param path The file's path, relative to the current directory unless it's absolute.
     * @return Null once it's deleted; InvalidPath for a path holding a 0 byte; OutOfMemory if its conversion couldn't
     *     be allocated; otherwise DeleteFileW's error (error_of), like NotFound, or AccessDenied for a read-only file
     *     or a folder.
     */
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

    /**
     * Move a file or folder, with MoveFileExW, replacing a file at the new path, and copying to another volume.
     *
     * @param from What's moved, relative to the current directory unless it's absolute.
     * @param to Its new path, likewise. A folder can't be moved to another volume.
     * @return Null once it's moved; InvalidPath if either path holds a 0 byte; OutOfMemory if a conversion couldn't
     *     be allocated; otherwise MoveFileExW's error (error_of), like NotFound, AlreadyExists or AccessDenied.
     */
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

    /**
     * Find what's at a path, with GetFileAttributesW.
     *
     * @param path The path, relative to the current directory unless it's absolute.
     * @return DIRECTORY for a folder, FILE for anything else that's there, and NOTHING when nothing is, it can't be
     *     looked at, the path holds a 0 byte, or its conversion couldn't be allocated.
     */
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

    /**
     * Make a folder, with CreateDirectoryW.
     *
     * @param path The new folder's path, relative to the current directory unless it's absolute; the folder it's in
     *     has to exist.
     * @return Null once it's made; InvalidPath for a path holding a 0 byte; OutOfMemory if its conversion couldn't be
     *     allocated; otherwise CreateDirectoryW's error (error_of): AlreadyExists if anything is there, NotFound if a
     *     folder on the way is missing, and so on.
     */
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

    /**
     * Remove an empty folder, with RemoveDirectoryW.
     *
     * @param path The folder's path, relative to the current directory unless it's absolute.
     * @return Null once it's removed; InvalidPath for a path holding a 0 byte; OutOfMemory if its conversion couldn't
     *     be allocated; otherwise RemoveDirectoryW's error (error_of): DirectoryNotEmpty for a folder with something
     *     in it, NotADirectory for a file, NotFound, and so on.
     */
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

    /**
     * WIN32_FIND_DATAW: 592 bytes, the attributes first and the name, 260 UTF-16 units with a
     * terminator, at 44.
     */
    FindData :: struct {
        /** The structure's bytes, as 148 words, which FindFirstFileW and FindNextFileW fill in. */
        words : u32[148],
    }
    /** Where in a FindData the name starts, in bytes. */
    FIND_NAME_OFFSET :: 44
    /** The most UTF-16 units a FindData's name has, its terminator included. */
    FIND_NAME_UNITS :: 260

    /**
     * List a folder, with FindFirstFileW and FindNextFileW, in the order they give, without "." and "..".
     *
     * @param path The folder's path, relative to the current directory unless it's absolute, with or without a
     *     separator at its end.
     * @param entries Where the entries are added, after what it holds already, grown with the context's allocator. On
     *     failure, those added so far stay, their names the caller's to free.
     * @param allocator Where each entry's name is allocated, which the caller owns.
     * @return Null once every entry is added, an empty folder too; InvalidPath for a path holding a 0 byte;
     *     OutOfMemory if a conversion or a name couldn't be allocated; otherwise FindFirstFileW's error (error_of),
     *     like NotFound.
     */
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

    /**
     * Give the current directory's absolute path, with GetCurrentDirectoryW.
     *
     * @param allocator Where the path is allocated from.
     * @return path The path as UTF-8, which the caller owns; "", owning nothing, on failure.
     * @return error OutOfMemory if a buffer or the path couldn't be allocated; otherwise GetCurrentDirectoryW's error
     *     (error_of); or null.
     */
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

    /**
     * Change the process's current directory, for every thread, with SetCurrentDirectoryW.
     *
     * @param path The new current directory, relative to the old one unless it's absolute.
     * @return Null once it's changed; InvalidPath for a path holding a 0 byte; OutOfMemory if its conversion couldn't
     *     be allocated; otherwise SetCurrentDirectoryW's error (error_of), like NotFound or NotADirectory, the current
     *     directory left as it was.
     */
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
    /** The ntdll.dll library, where the NT functions here are, for opening paths relative to a directory's handle. */
    NTDLL :: #library("ntdll")

    /**
     * Open or make a file or folder, its name relative to a root directory's handle.
     *
     * @param handle Where the handle is stored, which CloseHandle closes.
     * @param access What the handle may do, like GENERIC_READ, DELETE or FILE_LIST_DIRECTORY.
     * @param attributes An ObjectAttributes: the name and the root it's relative to.
     * @param status Where an IoStatus is stored.
     * @param size A new file's size to reserve, or null.
     * @param file_attributes A new file's attributes, like FILE_ATTRIBUTE_NORMAL.
     * @param share What others may do with it while it's open, like FILE_SHARE_ALL.
     * @param disposition What's done to what's there or isn't, like FILE_OPEN.
     * @param options How it's opened, like FILE_DIRECTORY_FILE or FILE_SYNCHRONOUS_IO_NONALERT.
     * @param extended Extended attributes, or null.
     * @param extended_length The size of extended in bytes, or 0.
     * @return An NTSTATUS: negative on failure, which status_error translates.
     */
    NtCreateFile #foreign(NTDLL) : fn(handle: ptr[mut rawptr], access: u32, attributes: rawptr, status: rawptr, size: rawptr, file_attributes: u32,
        share: u32, disposition: u32, options: u32, extended: rawptr, extended_length: u32) -> i32 : ---
    /**
     * Give a path's basic information without opening it.
     *
     * @param attributes An ObjectAttributes: the name and the root it's relative to.
     * @param information Where FILE_BASIC_INFORMATION is stored, 40 bytes: four times, then the attributes at 32.
     * @return An NTSTATUS: negative when nothing's there or it can't be looked at.
     */
    NtQueryAttributesFile #foreign(NTDLL) : fn(attributes: rawptr, information: rawptr) -> i32 : ---
    /**
     * Change something about an open file, like its name or that it's to be deleted.
     *
     * @param handle The file's handle, opened with the access the change needs, like DELETE.
     * @param status Where an IoStatus is stored.
     * @param information The change, laid out as class says.
     * @param length The size of information in bytes.
     * @param class What information is, like FILE_RENAME_INFORMATION or FILE_DISPOSITION_INFORMATION.
     * @return An NTSTATUS: negative on failure, which status_error translates.
     */
    NtSetInformationFile #foreign(NTDLL) : fn(handle: rawptr, status: rawptr, information: rawptr, length: u32, class: u32) -> i32 : ---
    /**
     * Read information about an open file, like a folder's entries.
     *
     * @param handle The file's or folder's handle.
     * @param class What to read, like FILE_FULL_DIRECTORY_RESTART_INFO for a folder's first entries.
     * @param buffer Where it goes.
     * @param size The size of buffer in bytes.
     * @return Nonzero if it worked; 0 if not, with GetLastError saying why, ERROR_NO_MORE_FILES after a folder's last
     *     entry.
     */
    GetFileInformationByHandleEx #foreign(KERNEL32) : fn(handle: rawptr, class: u32, buffer: rawptr, size: u32) -> i32 : ---

    /** UNICODE_STRING: its length and room in bytes, without a terminator, and its units. */
    UnicodeString :: struct #scoped {
        /** The text's length in bytes, twice its units, without a terminator. */
        length : u16,
        /** The room at buffer in bytes. */
        maximum : u16,
        /** Padding, for buffer's alignment. */
        padding : u32,
        /** The UTF-16 units, which the string doesn't own. */
        buffer : rawptr,
    }

    /** OBJECT_ATTRIBUTES: the name, relative to root. */
    ObjectAttributes :: struct #scoped {
        /** The structure's size in bytes. */
        length : u32,
        /** Padding, for root's alignment. */
        padding : u32,
        /** The directory's handle name is relative to, or null for an absolute NT path. */
        root : rawptr,
        /** The name, a UnicodeString. */
        name : rawptr,
        /** Flags, like OBJ_CASE_INSENSITIVE. */
        attributes : u32,
        /** Padding, for security's alignment. */
        padding_after : u32,
        /** A security descriptor, or null for the default. */
        security : rawptr,
        /** Security quality of service, or null. */
        quality : rawptr,
    }

    /** IO_STATUS_BLOCK: how a call on a file ended. */
    IoStatus :: struct {
        /** The NTSTATUS it ended with. */
        status : u64,
        /** What it gives besides, like what NtCreateFile did. */
        information : u64,
    }

    /** ObjectAttributes' flag for a name matched without regard to case, as Win32 paths are. */
    OBJ_CASE_INSENSITIVE : u32 : 0x40
    /** Access to wait on the handle, which synchronous calls on it need. */
    SYNCHRONIZE : u32 : 0x00100000
    /** Access to delete or rename. */
    DELETE : u32 : 0x00010000
    /** Access to list a folder's entries, or for NtCreateFile to make a folder. */
    FILE_LIST_DIRECTORY : u32 : 0x0001
    /** Access to write only at a file's end. */
    FILE_APPEND_DATA : u32 : 0x0004
    /** Access to go through a folder to what's beneath it. */
    FILE_TRAVERSE : u32 : 0x0020
    /** Access to read a file's attributes. */
    FILE_READ_ATTRIBUTES : u32 : 0x0080
    // NtCreateFile's dispositions
    /** NtCreateFile's disposition to open only what's there. */
    FILE_OPEN : u32 : 1
    /** NtCreateFile's disposition to make it, failing if anything's there. */
    FILE_CREATE : u32 : 2
    /** NtCreateFile's disposition to open what's there, or make it. */
    FILE_OPEN_IF : u32 : 3
    /** NtCreateFile's disposition to empty what's there, or make it. */
    FILE_OVERWRITE_IF : u32 : 5
    // and its options
    /** NtCreateFile's option that it has to be a folder. */
    FILE_DIRECTORY_FILE : u32 : 0x0001
    /** NtCreateFile's option for calls on the handle to wait, as Win32's do. */
    FILE_SYNCHRONOUS_IO_NONALERT : u32 : 0x0020
    /** NtCreateFile's option that it mustn't be a folder. */
    FILE_NON_DIRECTORY_FILE : u32 : 0x0040
    /** CreateFileW's flag that lets it open a folder. */
    FILE_FLAG_BACKUP_SEMANTICS : u32 : 0x02000000
    // NtSetInformationFile's classes, and GetFileInformationByHandleEx's
    /** NtSetInformationFile's class to rename. */
    FILE_RENAME_INFORMATION : u32 : 10
    /** NtSetInformationFile's class to mark for deletion. */
    FILE_DISPOSITION_INFORMATION : u32 : 13
    /** GetFileInformationByHandleEx's class for a folder's next entries. */
    FILE_FULL_DIRECTORY_INFO : u32 : 14
    /** GetFileInformationByHandleEx's class for a folder's entries from its first. */
    FILE_FULL_DIRECTORY_RESTART_INFO : u32 : 15
    /** The error after a folder's last entry. */
    ERROR_NO_MORE_FILES : u32 : 18
    // FILE_FULL_DIR_INFO: the next record's offset first, then the attributes, the name's bytes and the name
    /** Where in a FILE_FULL_DIR_INFO record its attributes are, in bytes. */
    DIRECTORY_INFO_ATTRIBUTES :: 56
    /** Where in a FILE_FULL_DIR_INFO record its name's length in bytes is. */
    DIRECTORY_INFO_NAME_BYTES :: 60
    /** Where in a FILE_FULL_DIR_INFO record its name starts, in bytes; it has no terminator. */
    DIRECTORY_INFO_NAME :: 68
    /** The size of the buffer a folder's entries are read into, in bytes: 64 KiB. */
    LISTING_BYTES :: 65536
    /** The access a Directory's handle has: to list it, go through it, read attributes, and wait on it. */
    DIRECTORY_ACCESS :: FILE_LIST_DIRECTORY | FILE_TRAVERSE | FILE_READ_ATTRIBUTES | SYNCHRONIZE

    /**
     * Translate a failed NTSTATUS into an OsError.
     *
     * NO_SUCH_FILE, OBJECT_NAME_NOT_FOUND and OBJECT_PATH_NOT_FOUND are NotFound; OBJECT_NAME_COLLISION AlreadyExists;
     * ACCESS_DENIED, SHARING_VIOLATION, MEDIA_WRITE_PROTECTED and CANNOT_DELETE AccessDenied; NOT_A_DIRECTORY
     * NotADirectory; FILE_IS_A_DIRECTORY IsADirectory; DIRECTORY_NOT_EMPTY DirectoryNotEmpty; INVALID_PARAMETER,
     * OBJECT_NAME_INVALID and OBJECT_PATH_SYNTAX_BAD InvalidPath; NO_MEMORY and INSUFFICIENT_RESOURCES OutOfMemory;
     * and anything else Other.
     *
     * @param status The status, negative.
     * @return The OsError a caller sees.
     */
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

    /**
     * Convert a path beneath a directory as NT wants it: UTF-16, each '/' a '\'.
     *
     * @param path The path, UTF-8.
     * @return units As wide_path's, from the context's allocator, which free_wide gives back.
     * @return error As wide_path's: InvalidPath for a 0 byte, OutOfMemory; or null.
     */
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

    /**
     * Open a path relative to a directory's handle, with NtCreateFile, its case not mattering.
     *
     * Others may read, write, delete and rename it while it's open; calls on the handle wait.
     *
     * @param root The directory's handle, which stays the caller's.
     * @param path The path beneath it, UTF-8, '/' or '\' between its parts; "" is root itself.
     * @param access What the handle may do; SYNCHRONIZE is added.
     * @param disposition What's done to what's there or isn't, like FILE_OPEN.
     * @param options Like FILE_DIRECTORY_FILE or FILE_NON_DIRECTORY_FILE, or 0 for either; FILE_SYNCHRONOUS_IO_NONALERT
     *     is added.
     * @return handle The handle, which the caller closes with CloseHandle; null on failure.
     * @return error InvalidPath for a path holding a 0 byte or of more than 32767 UTF-16 units; OutOfMemory if its
     *     conversion couldn't be allocated; otherwise NtCreateFile's (status_error); or null.
     */
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

    /**
     * Open a file beneath a directory, with open_relative.
     *
     * READ opens what's there to read; WRITE makes it, or empties what's there, to write; APPEND opens or makes it
     * only to append, so every write goes at the end and it can't be read or its size changed otherwise; READ_WRITE
     * opens what's there for both.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The file's path beneath it; files.hsc has checked it's beneath it.
     * @param mode How it's opened.
     * @return file The open file, which the caller closes with system_close; the zero File on failure.
     * @return error As open_relative's: IsADirectory for a folder, NotFound, AccessDenied, InvalidPath and so on; or
     *     null.
     */
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

    /**
     * Open a folder as a Directory, with CreateFileW, its handle staying on the folder even if it's moved.
     *
     * @param path The folder's path, relative to the current directory unless it's absolute.
     * @return directory The open directory, which the caller closes with system_close_directory; the zero Directory
     *     on failure.
     * @return error NotADirectory for a file; InvalidPath for a path holding a 0 byte; OutOfMemory if its conversion
     *     couldn't be allocated; otherwise CreateFileW's error (error_of), like NotFound or AccessDenied; or null.
     */
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

    /**
     * Open the current directory, as a Directory that stays on that folder even if the current directory changes.
     *
     * @return directory The open directory, which the caller closes; the zero Directory on failure.
     * @return error As system_open_directory's.
     */
    system_working_directory :: fn() -> (directory : Directory, error : OsError?) {
        return system_open_directory(".")
    }

    /**
     * Open a folder beneath a directory, with open_relative.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The folder's path beneath it, or "" for another handle to directory itself.
     * @return opened The open directory, which the caller closes, apart from directory; the zero Directory on
     *     failure.
     * @return error As open_relative's: NotADirectory for a file, NotFound, AccessDenied, InvalidPath and so on; or
     *     null.
     */
    system_open_directory_in :: fn(directory: Directory, path: string) -> (opened : Directory, error : OsError?) {
        handle, error :: open_relative(cast[rawptr](directory.handle), path, DIRECTORY_ACCESS, FILE_OPEN, FILE_DIRECTORY_FILE)
        if error != null {
            return Directory.{0}, error
        }
        return Directory.{cast[u64](handle)}, null
    }

    /**
     * Close a directory's handle; a failure is ignored.
     *
     * @param directory The open directory, which isn't good afterwards.
     */
    system_close_directory :: fn(directory: Directory) {
        CloseHandle(cast[rawptr](directory.handle))
    }

    /**
     * Make a folder beneath a directory, with open_relative.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The new folder's path beneath it; the folder it's in has to exist.
     * @return Null once it's made; open_relative's error otherwise: AlreadyExists if anything is there, NotFound if a
     *     folder on the way is missing, and so on.
     */
    system_make_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        handle, error :: open_relative(cast[rawptr](directory.handle), path, FILE_LIST_DIRECTORY, FILE_CREATE, FILE_DIRECTORY_FILE)
        if error != null {
            return error
        }
        CloseHandle(handle)
        return null
    }

    /**
     * Delete what's at a path beneath a directory: it's marked to go, and goes once every handle to it is closed,
     * this one and any another process has.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The path beneath it.
     * @param options FILE_NON_DIRECTORY_FILE to delete only a file, or FILE_DIRECTORY_FILE only a folder.
     * @return Null once it's marked; open_relative's error, like NotFound, IsADirectory or NotADirectory for the
     *     wrong kind, or AccessDenied; or NtSetInformationFile's (status_error), like DirectoryNotEmpty or
     *     AccessDenied for a read-only file.
     */
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

    /**
     * Delete a file beneath a directory.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The file's path beneath it.
     * @return As delete_relative's; IsADirectory for a folder.
     */
    system_delete_file_in :: fn(directory: Directory, path: string) -> OsError? {
        return delete_relative(directory, path, FILE_NON_DIRECTORY_FILE)
    }

    /**
     * Remove an empty folder beneath a directory.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The folder's path beneath it.
     * @return As delete_relative's; DirectoryNotEmpty for a folder with something in it, NotADirectory for a file.
     */
    system_remove_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        return delete_relative(directory, path, FILE_DIRECTORY_FILE)
    }

    /**
     * Move a file or folder beneath a directory, replacing a file at the new path.
     *
     * What's at from is opened for deleting, then given to as its new name relative to the directory:
     * FILE_RENAME_INFORMATION's ReplaceIfExists, padded, its root at 8, the name's bytes at 16 and the name at 20.
     *
     * @param directory The open directory both paths start from, which stays the caller's.
     * @param from What's moved, beneath directory.
     * @param to Its new path, beneath directory.
     * @return Null once it's moved; open_relative's error for from, like NotFound; relative_name's for to;
     *     OutOfMemory if the rename's information couldn't be allocated; or NtSetInformationFile's (status_error),
     *     like AccessDenied.
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

    /**
     * Find what's at a path beneath a directory, with NtQueryAttributesFile, without opening it.
     *
     * FILE_BASIC_INFORMATION: four times, then the attributes at 32.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The path beneath it. Unlike open_relative's, its length isn't checked.
     * @return DIRECTORY for a folder, FILE for anything else that's there, and NOTHING when nothing is, it can't be
     *     looked at, the path holds a 0 byte, or its conversion couldn't be allocated.
     */
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

    /**
     * List a folder beneath a directory, or the directory itself, with GetFileInformationByHandleEx, in the order it
     * gives, without "." and "..".
     *
     * A handle of its own is opened to list through, even for the directory itself, so the listing starts at its
     * beginning; entries are read LISTING_BYTES at a time.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The folder's path beneath it, or "" for the directory itself.
     * @param entries Where the entries are added, after what it holds already, grown with the context's allocator. On
     *     failure, those added so far stay, their names the caller's to free.
     * @param allocator Where each entry's name is allocated, which the caller owns.
     * @return Null once every entry is added; open_relative's error, like NotFound or NotADirectory for a file;
     *     OutOfMemory if the buffer or a name couldn't be allocated; or GetFileInformationByHandleEx's (error_of).
     */
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
