package program

import compiler from "base"
import intrinsics from "base"
import testing from "std"
import maths from "../maths"

/*
 * Calls a typed library's exports through the library, which the runtime loads and checks before main. main runs the
 * tests, and returns 42 if every call through the library gave what it should, or 1.
 */

calls_exports_through_the_library #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, maths.add(40, 2), 42, "an export taking and giving numbers")
    text :: maths.repeat("ab", 3)
    testing.expect_eq(t, text, "ababab", "an export giving a string it made")
    pair :: maths.ordered(9, 4)
    testing.expect(t, pair.low == 4 && pair.high == 9, "an export giving a struct, its members in the library's order")
    testing.expect_eq(t, pair.sum, 13, "the struct's last member")
    // A function value of an export calls through the library too
    adds := maths.add
    testing.expect_eq(t, adds(1, 2), 3, "a function value of an export calls through the library")
    testing.expect_eq(t, maths.twice(21), 42, "a generic of the library's, made in the program")
    return .Ok
}

shares_the_process_state_with_the_library #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, maths.process_state_address(), cast[u64](cast[uintptr](intrinsics.process_state())),
        "the library's base uses the program's process state, not one of its own")
    return .Ok
}

/**
 * Run the tests, reporting to standard output, which the harness doesn't compare.
 *
 * @return 42 if every test passed; 1 if any failed.
 */
main :: fn() -> int {
    if testing.run(#insert testing.tests_of(compiler.load_package(".")), testing.STANDARD_OUTPUT) != 0 {
        return 1
    }
    return 42
}
