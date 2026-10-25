package os

import runtime from "base"

// Targets without processes to run or an environment, like OS == .None and SlopOS (whose programs start through launch).
#if OS != .Windows && !(OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64)) {
    system_run_process :: fn(program: string, arguments: string[], working_directory: string?, allocator: runtime.Allocator)
        -> (result #unrestricted : ProcessResult, error : ProcessError?) {

        empty : ProcessResult
        return empty, ProcessError.Unsupported
    }

    system_get_environment :: fn(name: string, allocator: runtime.Allocator) -> (value #unrestricted : string, error : OsError?) {
        return "", OsError.Unsupported
    }
}

// Targets without a file system, like OS == .None: SlopOS's files are its file protocols (slop_os_files.hsc).
#if OS != .Windows && OS != .SlopOS && !(OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64)) {
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

    system_open_directory :: fn(path: string) -> (directory : Directory, error : OsError?) {
        return Directory.{0}, OsError.Unsupported
    }

    system_working_directory :: fn() -> (directory : Directory, error : OsError?) {
        return Directory.{0}, OsError.Unsupported
    }

    system_open_directory_in :: fn(directory: Directory, path: string) -> (opened : Directory, error : OsError?) {
        return Directory.{0}, OsError.Unsupported
    }

    system_close_directory :: fn(directory: Directory) {}

    system_open_in :: fn(directory: Directory, path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        return File.{0}, OsError.Unsupported
    }

    system_delete_file_in :: fn(directory: Directory, path: string) -> OsError? {
        return OsError.Unsupported
    }

    system_rename_in :: fn(directory: Directory, from: string, to: string) -> OsError? {
        return OsError.Unsupported
    }

    system_path_kind_in :: fn(directory: Directory, path: string) -> PathKind {
        return .NOTHING
    }

    system_make_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        return OsError.Unsupported
    }

    system_remove_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        return OsError.Unsupported
    }

    system_list_directory_in :: fn(directory: Directory, path: string, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        return OsError.Unsupported
    }
}
