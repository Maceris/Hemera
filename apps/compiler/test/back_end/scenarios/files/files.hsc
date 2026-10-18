/*
 * std/os in a hosted program: its arguments, an environment variable, and files and folders in a
 * folder it makes in the current directory and removes again. The test runs it as
 *
 *     files alpha "two words" ""
 *
 * with HEMERA_FILES_TEST set to "héllo", and main returns 42 if everything worked, or the number
 * of the first check that failed.
 */
package files_test

import runtime from "base"
import os from "std"
import strings from "std"

FOLDER :: "hemera_files_test"

check_arguments :: fn() -> int {
    arguments :: os.arguments()
    if arguments.count != 4 {
        return 1
    }
    if !strings.ends_with(arguments[0], "files") && !strings.ends_with(arguments[0], "files.exe") {
        return 2
    }
    if !strings.equal(arguments[1], "alpha") || !strings.equal(arguments[2], "two words") || arguments[3].count != 0 {
        return 3
    }
    // The same view each time
    if os.arguments().data != arguments.data {
        return 4
    }
    return 0
}

check_environment :: fn() -> int {
    value :: os.get_environment("HEMERA_FILES_TEST") or_else ""
    if !strings.equal(value, "héllo") {
        return 1
    }
    strings.free_string(value)
    match os.get_environment("HEMERA_FILES_TEST_NOT_SET") {
        case Ok(_) => return 2
        case Error(error) => {
            if error != .NotFound {
                return 2
            }
        }
    }
    return 0
}

OsError :: os.OsError

empty_listing :: fn() -> os.DirectoryEntry[..] {
    empty : os.DirectoryEntry[..]
    return empty
}

check_files :: fn() -> int {
    if os.exists(FOLDER) {
        return 1
    }
    if os.make_directory(FOLDER) != null || !os.is_directory(FOLDER) {
        return 2
    }
    if os.make_directory(FOLDER) != OsError.AlreadyExists {
        return 3
    }
    if os.set_current_directory(FOLDER) != null {
        return 4
    }
    inside :: os.current_directory() or_else ""
    if !strings.ends_with(inside, FOLDER) {
        return 5
    }
    strings.free_string(inside)

    // Writing, appending and reading back
    if os.write_entire_file("notes.txt", "first line\n") != null {
        return 6
    }
    match os.open("notes.txt", .APPEND) {
        case Ok(appending) => {
            failed :: os.write(appending, "second line\n") != null
            os.close(appending)
            if failed {
                return 7
            }
        }
        case Error(_) => return 7
    }
    contents :: os.read_entire_file("notes.txt") or_else ""
    if !strings.equal(contents, "first line\nsecond line\n") {
        return 8
    }
    strings.free_string(contents)
    match os.open("notes.txt", .READ) {
        case Ok(opened) => {
            size :: os.file_size(opened) or_else 0
            // A buffer smaller than the file: two reads, then the end
            buffer : u8[16]
            first :: os.read(opened, buffer) or_else 100
            second :: os.read(opened, buffer) or_else 100
            end :: os.read(opened, buffer) or_else 100
            os.close(opened)
            if size != 23 {
                return 9
            }
            if first != 16 || second != 7 || end != 0 {
                return 10
            }
        }
        case Error(_) => return 9
    }
    match os.open("missing.txt", .READ) {
        case Ok(_) => return 11
        case Error(error) => {
            if error != .NotFound {
                return 11
            }
        }
    }

    // Renaming, a folder inside, and listing
    if os.rename("notes.txt", "renamed.txt") != null || os.exists("notes.txt") || os.path_kind("renamed.txt") != .FILE {
        return 12
    }
    if os.make_directory("inner") != null || os.write_entire_file("ünïcode.txt", "") != null {
        return 13
    }
    entries :: os.list_directory(".") or_else empty_listing()
    if entries.count != 3 {
        return 14
    }
    found_inner := false
    found_unicode := false
    for entry in entries {
        if strings.equal(entry.name, "inner") && entry.is_directory {
            found_inner = true
        }
        if strings.equal(entry.name, "ünïcode.txt") && !entry.is_directory {
            found_unicode = true
        }
    }
    os.free_directory_listing(entries)
    if !found_inner || !found_unicode {
        return 15
    }

    // Cleaning up: a folder with something in it can't be removed
    if os.set_current_directory("..") != null {
        return 16
    }
    if os.remove_directory(FOLDER) != OsError.DirectoryNotEmpty {
        return 17
    }
    if os.delete_file("hemera_files_test/renamed.txt") != null || os.delete_file("hemera_files_test/ünïcode.txt") != null {
        return 18
    }
    if os.remove_directory("hemera_files_test/inner") != null || os.remove_directory(FOLDER) != null || os.exists(FOLDER) {
        return 19
    }
    return 0
}

main :: fn() -> int {
    failure := check_arguments()
    if failure != 0 {
        return 10 + failure
    }
    failure = check_environment()
    if failure != 0 {
        return 30 + failure
    }
    // Left over from a run that stopped part way
    os.delete_file("hemera_files_test/notes.txt")
    os.delete_file("hemera_files_test/renamed.txt")
    os.delete_file("hemera_files_test/ünïcode.txt")
    os.remove_directory("hemera_files_test/inner")
    os.remove_directory(FOLDER)
    failure = check_files()
    if failure != 0 {
        return 50 + failure
    }
    return 42
}
