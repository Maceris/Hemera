/*
 * #test(CASES) (docs/testing.md, Tests Over Cases): a test run once for each case of a constant array, each its own
 * test, named by the case's name, or by its index for a type without one. One case fails on purpose, so this package's
 * tests end with one failed. main returns 42 if the report is what it should be.
 */
package test_cases

import runtime from "base"
import compiler from "base"
import testing from "std"

/** A case with a name: text, and its length. */
Measured :: struct {
    /** What the case is called, which names its test. */
    name : string,
    /** The text measured. */
    text : string,
    /** How long it should be, in bytes. */
    length : usize,
}

MEASURED :: Measured.[
    Measured.{name = "empty", text = "", length = 0},
    Measured.{name = "word", text = "word", length = 4},
    // Wrong on purpose: its test fails
    Measured.{name = "miscounted", text = "two", length = 2},
]

/** Cases without names: numbers, each named by its index. */
SQUARES :: int.[1, 4, 9]

measures_text #test(MEASURED) :: fn(t: ptr[mut testing.T], item: Measured) -> testing.Outcome {
    testing.expect_eq(t, item.text.count, item.length, "the text's length in bytes")
    return .Ok
}

squares_are_squares #test(SQUARES) :: fn(t: ptr[mut testing.T], item: int) -> testing.Outcome {
    root := 0
    loop {
        if root * root >= item {
            break
        }
        root += 1
    }
    testing.expect_eq(t, root * root, item, "a square's root, squared, is it")
    return .Ok
}

plain #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    return .Ok
}

EXPECTED :: "test measures_text[empty] ... ok\ntest measures_text[word] ... ok\ntest measures_text[miscounted] ... FAILED\n    test_cases.hsc:33: the text's length in bytes\n        expected 2, got 3\ntest squares_are_squares[0] ... ok\ntest squares_are_squares[1] ... ok\ntest squares_are_squares[2] ... ok\ntest plain ... ok\n7 tests: 6 passed, 1 failed\n"

main :: fn() -> int {
    storage : u8[2048]
    caught := testing.BufferReporter.{bytes = storage}
    failed :: testing.run(#insert testing.tests_of(compiler.load_package(".")), testing.reporter_of(&caught))
    if failed != 1 || testing.report_text(&caught) != EXPECTED {
        runtime.write_output(testing.report_text(&caught))
        return 1
    }
    // One case, filtered by its name
    other : u8[256]
    one := testing.BufferReporter.{bytes = other}
    _ = testing.run(#insert testing.tests_of(compiler.load_package(".")), testing.reporter_of(&one), "[word]")
    if testing.report_text(&one) != "test measures_text[word] ... ok\n1 test: 1 passed, 0 failed, 6 filtered out\n" {
        runtime.write_output(testing.report_text(&one))
        return 2
    }
    return 42
}
