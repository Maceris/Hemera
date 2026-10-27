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
    SYS_READ : u64 : 0
    SYS_WRITE : u64 : 1
    SYS_CLOSE : u64 : 3
    SYS_FSTAT : u64 : 5
    SYS_GETCWD : u64 : 79
    SYS_CHDIR : u64 : 80
    SYS_GETDENTS64 : u64 : 217
    SYS_OPENAT : u64 : 257
    SYS_MKDIRAT : u64 : 258
    SYS_NEWFSTATAT : u64 : 262
    SYS_UNLINKAT : u64 : 263
    SYS_RENAMEAT : u64 : 264

    O_DIRECTORY : u64 : 0x10000
    // struct stat on x86-64: 144 bytes, st_mode the low half of the fourth word, st_size the seventh
    STAT_MODE_WORD :: 3
}
#else_if OS == .Linux && TARGET_ARCH == .arm64 {
    // The generic table's numbers, which AArch64 uses: renameat is renameat2, given no flags
    SYS_GETCWD : u64 : 17
    SYS_MKDIRAT : u64 : 34
    SYS_UNLINKAT : u64 : 35
    SYS_CHDIR : u64 : 49
    SYS_OPENAT : u64 : 56
    SYS_CLOSE : u64 : 57
    SYS_GETDENTS64 : u64 : 61
    SYS_READ : u64 : 63
    SYS_WRITE : u64 : 64
    SYS_NEWFSTATAT : u64 : 79
    SYS_FSTAT : u64 : 80
    SYS_RENAMEAT : u64 : 276

    O_DIRECTORY : u64 : 0x4000
    // struct stat on AArch64: 128 bytes, st_mode the low half of the third word, st_size the seventh
    STAT_MODE_WORD :: 2
}

#if OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64) {

    // openat and friends: relative paths start from the current directory
    AT_FDCWD : u64 : 0xffff_ffff_ffff_ff9c
    AT_REMOVEDIR : u64 : 0x200

    O_RDONLY : u64 : 0
    O_WRONLY : u64 : 1
    O_RDWR : u64 : 2
    O_CREAT : u64 : 0x40
    O_TRUNC : u64 : 0x200
    O_APPEND : u64 : 0x400
    O_CLOEXEC : u64 : 0x80000

    // A path's bytes and its terminator
    PATH_BUFFER_SIZE :: 4097

    // struct stat, as large as x86-64's, with st_size the seventh word on both
    Stat :: struct {
        words : u64[18],
    }
    S_IFMT : u32 : 0xf000
    S_IFDIR : u32 : 0x4000

    // A system call's result, which is -errno when it fails.
    failed :: fn(result: u64) -> bool {
        return result > 0xffff_ffff_ffff_f000
    }

    // The OsError for a failed system call's result.
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

    // path with a terminator in buffer, or false if it doesn't fit or holds a 0 byte.
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

    system_open :: fn(path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        return open_at(AT_FDCWD, path, mode)
    }

    // The file at path, from the directory at, as system_open opens it.
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

    system_open_in :: fn(directory: Directory, path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        return open_at(directory.handle, path, mode)
    }

    // A directory, as a file descriptor of its own, which reads nothing: what the *at calls start from.
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

    system_open_directory :: fn(path: string) -> (directory : Directory, error : OsError?) {
        return open_directory_at(AT_FDCWD, path)
    }

    system_working_directory :: fn() -> (directory : Directory, error : OsError?) {
        return open_directory_at(AT_FDCWD, ".")
    }

    system_open_directory_in :: fn(directory: Directory, path: string) -> (opened : Directory, error : OsError?) {
        return open_directory_at(directory.handle, path)
    }

    system_close_directory :: fn(directory: Directory) {
        runtime.linux_syscall(SYS_CLOSE, directory.handle)
    }

    system_close :: fn(file: File) {
        runtime.linux_syscall(SYS_CLOSE, file.handle)
    }

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

    system_file_size :: fn(file: File) -> (size : u64, error : OsError?) {
        status : Stat
        result :: runtime.linux_syscall(SYS_FSTAT, file.handle, cast[u64](&status))
        if failed(result) {
            return 0, error_of(result)
        }
        return status.words[6], null
    }

    system_delete_file :: fn(path: string) -> OsError? {
        return unlink_at(AT_FDCWD, path, 0)
    }

    system_delete_file_in :: fn(directory: Directory, path: string) -> OsError? {
        return unlink_at(directory.handle, path, 0)
    }

    system_remove_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        return unlink_at(directory.handle, path, AT_REMOVEDIR)
    }

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

    system_rename :: fn(from: string, to: string) -> OsError? {
        return rename_at(AT_FDCWD, from, to)
    }

    system_rename_in :: fn(directory: Directory, from: string, to: string) -> OsError? {
        return rename_at(directory.handle, from, to)
    }

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

    system_path_kind :: fn(path: string) -> PathKind {
        return path_kind_at(AT_FDCWD, path)
    }

    system_path_kind_in :: fn(directory: Directory, path: string) -> PathKind {
        return path_kind_at(directory.handle, path)
    }

    path_kind_at :: fn(at: u64, path: string) -> PathKind {
        buffer : u8[PATH_BUFFER_SIZE]
        if !terminated(path, buffer) {
            return .NOTHING
        }
        return kind_at(at, cast[rawptr](&buffer[0]))
    }

    system_make_directory :: fn(path: string) -> OsError? {
        return make_directory_at(AT_FDCWD, path)
    }

    system_make_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        return make_directory_at(directory.handle, path)
    }

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
    DT_UNKNOWN : u8 : 0
    DT_DIR : u8 : 4

    system_list_directory :: fn(path: string, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        return list_at(AT_FDCWD, path, entries, allocator)
    }

    // A path of "" is the directory itself, opened again for its own listing.
    system_list_directory_in :: fn(directory: Directory, path: string, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        return list_at(directory.handle, if path.count == 0 { "." } else { path }, entries, allocator)
    }

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

    // What name, terminated, is in the open folder directory: for file systems getdents64 gives no types for.
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
