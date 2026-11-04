package os

import runtime from "base"

/*
 * Targets without processes to run or an environment, like OS == .None and SlopOS (whose programs start through
 * launch).
 */
#if OS != .Windows && !(OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64)) {
    /**
     * Fail to run a program, as there's nothing to run it with.
     *
     * @param program The program, which isn't looked at.
     * @param arguments Its arguments, which aren't looked at.
     * @param working_directory Where it would start, which isn't looked at.
     * @param allocator Where the output would be allocated; nothing is.
     * @return result An empty ProcessResult, owning nothing.
     * @return error Always Unsupported.
     */
    system_run_process :: fn(program: string, arguments: string[], working_directory: string?, allocator: runtime.Allocator)
        -> (result #unrestricted : ProcessResult, error : ProcessError?) {

        empty : ProcessResult
        return empty, ProcessError.Unsupported
    }

    /**
     * Fail to look up an environment variable, as there's no environment.
     *
     * @param name The variable's name, which isn't looked at.
     * @param allocator Where the value would be allocated; nothing is.
     * @return value Always "", owning nothing.
     * @return error Always Unsupported.
     */
    system_get_environment :: fn(name: string, allocator: runtime.Allocator) -> (value #unrestricted : string, error : OsError?) {
        return "", OsError.Unsupported
    }
}

// Targets without a file system, like OS == .None: SlopOS's files are its file protocols (slop_os_files.hsc).
#if OS != .Windows && OS != .SlopOS && !(OS == .Linux && (TARGET_ARCH == .x86_64 || TARGET_ARCH == .arm64)) {
    /**
     * Fail to open a file, as there's no file system.
     *
     * @param path The file's path, which isn't looked at.
     * @param mode How it would be opened, which isn't looked at.
     * @return file Always the zero File, which close ignores.
     * @return error Always Unsupported.
     */
    system_open :: fn(path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        return File.{0}, OsError.Unsupported
    }

    /**
     * Close nothing: no file can have been opened.
     *
     * @param file A File, which can only be the zero one; ignored.
     */
    system_close :: fn(file: File) {}

    /**
     * Fail to read, as there's no file system.
     *
     * @param file The file, which isn't looked at.
     * @param buffer Where bytes would go, left as it is.
     * @return count Always 0.
     * @return error Always Unsupported.
     */
    system_read :: fn(file: File, buffer: mut u8[]) -> (count : usize, error : OsError?) {
        return 0, OsError.Unsupported
    }

    /**
     * Fail to write, as there's no file system.
     *
     * @param file The file, which isn't looked at.
     * @param bytes The bytes, which aren't read.
     * @param count How many bytes there are, in bytes; ignored.
     * @return written Always 0.
     * @return error Always Unsupported.
     */
    system_write :: fn(file: File, bytes: rawptr, count: usize) -> (written : usize, error : OsError?) {
        return 0, OsError.Unsupported
    }

    /**
     * Fail to give a file's size, as there's no file system.
     *
     * @param file The file, which isn't looked at.
     * @return size Always 0.
     * @return error Always Unsupported.
     */
    system_file_size :: fn(file: File) -> (size : u64, error : OsError?) {
        return 0, OsError.Unsupported
    }

    /**
     * Fail to delete a file, as there's no file system.
     *
     * @param path The file's path, which isn't looked at.
     * @return Always Unsupported.
     */
    system_delete_file :: fn(path: string) -> OsError? {
        return OsError.Unsupported
    }

    /**
     * Fail to rename, as there's no file system.
     *
     * @param from The path to move, which isn't looked at.
     * @param to Where it would go, which isn't looked at.
     * @return Always Unsupported.
     */
    system_rename :: fn(from: string, to: string) -> OsError? {
        return OsError.Unsupported
    }

    /**
     * Find nothing at a path, as there's no file system.
     *
     * @param path The path, which isn't looked at.
     * @return Always NOTHING.
     */
    system_path_kind :: fn(path: string) -> PathKind {
        return .NOTHING
    }

    /**
     * Fail to make a directory, as there's no file system.
     *
     * @param path The directory's path, which isn't looked at.
     * @return Always Unsupported.
     */
    system_make_directory :: fn(path: string) -> OsError? {
        return OsError.Unsupported
    }

    /**
     * Fail to remove a directory, as there's no file system.
     *
     * @param path The directory's path, which isn't looked at.
     * @return Always Unsupported.
     */
    system_remove_directory :: fn(path: string) -> OsError? {
        return OsError.Unsupported
    }

    /**
     * Fail to list a directory, as there's no file system.
     *
     * @param path The directory's path, which isn't looked at.
     * @param entries Where entries would be added, left as it is.
     * @param allocator Where names would be allocated; nothing is.
     * @return Always Unsupported.
     */
    system_list_directory :: fn(path: string, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        return OsError.Unsupported
    }

    /**
     * Fail to give the current directory, as there's no file system.
     *
     * @param allocator Where the path would be allocated; nothing is.
     * @return path Always "", owning nothing.
     * @return error Always Unsupported.
     */
    system_current_directory :: fn(allocator: runtime.Allocator) -> (path #unrestricted : string, error : OsError?) {
        return "", OsError.Unsupported
    }

    /**
     * Fail to change the current directory, as there's no file system.
     *
     * @param path The directory's path, which isn't looked at.
     * @return Always Unsupported.
     */
    system_set_current_directory :: fn(path: string) -> OsError? {
        return OsError.Unsupported
    }

    /**
     * Fail to open a directory, as there's no file system.
     *
     * @param path The directory's path, which isn't looked at.
     * @return directory Always the zero Directory, which close_directory ignores.
     * @return error Always Unsupported.
     */
    system_open_directory :: fn(path: string) -> (directory : Directory, error : OsError?) {
        return Directory.{0}, OsError.Unsupported
    }

    /**
     * Fail to open the working directory, as there's no file system.
     *
     * @return directory Always the zero Directory, which close_directory ignores.
     * @return error Always Unsupported.
     */
    system_working_directory :: fn() -> (directory : Directory, error : OsError?) {
        return Directory.{0}, OsError.Unsupported
    }

    /**
     * Fail to open a directory beneath another, as there's no file system.
     *
     * @param directory The directory, which can only be the zero one; ignored.
     * @param path The path beneath it, which isn't looked at.
     * @return opened Always the zero Directory, which close_directory ignores.
     * @return error Always Unsupported.
     */
    system_open_directory_in :: fn(directory: Directory, path: string) -> (opened : Directory, error : OsError?) {
        return Directory.{0}, OsError.Unsupported
    }

    /**
     * Close nothing: no directory can have been opened.
     *
     * @param directory A Directory, which can only be the zero one; ignored.
     */
    system_close_directory :: fn(directory: Directory) {}

    /**
     * Fail to open a file beneath a directory, as there's no file system.
     *
     * @param directory The directory, which can only be the zero one; ignored.
     * @param path The path beneath it, which isn't looked at.
     * @param mode How it would be opened, which isn't looked at.
     * @return file Always the zero File, which close ignores.
     * @return error Always Unsupported.
     */
    system_open_in :: fn(directory: Directory, path: string, mode: OpenMode) -> (file : File, error : OsError?) {
        return File.{0}, OsError.Unsupported
    }

    /**
     * Fail to delete a file beneath a directory, as there's no file system.
     *
     * @param directory The directory, which can only be the zero one; ignored.
     * @param path The path beneath it, which isn't looked at.
     * @return Always Unsupported.
     */
    system_delete_file_in :: fn(directory: Directory, path: string) -> OsError? {
        return OsError.Unsupported
    }

    /**
     * Fail to rename beneath a directory, as there's no file system.
     *
     * @param directory The directory, which can only be the zero one; ignored.
     * @param from The path to move, which isn't looked at.
     * @param to Where it would go, which isn't looked at.
     * @return Always Unsupported.
     */
    system_rename_in :: fn(directory: Directory, from: string, to: string) -> OsError? {
        return OsError.Unsupported
    }

    /**
     * Find nothing at a path beneath a directory, as there's no file system.
     *
     * @param directory The directory, which can only be the zero one; ignored.
     * @param path The path beneath it, which isn't looked at.
     * @return Always NOTHING.
     */
    system_path_kind_in :: fn(directory: Directory, path: string) -> PathKind {
        return .NOTHING
    }

    /**
     * Fail to make a directory beneath another, as there's no file system.
     *
     * @param directory The directory, which can only be the zero one; ignored.
     * @param path The path beneath it, which isn't looked at.
     * @return Always Unsupported.
     */
    system_make_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        return OsError.Unsupported
    }

    /**
     * Fail to remove a directory beneath another, as there's no file system.
     *
     * @param directory The directory, which can only be the zero one; ignored.
     * @param path The path beneath it, which isn't looked at.
     * @return Always Unsupported.
     */
    system_remove_directory_in :: fn(directory: Directory, path: string) -> OsError? {
        return OsError.Unsupported
    }

    /**
     * Fail to list a directory beneath another, as there's no file system.
     *
     * @param directory The directory, which can only be the zero one; ignored.
     * @param path The path beneath it, which isn't looked at.
     * @param entries Where entries would be added, left as it is.
     * @param allocator Where names would be allocated; nothing is.
     * @return Always Unsupported.
     */
    system_list_directory_in :: fn(directory: Directory, path: string, entries: ptr[mut DirectoryEntry[..]], allocator: runtime.Allocator) -> OsError? {
        return OsError.Unsupported
    }
}
