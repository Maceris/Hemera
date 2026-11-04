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
    made : compiler.Code[..]
    found :: package or_return #code(testing.Test.[])
    for &function in found.functions {
        if !function.is_test || !is_test_signature(function) {
            continue
        }
        reached :: compiler.name(function.name)
        runtime.array_add(&made, #code(testing.Test.{name = #insert function.name, run = #insert reached}))
    }
    return #code(testing.Test.[#insert compiler.list(made)])
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
