/*
 * std/os in a hosted program: its arguments, an environment variable, files and folders in a folder it makes in
 * the current directory and removes again, and the same through an open directory, which keeps working after the
 * folder it is is renamed. The test runs it as
 *
 *     files alpha "two words" ""
 *
 * with HEMERA_FILES_TEST set to "héllo", so it keeps a main of its own, which runs its #test functions, reporting to
 * standard output, and returns 42 if they all passed.
 */
package files_test

import compiler from "base"
import runtime from "base"
import os from "std"
import strings from "std"
import testing from "std"

FOLDER :: "hemera_files_test"

takes_its_arguments #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    arguments :: os.arguments()
    testing.require_eq(t, arguments.count, 4, "the program's path, then the three arguments the test gives it")?
    if arguments.count < 4 {
        return .Ok
    }
    testing.expect(t, strings.ends_with(arguments[0], "files") || strings.ends_with(arguments[0], "files.exe"),
        "the first argument is the program's own path")
    testing.expect_eq(t, arguments[1], "alpha", "a plain argument is given as it is")
    testing.expect_eq(t, arguments[2], "two words", "a quoted argument is one, without its quotes")
    testing.expect_eq(t, arguments[3].count, 0, "an empty quoted argument is an empty string, not left out")
    testing.expect(t, os.arguments().data == arguments.data, "arguments gives the same view each time")
    return .Ok
}

reads_the_environment #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    found :: os.get_environment("HEMERA_FILES_TEST")
    value :: testing.require_ok(t, found, "the test sets HEMERA_FILES_TEST")?
    testing.expect_eq(t, value, "héllo", "a value beyond ASCII comes back as UTF-8")
    strings.free_string(value)
    testing.expect_error(t, os.get_environment("HEMERA_FILES_TEST_NOT_SET"), OsError.NotFound, "nothing sets that variable")
    return .Ok
}

OsError :: os.OsError

empty_listing :: fn() -> os.DirectoryEntry[..] {
    empty : os.DirectoryEntry[..]
    return empty
}

works_with_files_and_folders #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Left over from a run that stopped part way
    os.delete_file("hemera_files_test/notes.txt")
    os.delete_file("hemera_files_test/renamed.txt")
    os.delete_file("hemera_files_test/ünïcode.txt")
    os.remove_directory("hemera_files_test/inner")
    os.remove_directory(FOLDER)
    testing.require(t, !os.exists(FOLDER), "anything a run before left is cleared away")?
    testing.require_none(t, os.make_directory(FOLDER), "the current directory can be written to")?
    testing.expect(t, os.is_directory(FOLDER), "what make_directory made is a folder")
    testing.expect_eq(t, os.make_directory(FOLDER), cast[OsError?](OsError.AlreadyExists), "the folder is there already")
    testing.require_none(t, os.set_current_directory(FOLDER), "the folder just made can be gone into")?
    in_folder :: works_in_the_folder(t)
    testing.require_none(t, os.set_current_directory(".."), "the folder above is where the test started")?
    in_folder?
    // Cleaning up: a folder with something in it can't be removed
    testing.expect_eq(t, os.remove_directory(FOLDER), cast[OsError?](OsError.DirectoryNotEmpty), "the folder still has files and a folder in it")
    testing.expect_none(t, os.delete_file("hemera_files_test/renamed.txt"), "the renamed file is there to delete")
    testing.expect_none(t, os.delete_file("hemera_files_test/ünïcode.txt"), "a file named beyond ASCII is deleted by its name")
    testing.expect_none(t, os.remove_directory("hemera_files_test/inner"), "the empty folder inside is removed")
    testing.expect_none(t, os.remove_directory(FOLDER), "the folder, empty now, is removed")
    testing.expect(t, !os.exists(FOLDER), "a removed folder is gone")
    return .Ok
}

/*
 * The part of works_with_files_and_folders inside FOLDER, the current directory: writing, appending and reading back,
 * renaming, a folder inside, and listing.
 */
works_in_the_folder :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    current :: os.current_directory()
    inside :: testing.require_ok(t, current, "the current directory can be read")?
    testing.expect(t, strings.ends_with(inside, FOLDER), "the current directory is the folder gone into")
    strings.free_string(inside)

    // Writing, appending and reading back
    testing.require_none(t, os.write_entire_file("notes.txt", "first line\n"), "a new file can be written in the folder")?
    opened_to_append :: os.open("notes.txt", .APPEND)
    appending :: testing.require_ok(t, opened_to_append, "the file just written can be opened to append to")?
    testing.expect_none(t, os.write(appending, "second line\n"), "an open file can be appended to")
    os.close(appending)
    read :: os.read_entire_file("notes.txt")
    contents :: testing.require_ok(t, read, "the file can be read back")?
    testing.expect_eq(t, contents, "first line\nsecond line\n", "what was appended follows what was written")
    strings.free_string(contents)
    opened_to_read :: os.open("notes.txt", .READ)
    opened :: testing.require_ok(t, opened_to_read, "the file can be opened to read")?
    size :: os.file_size(opened)
    // A buffer smaller than the file: two reads, then the end
    buffer : u8[16]
    first :: os.read(opened, buffer) or_else 100
    second :: os.read(opened, buffer) or_else 100
    end :: os.read(opened, buffer) or_else 100
    os.close(opened)
    testing.expect_eq(t, size or_else 0, 23, "the file's size is both lines'")
    testing.expect_eq(t, first, 16, "a read fills the buffer when there's more than it holds")
    testing.expect_eq(t, second, 7, "the next read gives the rest")
    testing.expect_eq(t, end, 0, "a read at the end gives nothing")
    // Two appending at once: every write goes at the end, not where the other's started
    opened_first :: os.open("notes.txt", .APPEND)
    first_appender :: testing.require_ok(t, opened_first, "a file can be opened to append to")?
    opened_second :: os.open("notes.txt", .APPEND)
    second_appender :: testing.require_ok(t, opened_second, "a file can be opened to append to twice at once")?
    testing.expect_none(t, os.write(first_appender, "a"), "the first appender appends")
    testing.expect_none(t, os.write(second_appender, "b"), "the second appender appends")
    testing.expect_none(t, os.write(first_appender, "c"), "the first appender appends again")
    os.close(first_appender)
    os.close(second_appender)
    read_both :: os.read_entire_file("notes.txt")
    both :: testing.require_ok(t, read_both, "the file can be read back")?
    testing.expect_eq(t, both, "first line\nsecond line\nabc", "each write went at the end, wherever the other left it")
    strings.free_string(both)
    testing.expect_error(t, os.open("missing.txt", .READ), OsError.NotFound, "nothing made missing.txt")

    // Renaming, a folder inside, and listing
    testing.expect_none(t, os.rename("notes.txt", "renamed.txt"), "a file can be renamed in its folder")
    testing.expect(t, !os.exists("notes.txt"), "a renamed file isn't under its old name")
    testing.expect(t, os.path_kind("renamed.txt") == .FILE, "a renamed file is under its new name")
    testing.require_none(t, os.make_directory("inner"), "a folder can be made inside")?
    testing.require_none(t, os.write_entire_file("ünïcode.txt", ""), "a file can be named beyond ASCII")?
    listing :: os.list_directory(".")
    entries :: testing.require_ok(t, listing, "the folder can be listed")?
    testing.expect_eq(t, entries.count, 3, "the renamed file, the folder inside and the file named beyond ASCII")
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
    testing.expect(t, found_inner, "the folder inside is listed as a folder")
    testing.expect(t, found_unicode, "the file named beyond ASCII is listed by its name, as a file")
    return .Ok
}

MOVING :: "hemera_directory_test"
MOVED :: "hemera_directory_moved"

// Through an open directory: paths beneath it, which reach it after it's renamed, and none above it.
works_through_an_open_directory #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Left over from a run that stopped part way
    os.delete_file("hemera_directory_moved/inside.txt")
    os.delete_file("hemera_directory_moved/ünïcode.txt")
    os.delete_file("hemera_directory_moved/sub/deeper.txt")
    os.delete_file("hemera_directory_moved/sub/moved.txt")
    os.remove_directory("hemera_directory_moved/sub")
    os.remove_directory(MOVED)
    os.remove_directory(MOVING)
    testing.require_none(t, os.make_directory(MOVING), "the current directory can be written to")?
    opened_directory :: os.open_directory(MOVING)
    directory :: testing.require_ok(t, opened_directory, "the folder just made can be opened")?
    testing.require_none(t, os.write_entire_file_in(directory, "inside.txt", "beneath"), "a file can be written beneath it")?
    testing.require_none(t, os.make_directory_in(directory, "sub"), "a folder can be made beneath it")?
    testing.expect_eq(t, os.make_directory_in(directory, "sub"), cast[OsError?](OsError.AlreadyExists), "sub is there already")
    testing.expect_some(t, os.make_directory_in(directory, "none/sub"), "a folder can't be made in one that isn't there")
    // Renamed, the directory is still the one open
    testing.require_none(t, os.rename(MOVING, MOVED), "an open directory can be renamed")?
    testing.expect(t, !os.exists(MOVING), "a renamed folder isn't under its old name")
    read :: os.read_entire_file_in(directory, "inside.txt")
    contents :: testing.require_ok(t, read, "the file beneath it is still reached through it, renamed")?
    testing.expect_eq(t, contents, "beneath", "it's the file that was written")
    strings.free_string(contents)
    testing.expect(t, os.path_kind_in(directory, "sub") == .DIRECTORY, "sub, beneath it, is a folder")
    testing.expect(t, os.path_kind_in(directory, "inside.txt") == .FILE, "inside.txt, beneath it, is a file")
    testing.expect(t, os.path_kind_in(directory, "nothing") == .NOTHING, "nothing made anything named nothing")
    // A name beyond ASCII beneath it: made, found, listed by its name, and deleted
    testing.expect_none(t, os.write_entire_file_in(directory, "ünïcode.txt", ""), "a file beneath it can be named beyond ASCII")
    testing.expect(t, os.path_kind_in(directory, "ünïcode.txt") == .FILE, "the file named beyond ASCII is found by its name")
    listing :: os.list_directory_in(directory, "")
    listed :: testing.require_ok(t, listing, "the directory can be listed")?
    found_unicode := false
    for entry in listed {
        if strings.equal(entry.name, "ünïcode.txt") {
            found_unicode = true
        }
    }
    os.free_directory_listing(listed)
    testing.expect(t, found_unicode, "the file named beyond ASCII is listed by its name")
    testing.expect_none(t, os.delete_file_in(directory, "ünïcode.txt"), "the file named beyond ASCII is deleted by its name")
    testing.expect(t, os.path_kind_in(directory, "ünïcode.txt") == .NOTHING, "a deleted file is gone")
    opened_sub :: os.open_directory_in(directory, "sub")
    sub :: testing.require_ok(t, opened_sub, "a directory beneath an open one can be opened")?
    testing.require_none(t, os.write_entire_file_in(sub, "deeper.txt", "deeper"), "a file can be written beneath that")?
    opened_to_append :: os.open_in(directory, "sub/deeper.txt", .APPEND)
    appending :: testing.require_ok(t, opened_to_append, "a path two levels down can be opened to append to")?
    testing.expect_none(t, os.write(appending, " still"), "the file opened through a path can be appended to")
    os.close(appending)
    read_deeper :: os.read_entire_file_in(sub, "deeper.txt")
    deeper :: testing.require_ok(t, read_deeper, "the file can be read back through the directory beneath")?
    testing.expect_eq(t, deeper, "deeper still", "what was appended through one directory is read through the other")
    strings.free_string(deeper)
    // Nothing above it, nor absolute
    for refused in string.["../hemera_directory_moved/inside.txt", "/inside.txt", "sub//deeper.txt", "./inside.txt", "sub/..", ""] {
        opened :: os.open_in(directory, refused, .READ)
        if !testing.expect_error(t, opened, OsError.InvalidPath, "a path that isn't plainly beneath the directory is refused") {
            match opened {
                case Ok(file) => os.close(file)
                case Error(_) => {}
            }
        }
    }
    // Listing it, and a directory beneath it
    listing_all :: os.list_directory_in(directory, "")
    entries :: testing.require_ok(t, listing_all, "the directory can be listed")?
    testing.expect_eq(t, entries.count, 2, "inside.txt and sub are beneath it")
    os.free_directory_listing(entries)
    listing_beneath :: os.list_directory_in(directory, "sub")
    beneath :: testing.require_ok(t, listing_beneath, "a directory beneath it can be listed")?
    testing.expect_eq(t, beneath.count, 1, "deeper.txt alone is in sub")
    if beneath.count > 0 {
        testing.expect_eq(t, beneath[0].name, "deeper.txt", "the one file in sub is deeper.txt")
    }
    os.free_directory_listing(beneath)
    // Moved within it, then removed
    testing.expect_none(t, os.rename_in(directory, "inside.txt", "sub/moved.txt"), "a file can be moved within the directory")
    testing.expect(t, os.path_kind_in(directory, "sub/moved.txt") == .FILE, "a moved file is where it was moved to")
    testing.expect_eq(t, os.remove_directory_in(directory, "sub"), cast[OsError?](OsError.DirectoryNotEmpty),
        "sub still has files in it")
    testing.expect_none(t, os.delete_file_in(directory, "sub/moved.txt"), "the moved file can be deleted through a path")
    testing.expect_none(t, os.delete_file_in(sub, "deeper.txt"), "the file in sub can be deleted through sub")
    os.close_directory(sub)
    testing.expect_none(t, os.remove_directory_in(directory, "sub"), "sub, empty now, is removed")
    os.close_directory(directory)
    // The working directory, which the moved one is in
    opened_working :: os.working_directory()
    working :: testing.require_ok(t, opened_working, "the working directory can be opened")?
    kind :: os.path_kind_in(working, MOVED)
    os.close_directory(working)
    testing.expect(t, kind == .DIRECTORY, "the renamed folder is in the working directory under its new name")
    testing.expect_none(t, os.remove_directory(MOVED), "the renamed folder, empty now, is removed")
    return .Ok
}

/**
 * Run the tests, reporting to standard output.
 *
 * @return 42 if every test passed, which the harness checks for; 1 if any failed.
 */
main :: fn() -> int {
    failed :: testing.run(#insert testing.tests_of(compiler.load_package(".")), testing.STANDARD_OUTPUT)
    return if failed == 0 { 42 } else { 1 }
}
