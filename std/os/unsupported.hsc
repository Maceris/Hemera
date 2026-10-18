package os

import runtime from "base"

// Targets without a file system or environment, like OS == .None: everything is Unsupported.
#if OS != .Windows && !(OS == .Linux && TARGET_ARCH == .x86_64) {
    system_get_environment :: fn(name: string, allocator: runtime.Allocator) -> (value #unrestricted : string, error : OsError?) {
        return "", OsError.Unsupported
    }

    system_open :: fn(path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        return File.{0}, OsError.Unsupported
    }

    system_close :: fn(file: File) {}

    system_read :: fn(file: File, buffer: mut u8[]) -> (count : usize, error : OsError?) {
        return 0, OsError.Unsupported
    }

    system_write :: fn(file: File, bytes: rawptr, count: usize) -> (written : usize, error : OsError?) {
        return 0, OsError.Unsupported
    }

    system_file_size :: fn(file: File) -> (size : u64, error : OsError?) {
        return 0, OsError.Unsupported
    }

    system_delete_file :: fn(path: string) -> OsError? {
        return OsError.Unsupported
    }

    system_rename :: fn(from: string, to: string) -> OsError? {
        return OsError.Unsupported
    }

    system_path_kind :: fn(path: string) -> PathKind {
        return .NOTHING
    }

    system_make_directory :: fn(path: string) -> OsError? {
        return OsError.Unsupported
    }

    system_remove_directory :: fn(path: string) -> OsError? {
        return OsError.Unsupported
    }

    system_list_directory :: fn(path: string, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        return OsError.Unsupported
    }

    system_current_directory :: fn(allocator: runtime.Allocator) -> (path #unrestricted : string, error : OsError?) {
        return "", OsError.Unsupported
    }

    system_set_current_directory :: fn(path: string) -> OsError? {
        return OsError.Unsupported
    }
}
