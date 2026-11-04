package os

import intrinsics from "base"
import runtime from "base"

/*
 * Linux's side of std/os: system calls made directly, so a program needs no C library for them
 * (one that links C makes the same calls). Paths are copied with a terminator into a buffer on the
 * stack, PATH_BUFFER_SIZE bytes, so a longer path is InvalidPath. On x86-64 and AArch64, whose calls,
 * some flags and struct stat differ.
 */
#if OS == .Linux && TARGET_ARCH == .x86_64 {
    /** The system call number of read on x86-64. */
    SYS_READ : u64 : 0
    /** The system call number of write on x86-64. */
    SYS_WRITE : u64 : 1
    /** The system call number of close on x86-64. */
    SYS_CLOSE : u64 : 3
    /** The system call number of fstat on x86-64. */
    SYS_FSTAT : u64 : 5
    /** The system call number of getcwd on x86-64. */
    SYS_GETCWD : u64 : 79
    /** The system call number of chdir on x86-64. */
    SYS_CHDIR : u64 : 80
    /** The system call number of getdents64 on x86-64. */
    SYS_GETDENTS64 : u64 : 217
    /** The system call number of openat on x86-64. */
    SYS_OPENAT : u64 : 257
    /** The system call number of mkdirat on x86-64. */
    SYS_MKDIRAT : u64 : 258
    /** The system call number of newfstatat on x86-64. */
    SYS_NEWFSTATAT : u64 : 262
    /** The system call number of unlinkat on x86-64. */
    SYS_UNLINKAT : u64 : 263
    /** The system call number of renameat on x86-64. */
    SYS_RENAMEAT : u64 : 264

    /** The openat flag that fails with ENOTDIR unless the path is a folder; x86-64's value. */
    O_DIRECTORY : u64 : 0x10000
    /**
     * Which of Stat's words holds st_mode, in its low 32 bits: struct stat on x86-64 is 144 bytes, st_mode the low
     * half of the fourth word, st_size the seventh.
     */
    STAT_MODE_WORD :: 3
}
#else_if OS == .Linux && TARGET_ARCH == .arm64 {
    /** The system call number of getcwd in the generic table, which AArch64 uses. */
    SYS_GETCWD : u64 : 17
    /** The system call number of mkdirat in the generic table. */
    SYS_MKDIRAT : u64 : 34
    /** The system call number of unlinkat in the generic table. */
    SYS_UNLINKAT : u64 : 35
    /** The system call number of chdir in the generic table. */
    SYS_CHDIR : u64 : 49
    /** The system call number of openat in the generic table. */
    SYS_OPENAT : u64 : 56
    /** The system call number of close in the generic table. */
    SYS_CLOSE : u64 : 57
    /** The system call number of getdents64 in the generic table. */
    SYS_GETDENTS64 : u64 : 61
    /** The system call number of read in the generic table. */
    SYS_READ : u64 : 63
    /** The system call number of write in the generic table. */
    SYS_WRITE : u64 : 64
    /** The system call number of newfstatat in the generic table. */
    SYS_NEWFSTATAT : u64 : 79
    /** The system call number of fstat in the generic table. */
    SYS_FSTAT : u64 : 80
    /** The system call number of renameat2, given no flags, standing in for renameat, which the generic table lacks. */
    SYS_RENAMEAT : u64 : 276

    /** The openat flag that fails with ENOTDIR unless the path is a folder; AArch64's value. */
    O_DIRECTORY : u64 : 0x4000
    /**
     * Which of Stat's words holds st_mode, in its low 32 bits: struct stat on AArch64 is 128 bytes, st_mode the low
     * half of the third word, st_size the seventh.
     */
    STAT_MODE_WORD :: 2
}

#if OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {

    /** The directory openat and the other *at calls are given for a relative path to start from the current one. */
    AT_FDCWD : u64 : 0xffff_ffff_ffff_ff9c
    /** The unlinkat flag to remove a folder, which has to be empty, rather than a file. */
    AT_REMOVEDIR : u64 : 0x200

    /** The openat flag to open only for reading. */
    O_RDONLY : u64 : 0
    /** The openat flag to open only for writing. */
    O_WRONLY : u64 : 1
    /** The openat flag to open for reading and writing. */
    O_RDWR : u64 : 2
    /** The openat flag to make the file if it isn't there. */
    O_CREAT : u64 : 0x40
    /** The openat flag to empty a file that's there. */
    O_TRUNC : u64 : 0x200
    /** The openat flag for every write to go at the file's end. */
    O_APPEND : u64 : 0x400
    /** The flag, to openat and pipe2, for the descriptor to be closed in a program execve starts, not inherited. */
    O_CLOEXEC : u64 : 0x80000

    /**
     * The size in bytes of the stack buffer a path is copied into: Linux's PATH_MAX of 4096 bytes and the
     * terminator, so a path of more than 4096 bytes is InvalidPath before the system sees it.
     */
    PATH_BUFFER_SIZE :: 4097

    /**
     * The C struct stat, as large as x86-64's (144 bytes), with st_size the seventh word on both architectures and
     * st_mode in the word STAT_MODE_WORD says.
     */
    Stat :: struct {
        /** The structure's bytes, as 18 words, which fstat and newfstatat fill in. */
        words : u64[18],
    }
    /** The bits of st_mode that say what kind of thing it is. */
    S_IFMT : u32 : 0xf000
    /** What st_mode & S_IFMT is for a folder. */
    S_IFDIR : u32 : 0x4000

    /**
     * Tell whether a system call failed.
     *
     * @param result What the call returned, which is -errno, from -4095 to -1, when it fails.
     * @return True if it's an error, which error_of translates; false if it's a result.
     */
    failed :: fn(result: u64) -> bool {
        return result > 0xffff_ffff_ffff_f000
    }

    /**
     * Translate a failed system call's result into an OsError.
     *
     * ENOENT is NotFound; EPERM, EACCES and EROFS AccessDenied; EEXIST AlreadyExists; ENOTDIR NotADirectory; EISDIR
     * IsADirectory; ENOTEMPTY DirectoryNotEmpty; EINVAL, ENAMETOOLONG and ELOOP InvalidPath; ENOMEM OutOfMemory; and
     * anything else, like ENOSPC, EIO, EXDEV or EBADF, Other.
     *
     * @param result The call's result, one that failed says is an error.
     * @return The OsError a caller sees.
     */
    error_of :: fn(result: u64) -> OsError {
        errno :: 0 - result
        if errno == 2 {
            return .NotFound
        }
        if errno == 1 || errno == 13 || errno == 30 {
            return .AccessDenied
        }
        if errno == 17 {
            return .AlreadyExists
        }
        if errno == 20 {
            return .NotADirectory
        }
        if errno == 21 {
            return .IsADirectory
        }
        if errno == 39 {
            return .DirectoryNotEmpty
        }
        if errno == 22 || errno == 36 || errno == 40 {
            return .InvalidPath
        }
        if errno == 12 {
            return .OutOfMemory
        }
        return .Other
    }

    /**
     * Copy a path into a buffer with a terminator, as the system calls take it.
     *
     * @param path The path, as bytes.
     * @param buffer Where it's copied, usually PATH_BUFFER_SIZE bytes on the caller's stack. On failure, some of it
     *     may have been written.
     * @return True once the path and its 0 are at the buffer's start; false if they don't fit, or the path holds a 0
     *     byte, which would cut it short.
     */
    terminated :: fn(path: string, buffer: mut u8[]) -> bool {
        if path.count + 1 > buffer.count {
            return false
        }
        for character, index in path {
            if character == cast[char](0) || index >= buffer.count {
                return false
            }
            buffer[index] = cast[u8](character)
        }
        if path.count < buffer.count {
            buffer[path.count] = 0
        }
        return true
    }

    /**
     * Look up an environment variable in the environment the process started with.
     *
     * Entries are read from the startup's environment pointers, each name=value; the first whose name matches
     * exactly is used. An entry of more than runtime.ARGUMENT_TEXT_LIMIT bytes is skipped.
     *
     * @param name The variable's name, matched exactly, case and all.
     * @param allocator Where the value's copy is allocated from.
     * @return value The value, copied from allocator, which the caller owns; "", owning nothing, when it's set but
     *     empty or on failure.
     * @return error NotFound when it isn't set, name is empty, or the process has no environment; OutOfMemory when
     *     the copy couldn't be allocated; or null.
     */
    system_get_environment :: fn(name: string, allocator: runtime.Allocator) -> (value #unrestricted : string, error : OsError?) {
        state :: intrinsics.process_state()
        if state.environment_pointers == null || name.count == 0 {
            return "", OsError.NotFound
        }
        index : usize = 0
        loop {
            entry :: cast[ptr[rawptr]](state.environment_pointers + index * 8)^
            if entry == null {
                break
            }
            index += 1
            text :: runtime.cstring_view(entry, runtime.ARGUMENT_TEXT_LIMIT) or_continue
            // name=value
            if text.count > name.count && text[name.count] == '=' {
                matches := true
                for character, position in name {
                    if position >= text.count || text[position] != character {
                        matches = false
                        break
                    }
                }
                if matches {
                    return copy_string(string_of(cast[ptr[u8]](entry + name.count + 1), text.count - name.count - 1), allocator)
                }
            }
        }
        return "", OsError.NotFound
    }

    /**
     * Open a file, relative to the current directory unless its path is absolute.
     *
     * @param path The file's path, relative to the current directory unless it's absolute; links in it are followed.
     *     Over 4096 bytes, or holding a 0 byte, it isn't tried, and the error is InvalidPath.
     * @param mode How it's opened, as open_at takes it.
     * @return file The open file, a descriptor the caller closes with system_close; the zero File on failure.
     * @return error As open_at's.
     */
    system_open :: fn(path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        return open_at(AT_FDCWD, path, mode)
    }

    /**
     * Open a file relative to a directory, with openat, as system_open opens it.
     *
     * READ opens for reading; WRITE for writing, made if it isn't there and emptied if it is; APPEND for writing at
     * the end, made if it isn't there; READ_WRITE for both, not made. A file that's made gets 0666, less the
     * process's umask. The descriptor isn't inherited by programs run_process starts.
     *
     * @param at The directory's descriptor, or AT_FDCWD for the current directory; only used, not closed.
     * @param path The file's path, relative to at unless it's absolute; links in it are followed.
     * @param mode How it's opened.
     * @return file The open file, whose handle is the descriptor, which the caller closes; the zero File on failure.
     * @return error InvalidPath for a path over 4096 bytes or holding a 0 byte; otherwise openat's error (error_of),
     *     like NotFound, AccessDenied or IsADirectory (a folder opened to write); or null.
     */
    open_at :: fn(at: u64, path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        buffer : u8[PATH_BUFFER_SIZE]
        if !terminated(path, buffer) {
            return File.{0}, OsError.InvalidPath
        }
        flags := O_RDONLY
        if mode == .WRITE {
            flags = O_WRONLY | O_CREAT | O_TRUNC
        }
        else if mode == .APPEND {
            flags = O_WRONLY | O_CREAT | O_APPEND
        }
        else if mode == .READ_WRITE {
            flags = O_RDWR
        }
        // 0666, rw-rw-rw-, less the process's umask
        result :: runtime.linux_syscall(SYS_OPENAT, at, cast[u64](&buffer[0]), flags | O_CLOEXEC, 438)
        if failed(result) {
            return File.{0}, error_of(result)
        }
        return File.{result}, null
    }

    /**
     * Open a file beneath a directory, as open_at opens it.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The file's path, relative to directory; files.hsc has checked it's beneath it.
     * @param mode How it's opened.
     * @return file The open file, which the caller closes with system_close; the zero File on failure.
     * @return error As open_at's.
     */
    system_open_in :: fn(directory: Directory, path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        return open_at(directory.handle, path, mode)
    }

    /**
     * Open a directory as a descriptor of its own, which reads nothing: what the *at calls start from.
     *
     * @param at The descriptor of the directory path starts from, or AT_FDCWD; only used, not closed.
     * @param path The directory's path, relative to at unless it's absolute.
     * @return directory The open directory, whose handle is the descriptor, which the caller closes with
     *     system_close_directory; the zero Directory on failure.
     * @return error InvalidPath for a path over 4096 bytes or holding a 0 byte; NotADirectory for a file; otherwise
     *     openat's error (error_of), like NotFound or AccessDenied; or null.
     */
    open_directory_at :: fn(at: u64, path: string) -> (directory : Directory, error : OsError?) {
        buffer : u8[PATH_BUFFER_SIZE]
        if !terminated(path, buffer) {
            return Directory.{0}, OsError.InvalidPath
        }
        result :: runtime.linux_syscall(SYS_OPENAT, at, cast[u64](&buffer[0]), O_RDONLY | O_DIRECTORY | O_CLOEXEC, 0)
        if failed(result) {
            return Directory.{0}, error_of(result)
        }
        return Directory.{result}, null
    }

    /**
     * Open a directory, relative to the current directory unless its path is absolute.
     *
     * @param path The directory's path, relative to the current directory unless it's absolute. Over 4096 bytes, or
     *     holding a 0 byte, it isn't tried, and the error is InvalidPath; a file's gives NotADirectory.
     * @return directory The open directory, which the caller closes; the zero Directory on failure.
     * @return error As open_directory_at's.
     */
    system_open_directory :: fn(path: string) -> (directory : Directory, error : OsError?) {
        return open_directory_at(AT_FDCWD, path)
    }

    /**
     * Open the current directory, as a Directory that stays on that folder even if the current directory changes.
     *
     * @return directory The open directory, which the caller closes; the zero Directory on failure.
     * @return error As open_directory_at's, like NotFound if the current folder was removed.
     */
    system_working_directory :: fn() -> (directory : Directory, error : OsError?) {
        return open_directory_at(AT_FDCWD, ".")
    }

    /**
     * Open a directory beneath a directory.
     *
     * @param directory The open directory path starts from, which stays the caller's.
     * @param path The path beneath it.
     * @return opened The open directory, which the caller closes, apart from directory; the zero Directory on failure.
     * @return error As open_directory_at's.
     */
    system_open_directory_in :: fn(directory: Directory, path: string) -> (opened : Directory, error : OsError?) {
        return open_directory_at(directory.handle, path)
    }

    /**
     * Close a directory's descriptor; a failure is ignored.
     *
     * @param directory The open directory, which isn't good afterwards. Not the zero Directory, whose handle is
     *     descriptor 0, standard input, which this would close.
     */
    system_close_directory :: fn(directory: Directory) {
        runtime.linux_syscall(SYS_CLOSE, directory.handle)
    }

    /**
     * Close a file's descriptor; a failure is ignored.
     *
     * @param file The open file, which isn't good afterwards. Not the zero File, whose handle is descriptor 0,
     *     standard input, which this would close.
     */
    system_close :: fn(file: File) {
        runtime.linux_syscall(SYS_CLOSE, file.handle)
    }

    /**
     * Read from a file, with one read, tried again when a signal interrupts it.
     *
     * @param file The open file, read from where its offset is, which moves past what's read.
     * @param buffer Where the bytes go; at most its count are read. An empty one reads nothing, without a call.
     * @return count How many bytes were read into buffer's start: 0 at the end, or a pipe whose writers are all
     *     closed; fewer than asked when less was there. 0 on failure.
     * @return error What read failed with (error_of): IsADirectory for a folder, Other for a descriptor not open to
     *     read (EBADF) or a device error; or null.
     */
    system_read :: fn(file: File, buffer: mut u8[]) -> (count : usize, error : OsError?) {
        if buffer.count == 0 {
            return 0, null
        }
        loop {
            result :: runtime.linux_syscall(SYS_READ, file.handle, cast[u64](buffer.data), cast[u64](buffer.count))
            // EINTR: again
            if result == ~cast[u64](3) {
                continue
            }
            if failed(result) {
                return 0, error_of(result)
            }
            return cast[usize](result), null
        }
    }

    /**
     * Write to a file, with one write, tried again when a signal interrupts it.
     *
     * @param file The open file, written where its offset is, or at the end if it was opened to append.
     * @param bytes The bytes to write, only read.
     * @param count How many bytes to write, which may be 0.
     * @return written How many were written, which can be fewer than count, as to a pipe or a full volume; the caller
     *     writes the rest. 0 on failure.
     * @return error What write failed with (error_of): Other for a full volume, a device error or a descriptor not
     *     open to write; or null.
     */
    system_write :: fn(file: File, bytes: rawptr, count: usize) -> (written : usize, error : OsError?) {
        loop {
            result :: runtime.linux_syscall(SYS_WRITE, file.handle, cast[u64](bytes), cast[u64](count))
            if result == ~cast[u64](3) {
                continue
            }
            if failed(result) {
                return 0, error_of(result)
            }
            return cast[usize](result), null
        }
    }

    /**
     * Give a file's size, from fstat.
     *
     * @param file A File system_open gave that isn't closed; its offset isn't moved.
     * @return size Its size in bytes as fstat gives st_size: for a pipe or a terminal, usually 0. 0 on failure.
     * @return error What fstat failed with (error_of), like Other for a descriptor that isn't open; or null.
     */
    system_file_size :: fn(file: File) -> (size : u64, error : OsError?) {
        status : Stat
        result :: runtime.linux_syscall(SYS_FSTAT, file.handle, cast[u64](&status))
        if failed(result) {
            return 0, error_of(result)
        }
        return status.words[6], null
    }

    /**
     * Delete a file, relative to the current directory unless its path is absolute.
     *
     * @param path The file's path. A link is deleted, not what it points to.
     * @return As unlink_at's; IsADirectory for a folder.
     */
    system_delete_file :: fn(path: string) -> OsError? {
        return unlink_at(AT_FDCWD, path, 0)
    }

    /**
     * Delete a file beneath a directory.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The file's path beneath it.
     * @return As unlink_at's; IsADirectory for a folder.
     */
    system_delete_file_in :: fn(directory: Directory, path: string) -> OsError? {
        return unlink_at(directory.handle, path, 0)
    }

    /**
     * Remove an empty folder beneath a directory.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The folder's path beneath it.
     * @return As unlink_at's; DirectoryNotEmpty for a folder with something in it, NotADirectory for a file.
     */
    system_remove_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        return unlink_at(directory.handle, path, AT_REMOVEDIR)
    }

    /**
     * Remove what's at a path, with unlinkat.
     *
     * @param at The descriptor of the directory path starts from, or AT_FDCWD; only used, not closed.
     * @param path The path, relative to at unless it's absolute.
     * @param flags 0 to delete a file, or AT_REMOVEDIR to remove an empty folder.
     * @return Null once it's gone; InvalidPath for a path over 4096 bytes or holding a 0 byte; otherwise unlinkat's
     *     error (error_of), like NotFound or AccessDenied.
     */
    unlink_at :: fn(at: u64, path: string, flags: u64) -> OsError? {
        buffer : u8[PATH_BUFFER_SIZE]
        if !terminated(path, buffer) {
            return OsError.InvalidPath
        }
        result :: runtime.linux_syscall(SYS_UNLINKAT, at, cast[u64](&buffer[0]), flags)
        if failed(result) {
            return error_of(result)
        }
        return null
    }

    /**
     * Move a file or folder, relative to the current directory unless the paths are absolute.
     *
     * @param from What's moved.
     * @param to Its new path.
     * @return As rename_at's.
     */
    system_rename :: fn(from: string, to: string) -> OsError? {
        return rename_at(AT_FDCWD, from, to)
    }

    /**
     * Move a file or folder beneath a directory.
     *
     * @param directory The open directory both paths start from, which stays the caller's.
     * @param from What's moved, beneath directory.
     * @param to Its new path, beneath directory.
     * @return As rename_at's.
     */
    system_rename_in :: fn(directory: Directory, from: string, to: string) -> OsError? {
        return rename_at(directory.handle, from, to)
    }

    /**
     * Move a file or folder, with renameat, both paths starting from one directory.
     *
     * A file already at to is replaced, in one step; so is an empty folder, when what's moved is a folder.
     *
     * @param at The descriptor of the directory both paths start from, or AT_FDCWD; only used, not closed.
     * @param from What's moved.
     * @param to Its new path, on the same volume.
     * @return Null once it's moved; InvalidPath if either path is over 4096 bytes or holds a 0 byte; otherwise
     *     renameat's error (error_of), like NotFound, AccessDenied, DirectoryNotEmpty for a folder at to with
     *     something in it, or Other for another volume (EXDEV).
     */
    rename_at :: fn(at: u64, from: string, to: string) -> OsError? {
        source : u8[PATH_BUFFER_SIZE]
        target : u8[PATH_BUFFER_SIZE]
        if !terminated(from, source) || !terminated(to, target) {
            return OsError.InvalidPath
        }
        result :: runtime.linux_syscall(SYS_RENAMEAT, at, cast[u64](&source[0]), at, cast[u64](&target[0]))
        if failed(result) {
            return error_of(result)
        }
        return null
    }

    /**
     * Find what's at a path, relative to the current directory unless it's absolute.
     *
     * @param path The path, relative to the current directory unless it's absolute; links are followed. One too long
     *     for PATH_BUFFER_SIZE, or holding a 0 byte, gives NOTHING.
     * @return As path_kind_at's.
     */
    system_path_kind :: fn(path: string) -> PathKind {
        return path_kind_at(AT_FDCWD, path)
    }

    /**
     * Find what's at a path beneath a directory.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The path beneath it.
     * @return As path_kind_at's.
     */
    system_path_kind_in :: fn(directory: Directory, path: string) -> PathKind {
        return path_kind_at(directory.handle, path)
    }

    /**
     * Find what's at a path, following links.
     *
     * @param at The descriptor of the directory path starts from, or AT_FDCWD; only used, not closed.
     * @param path The path, relative to at unless it's absolute.
     * @return DIRECTORY for a folder, FILE for anything else that's there (a device or a pipe too), and NOTHING when
     *     nothing is, the path is too long or holds a 0 byte, it can't be looked at, or a link leads nowhere.
     */
    path_kind_at :: fn(at: u64, path: string) -> PathKind {
        buffer : u8[PATH_BUFFER_SIZE]
        if !terminated(path, buffer) {
            return .NOTHING
        }
        return kind_at(at, cast[rawptr](&buffer[0]))
    }

    /**
     * Make a folder, relative to the current directory unless its path is absolute.
     *
     * @param path The new folder's path; the folder it's in has to exist.
     * @return As make_directory_at's.
     */
    system_make_directory :: fn(path: string) -> OsError? {
        return make_directory_at(AT_FDCWD, path)
    }

    /**
     * Make a folder beneath a directory.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The new folder's path beneath it; the folder it's in has to exist.
     * @return As make_directory_at's.
     */
    system_make_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        return make_directory_at(directory.handle, path)
    }

    /**
     * Make a folder, with mkdirat, given 0777 less the process's umask.
     *
     * @param at The descriptor of the directory path starts from, or AT_FDCWD; only used, not closed.
     * @param path The new folder's path, relative to at unless it's absolute. Only the last part is made.
     * @return Null once it's made; InvalidPath for a path over 4096 bytes or holding a 0 byte; otherwise mkdirat's
     *     error (error_of): AlreadyExists if anything is there, NotFound if a folder on the way is missing,
     *     AccessDenied, and so on.
     */
    make_directory_at :: fn(at: u64, path: string) -> OsError? {
        buffer : u8[PATH_BUFFER_SIZE]
        if !terminated(path, buffer) {
            return OsError.InvalidPath
        }
        // 0777, rwxrwxrwx, less the process's umask
        result :: runtime.linux_syscall(SYS_MKDIRAT, at, cast[u64](&buffer[0]), 511)
        if failed(result) {
            return error_of(result)
        }
        return null
    }

    /**
     * Remove an empty folder, relative to the current directory unless its path is absolute.
     *
     * @param path The path of the folder to remove, relative to the current directory unless it's absolute; the folder
     *     has to be empty. Over 4096 bytes, or holding a 0 byte, it isn't tried.
     * @return Null once it's gone; InvalidPath for a path over 4096 bytes or holding a 0 byte; otherwise unlinkat's
     *     error (error_of): DirectoryNotEmpty for a folder with something in it, NotADirectory for a file,
     *     NotFound, AccessDenied, and so on.
     */
    system_remove_directory :: fn(path: string) -> OsError? {
        buffer : u8[PATH_BUFFER_SIZE]
        if !terminated(path, buffer) {
            return OsError.InvalidPath
        }
        result :: runtime.linux_syscall(SYS_UNLINKAT, AT_FDCWD, cast[u64](&buffer[0]), AT_REMOVEDIR)
        if failed(result) {
            return error_of(result)
        }
        return null
    }

    // getdents64's records: inode (8), offset (8), record length (2), type (1), then the name and a 0.
    /** The getdents64 type for an entry whose kind the file system doesn't give, which then has to be looked up. */
    DT_UNKNOWN : u8 : 0
    /** The getdents64 type for a folder. */
    DT_DIR : u8 : 4

    /**
     * List a folder, relative to the current directory unless its path is absolute.
     *
     * @param path The folder's path, relative to the current directory unless it's absolute. Over 4096 bytes, or
     *     holding a 0 byte, it isn't listed, and the error is InvalidPath.
     * @param entries Where the entries are added, after what it holds already.
     * @param allocator Where the entries' names are allocated.
     * @return As list_at's.
     */
    system_list_directory :: fn(path: string, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        return list_at(AT_FDCWD, path, entries, allocator)
    }

    /**
     * List a folder beneath a directory, or the directory itself.
     *
     * @param directory The open directory, which stays the caller's.
     * @param path The folder's path beneath it, or "" for the directory itself, opened again for its own listing so
     *     the listing starts at its beginning.
     * @param entries Where the entries are added, after what it holds already.
     * @param allocator Where the entries' names are allocated.
     * @return As list_at's.
     */
    system_list_directory_in :: fn(directory: Directory, path: string, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        return list_at(directory.handle, if path.count == 0 { "." } else { path }, entries, allocator)
    }

    /**
     * List a folder, with getdents64, in the order the file system gives, without "." and "..".
     *
     * Whether each entry is a folder comes from its type; when the file system gives none, it's looked up. A link is
     * never a folder here, even to one.
     *
     * @param at The descriptor of the directory path starts from, or AT_FDCWD; only used, not closed.
     * @param path The folder's path, relative to at unless it's absolute.
     * @param entries Where the entries are added, after what it holds already, grown with the context's allocator. On
     *     failure, those added so far stay, their names the caller's to free.
     * @param allocator Where each entry's name is allocated, which the caller owns.
     * @return Null once every entry is added; InvalidPath for a path over 4096 bytes or holding a 0 byte;
     *     OutOfMemory if a name couldn't be copied; Other for a malformed record; otherwise openat's or getdents64's
     *     error (error_of), like NotFound, NotADirectory or AccessDenied.
     */
    list_at :: fn(at: u64, path: string, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        buffer : u8[PATH_BUFFER_SIZE]
        if !terminated(path, buffer) {
            return OsError.InvalidPath
        }
        opened :: runtime.linux_syscall(SYS_OPENAT, at, cast[u64](&buffer[0]), O_RDONLY | O_DIRECTORY | O_CLOEXEC, 0)
        if failed(opened) {
            return error_of(opened)
        }
        defer runtime.linux_syscall(SYS_CLOSE, opened)
        records : u64[256]
        start :: cast[rawptr](&records[0])
        loop {
            filled :: runtime.linux_syscall(SYS_GETDENTS64, opened, cast[u64](start), cast[u64](size_of(u64[256])))
            if failed(filled) {
                return error_of(filled)
            }
            if filled == 0 {
                break
            }
            offset : usize = 0
            loop {
                if offset >= cast[usize](filled) {
                    break
                }
                record :: start + offset
                length :: cast[usize](cast[ptr[u16]](record + 16)^)
                // A record holds its name and that name's 0 after the 19 bytes before it
                if length <= 19 || offset + length > cast[usize](filled) {
                    return OsError.Other
                }
                kind :: cast[ptr[u8]](record + 18)^
                name :: runtime.cstring_view(record + 19, length - 19) or_return OsError.Other
                offset += length
                if (name.count == 1 && name[0] == '.') || (name.count == 2 && name[0] == '.' && name[1] == '.') {
                    continue
                }
                copy, error :: copy_string(name, allocator)
                if error != null {
                    return error
                }
                is_folder := kind == DT_DIR
                if kind == DT_UNKNOWN {
                    is_folder = kind_at(opened, record + 19) == .DIRECTORY
                }
                runtime.array_add(entries, DirectoryEntry.{name = copy, is_directory = is_folder})
            }
        }
        return null
    }

    /**
     * Find what a name is in an open folder, with newfstatat, following links: for file systems getdents64 gives no
     * types for, and for path_kind_at.
     *
     * @param directory The descriptor of the folder name is in, or AT_FDCWD; only used, not closed.
     * @param name The name or path, with a 0 after it.
     * @return DIRECTORY for a folder, FILE for anything else that's there, NOTHING when newfstatat fails.
     */
    kind_at :: fn(directory: u64, name: rawptr) -> PathKind {
        status : Stat
        result :: runtime.linux_syscall(SYS_NEWFSTATAT, directory, cast[u64](name), cast[u64](&status), 0)
        if failed(result) {
            return .NOTHING
        }
        if cast[u32](status.words[STAT_MODE_WORD] & 0xffff_ffff) & S_IFMT == S_IFDIR {
            return .DIRECTORY
        }
        return .FILE
    }

    /**
     * Give the current directory's absolute path, from getcwd.
     *
     * @param allocator Where the path is allocated from.
     * @return path The path, which the caller owns; "/" if getcwd gave something too short or long to be one; "",
     *     owning nothing, on failure.
     * @return error What getcwd failed with (error_of): NotFound if the current folder was removed, Other for a path
     *     over 4096 bytes; OutOfMemory if the copy couldn't be allocated; or null.
     */
    system_current_directory :: fn(allocator: runtime.Allocator) -> (path #unrestricted : string, error : OsError?) {
        buffer : u8[PATH_BUFFER_SIZE]
        // The length with its terminator
        result :: runtime.linux_syscall(SYS_GETCWD, cast[u64](&buffer[0]), cast[u64](size_of(u8[PATH_BUFFER_SIZE])))
        if failed(result) {
            return "", error_of(result)
        }
        if result < 2 || result > PATH_BUFFER_SIZE {
            return copy_string("/", allocator)
        }
        return copy_string(string_of(&buffer[0], cast[usize](result) - 1), allocator)
    }

    /**
     * Change the process's current directory, for every thread, with chdir.
     *
     * @param path The new current directory, relative to the old one unless it's absolute.
     * @return Null once it's changed; InvalidPath for a path over 4096 bytes or holding a 0 byte; otherwise chdir's
     *     error (error_of), like NotFound, NotADirectory or AccessDenied, the current directory left as it was.
     */
    system_set_current_directory :: fn(path: string) -> OsError? {
        buffer : u8[PATH_BUFFER_SIZE]
        if !terminated(path, buffer) {
            return OsError.InvalidPath
        }
        result :: runtime.linux_syscall(SYS_CHDIR, cast[u64](&buffer[0]))
        if failed(result) {
            return error_of(result)
        }
        return null
    }
}
