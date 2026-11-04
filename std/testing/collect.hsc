package testing

import runtime from "base"
import compiler from "base"

/**
 * Make the table of a package's tests, for a runner: compile-time code, inserted in that package, where the table is
 * wanted, like tests :: #insert (testing.tests_of(compiler.load_package("."))).
 *
 * Each function the package marks #test is a Test, in the order the package declares them, named as the function and
 * reached by its name, so the table has to be inserted in the tests' own package. A #test function whose signature
 * isn't fn(t: ptr[mut T]) -> Outcome, or that's generic, is reported as an error at it, and left out.
 *
 * @param package The package whose tests these are, the inserting file's own, from compiler.load_package("."); none
 *     gives an empty table.
 * @return An expression, a Test[] literal; testing has to be imported, as testing, where it's inserted.
 */
tests_of :: fn(package: compiler.PackageInfo?) -> compiler.Code {
    found :: package or_return #code(testing.Test.[])
    // The tests' indices in found.functions, put in the order they're declared, as reflection gives another
    tests : usize[..]
    for &function, i in found.functions {
        if !function.is_test || !is_test_signature(function) {
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
    for index in tests {
        if index < found.functions.count {
            name :: found.functions[index].name
            reached :: compiler.name(name)
            runtime.array_add(&made, #code(testing.Test.{name = #insert name, run = #insert reached}))
        }
    }
    return #code(testing.Test.[#insert compiler.list(made)])
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
 * Check a #test function's signature, reporting it at the function if it isn't a test's.
 *
 * @param function The function, marked #test.
 * @return Whether it's fn(t: ptr[mut T]) -> Outcome and not generic.
 */
is_test_signature :: fn(function: ptr[compiler.FunctionInfo]) -> bool {
    right := function.generic_bindings.count == 0 && function.parameters.count == 1 && function.return_values.count == 1
    if right && function.parameters.count == 1 && function.return_values.count == 1 {
        right = function.parameters[0].type == ptr[mut T] && function.return_values[0].type == Outcome
    }
    if !right {
        compiler.report_error(function.location, "% is marked #test, so it has to be fn(t: ptr[mut testing.T]) -> testing.Outcome",
            function.name)
    }
    return right
}
