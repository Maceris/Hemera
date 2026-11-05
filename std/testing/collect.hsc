package testing

import runtime from "base"
import compiler from "base"
import reflection from "std"
import text_buffer from "std"

/**
 * Make the table of a package's tests, for a runner: compile-time code, inserted in that package, where the table is
 * wanted, like tests :: #insert (testing.tests_of(compiler.load_package("."))).
 *
 * Each function the package marks #test is a Test, in the order the package declares them, named as the function and
 * reached by its name, so the table has to be inserted in the tests' own package; its #tags(...) are its Test's tags,
 * named where it is, like SLOW or testing.SLOW. A property test, fn(t: ptr[mut T], source: ptr[mut Source]) ->
 * Outcome, is run through check_property, by a function the table's compute block declares for it. A #test(CASES)
 * function is a Test for each of its cases, in their order, named name[i], or name[<the case's name>] when its type has
 * a name string, each run by a function the compute block declares, which calls the test with it. A #test function
 * whose signature is none of these, fn(t: ptr[mut T], item: C) -> Outcome for cases a constant array of C included,
 * or that's generic, is reported as an error at it, and left out.
 *
 * @param package The package whose tests these are, the inserting file's own, from compiler.load_package("."); none
 *     gives an empty table.
 * @param file Only the tests declared in this file, by its name, like "accounts_check.hsc", or a path ending in it;
 *     empty for every file's, as a test package wants. One file's suits checks kept in one file of a bigger package.
 * @return An expression giving the Test[...] table; testing has to be imported, as testing, where it's inserted.
 */
tests_of :: fn(package: compiler.PackageInfo?, file: string = "") -> compiler.Code {
    found :: package or_return #code(testing.Test.[])
    // The tests' indices in found.functions, put in the order they're declared, as reflection gives another
    tests : usize[..]
    for &function, i in found.functions {
        if !function.is_test || !in_file(function.location.file_path, file) || !is_test_signature(function, found.constants) {
            continue
        }
        // After every test declared before it
        at : usize = 0
        for other in tests {
            if other < found.functions.count && declared_before(found.functions[other].location, function.location) {
                at += 1
            }
        }
        runtime.array_add(&tests, i)
        // Moved down from the end to at
        place := tests.count - 1
        loop {
            if place <= at || place >= tests.count {
                break
            }
            below :: place - 1
            moved :: tests[below]
            tests[below] = tests[place]
            if place < tests.count {
                tests[place] = moved
            }
            place = below
        }
    }
    made : compiler.Code[..]
    // Each case's function, for the tests over cases
    wrappers : compiler.Code[..]
    for index in tests {
        if index >= found.functions.count {
            continue
        }
        function :: &found.functions[index]
        // Its tags, as #tags names them, each a testing.Tag constant where the table goes, the rest of their room empty
        tags : compiler.Code[..]
        for tag in function.test_tags {
            runtime.array_add(&tags, tag)
        }
        if tags.count > MAX_TAGS {
            compiler.report_error(function.location, "% has % tags; a test can have at most %", function.name, tags.count, MAX_TAGS)
            continue
        }
        tag_count :: tags.count
        for index in tag_count..<MAX_TAGS {
            runtime.array_add(&tags, #code(testing.Tag.{}))
        }
        tag_list :: compiler.list(tags)
        if is_property(function) {
            property :: compiler.name(function.name)
            wrapper :: compiler.name(function.name, "_property")
            runtime.array_add(&wrappers, #code {
                #insert wrapper :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
                    return testing.check_property(t, #insert property)
                }
            })
            runtime.array_add(&made, entry(function.name, wrapper, tag_list, tag_count))
            continue
        }
        if function.test_cases.count == 0 {
            reached :: compiler.name(function.name)
            runtime.array_add(&made, entry(function.name, reached, tag_list, tag_count))
            continue
        }
        cases :: cases_of(found.constants, function.test_cases) or_else Cases.{}
        test :: compiler.name(function.name)
        list :: compiler.name(function.test_cases)
        for case_index in 0..<cases.count {
            storage : u8[64]
            number := text_buffer.make(storage)
            text_buffer.append_unsigned(&number, cast[u64](case_index))
            wrapper :: compiler.name(function.name, "_case_", text_buffer.as_string(&number))
            runtime.array_add(&wrappers, #code {
                #insert wrapper :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
                    return testing.run_case_at(t, #insert test, #insert list, #insert case_index)
                }
            })
            label :: case_label(function.name, &cases, case_index)
            runtime.array_add(&made, entry(label, wrapper, tag_list, tag_count))
        }
    }
    if wrappers.count == 0 {
        return #code(testing.Test.[#insert compiler.list(made)])
    }
    return #code(compute[testing.Test[#insert made.count]] {
        #insert compiler.list(wrappers)
        give testing.Test.[#insert compiler.list(made)]
    })
}

/**
 * Make a table's entry for a test.
 *
 * @param name The test's name, as it's reported.
 * @param run The code naming the function the runner calls.
 * @param tags The code of its tags, MAX_TAGS of them, those past count empty.
 * @param count How many tags it has.
 * @return The code of a testing.Test.
 */
entry :: fn(name: string, run: compiler.Code, tags: compiler.Code, count: usize) -> compiler.Code {
    if count == 0 {
        return #code(testing.Test.{name = #insert name, run = #insert run})
    }
    return #code(testing.Test.{name = #insert name, run = #insert run, tags = testing.Tag.[#insert tags], tag_count = #insert count})
}

/** A #test(CASES) function's cases, as compile-time code reads them from the constant. */
Cases :: struct {
    /** How many there are. */
    count : usize,
    /** Where the first is, in the constant's value; the rest follow, size bytes apart. */
    data : rawptr,
    /** Each case's size in bytes. */
    size : usize,
    /** Where in a case its name string is, in bytes, when its type has one. */
    name_offset : usize,
    /** Whether its type has a name string, which names its test. */
    named : bool,
    /** The cases' type, which the test's second parameter has to be. */
    type : type,
}

/**
 * Find a #test(CASES) function's cases: a constant of the package's, a fixed array.
 *
 * @param constants The package's constants, looked in.
 * @param name The constant's name, as #test gives it.
 * @return The cases; null if the package has no such constant, or it isn't a fixed array.
 */
cases_of :: fn(constants: compiler.ConstantInfo[], name: string) -> Cases? {
    for &constant in constants {
        if constant.name != name {
            continue
        }
        info :: reflection.unaliased(type_info_of(constant.type))
        if info.variant != .ARRAY {
            return null
        }
        array :: cast[ptr[compiler.TypeInfoArray]](info)
        if array.dimensions.count != 1 {
            return null
        }
        dimension :: array.dimensions[0]
        if dimension.type != .STATIC {
            return null
        }
        element :: reflection.unaliased(array.base_type)
        made := Cases.{count = dimension.count, data = constant.value.data, size = array.base_type.size,
            type = compiler.described_type(array.base_type)}
        if element.variant == .STRUCT {
            for member in cast[ptr[compiler.TypeInfoStruct]](element).members {
                if member.name == "name" && reflection.unaliased(member.member_type).variant == .STRING {
                    made.named = true
                    made.name_offset = member.offset
                }
            }
        }
        return made
    }
    return null
}

/**
 * Name a case's test: the test's name, then the case's name in brackets when its type has one, or its index.
 *
 * @param test The test function's name.
 * @param cases Its cases.
 * @param index Which case, from 0.
 * @return The name, from the context's allocator, lasting through the compilation.
 */
case_label :: fn(test: string, cases: ptr[Cases], index: usize) -> string {
    storage : u8[256]
    label := text_buffer.make(storage)
    text_buffer.append(&label, test)
    text_buffer.append(&label, "[")
    if cases.named {
        at :: cast[rawptr](cast[u64](cases.data) + cast[u64](index * cases.size + cases.name_offset))
        text_buffer.append(&label, cast[ptr[string]](at)^)
    }
    else {
        text_buffer.append_unsigned(&label, cast[u64](index))
    }
    text_buffer.append(&label, "]")
    // Copied out of the stack, for the code it goes into
    written :: text_buffer.as_string(&label)
    copy, error :: runtime.new_array(u8, written.count)
    if error != null || copy.count == 0 {
        return test
    }
    for character, i in written {
        if i < copy.count {
            copy[i] = cast[u8](character)
        }
    }
    return string_of(&copy[0], copy.count)
}

/**
 * Tell whether a function's file is the one asked for.
 *
 * @param path The function's file, as reflection gives it: a full path, with / or, on Windows, \ between its parts.
 * @param file The file asked for, by name or by a path's end with / between its parts; empty for any.
 * @return True if file is empty, is path, or is path's last parts, after a separator.
 */
in_file :: fn(path: string, file: string) -> bool {
    if file.count == 0 || path == file {
        return true
    }
    if file.count >= path.count {
        return false
    }
    start :: path.count - file.count
    if start == 0 || start > path.count || (path[start - 1] != '/' && path[start - 1] != '\\') {
        return false
    }
    // Each / of file matches either separator of path
    for character, i in file {
        at :: start + i
        if at >= path.count {
            return false
        }
        found :: path[at]
        if character == '/' {
            if found != '/' && found != '\\' {
                return false
            }
        }
        else if found != character {
            return false
        }
    }
    return true
}

/**
 * Tell whether one place is before another: in a file whose path sorts first, byte by byte, or earlier in the same one.
 *
 * @param a The place that may come first.
 * @param b The place it's compared with.
 * @return True if a comes before b.
 */
declared_before :: fn(a: runtime.SourceCodeLocation, b: runtime.SourceCodeLocation) -> bool {
    for character, i in a.file_path {
        if i >= b.file_path.count {
            return false
        }
        if character != b.file_path[i] {
            return cast[u8](character) < cast[u8](b.file_path[i])
        }
    }
    if a.file_path.count != b.file_path.count {
        return true
    }
    return a.line < b.line
}

/**
 * Tell whether a #test function is a property test: it takes a Source after its T, and has no cases.
 *
 * @param function The function, marked #test.
 * @return Whether its second parameter is a ptr[mut Source], and it isn't #test(CASES).
 */
is_property :: fn(function: ptr[compiler.FunctionInfo]) -> bool {
    return function.test_cases.count == 0 && function.parameters.count == 2 && function.parameters[1].type == ptr[mut Source]
}

/**
 * Check a #test function's signature, reporting it at the function if it isn't a test's.
 *
 * @param function The function, marked #test.
 * @param constants Its package's constants, where #test(CASES) finds its cases.
 * @return Whether it's fn(t: ptr[mut T]) -> Outcome, or with #test(CASES), fn(t: ptr[mut T], item: C) -> Outcome for
 *     CASES a constant fixed array of C; and not generic.
 */
is_test_signature :: fn(function: ptr[compiler.FunctionInfo], constants: compiler.ConstantInfo[]) -> bool {
    takes :: if function.test_cases.count == 0 && !is_property(function) { cast[usize](1) } else { cast[usize](2) }
    right := function.generic_bindings.count == 0 && function.parameters.count == takes && function.return_values.count == 1
    if right && function.parameters.count >= 1 && function.return_values.count == 1 {
        right = function.parameters[0].type == ptr[mut T] && function.return_values[0].type == Outcome
    }
    if function.test_cases.count == 0 {
        if !right {
            compiler.report_error(function.location, "% is marked #test, so it has to be fn(t: ptr[mut testing.T]) -> testing.Outcome, or for a property test, fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome",
                function.name)
        }
        return right
    }
    found :: cases_of(constants, function.test_cases)
    match found {
        case Some(cases) => {
            if right && function.parameters.count == 2 {
                right = function.parameters[1].type == cases.type
            }
            if !right {
                compiler.report_error(function.location,
                    "% is marked #test(%), so it has to be fn(t: ptr[mut testing.T], item: %) -> testing.Outcome", function.name,
                    function.test_cases, cases.type)
            }
            return right
        }
        case None => {
            compiler.report_error(function.location, "% is marked #test(%), which has to name a constant fixed array of its package's",
                function.name, function.test_cases)
            return false
        }
    }
}
