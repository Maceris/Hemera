/*
 * std/testing (docs/testing.md): #test functions found through reflection, their assertions, notes and skips, and the
 * runner's report, caught and compared whole. main returns 42 if everything worked, or the number of the first check
 * that failed.
 */
package testing_scenario

import runtime from "base"
import compiler from "base"
import testing from "std"

Parsed :: enum {
    Empty,
    Negative,
}

// A stand-in for code under test: the number a text of digits says, or why not
parse :: fn(text: string) -> Result[int, Parsed] {
    if text.count == 0 {
        return .Error(.Empty)
    }
    value := 0
    for character in text {
        if character == '-' {
            return .Error(.Negative)
        }
        value = value * 10 + cast[int](character) - cast[int]('0')
    }
    return .Ok(value)
}

parses_digits #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    parsed :: testing.require_ok(t, parse("42"), "digits parse")?
    testing.expect_eq(t, parsed, 42, "forty-two")
    testing.expect_error(t, parse(""), Parsed.Empty, "nothing isn't a number")
    testing.expect_some(t, cast[int?](parsed), "a value")
    testing.expect_lt(t, parsed, 100, "two digits")
    testing.expect_within(t, parsed, 40, 42, "forty-something")
    testing.expect_any_error(t, parse("-3"), "a sign isn't a digit")
    testing.expect_error_in(t, parse(""), Parsed.[Parsed.Negative, Parsed.Empty], "nothing, or a sign, isn't a number")
    digits :: int.[4, 2]
    same :: int.[4, 2]
    testing.expect_same_items(t, digits[0..<2], same[0..<2], "the digits, in order")
    return .Ok
}

// Two failures that don't stop it, then one that does, so the last expect is never reached
reports_failures #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, parse("12") or_else 0, 13, "twelve isn't thirteen")
    testing.expect(t, false, "plainly false")
    testing.require_ok(t, parse("-1"), "negative numbers parse")?
    testing.fail(t, "never reached")
    return .Ok
}

// What each kind of assertion says it found, a note in force, and a message that says it itself
reports_what_was_found #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_lt(t, 0xff35, 0xff31, "%1{x} is below the limit %2{x}")
    testing.expect_eq(t, "", "a", "the name")
    testing.note(t, "case %", 3)
    testing.expect_within(t, 12, 1, 10, "in range")
    testing.end_note(t)
    found :: int.[1, 2, 3]
    wanted :: int.[1, 5, 3]
    testing.expect_same_items(t, found[0..<3], wanted[0..<3], "the same items")
    testing.expect_any_error(t, parse("7"), "seven is refused")
    return .Ok
}

skips_itself #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    return testing.skip(t, "nothing to test here")
}

// Not a test: no #test
helper :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.fail(t, "the helper ran")
    return .Ok
}

EXPECTED :: "test parses_digits ... ok\ntest reports_failures ... FAILED\n    testing_scenario.hsc:49: twelve isn't thirteen\n        expected 13, got 12\n    testing_scenario.hsc:50: plainly false\n    testing_scenario.hsc:51: negative numbers parse\n        expected Ok, got Error(Negative)\ntest reports_what_was_found ... FAILED\n    testing_scenario.hsc:58: ff35 is below the limit ff31\n    testing_scenario.hsc:59: the name\n        expected \"a\", got \"\"\n    testing_scenario.hsc:61: in range\n        expected 1 to 10, got 12\n        note: case 3\n    testing_scenario.hsc:65: the same items\n        at 1, expected 5, got 2\n    testing_scenario.hsc:66: seven is refused\n        expected an error, got Ok(7)\ntest skips_itself ... skipped: nothing to test here\n4 tests: 1 passed, 2 failed, 1 skipped\n"

main :: fn() -> int {
    tests :: #insert testing.tests_of(compiler.load_package("."))
    if tests.count != 4 || tests[0].name != "parses_digits" || tests[1].name != "reports_failures" {
        return 1
    }
    // One file's tests: this file's are all of them, and another's none
    if (#insert testing.tests_of(compiler.load_package("."), "testing_scenario.hsc")).count != 4
        || (#insert testing.tests_of(compiler.load_package("."), "elsewhere.hsc")).count != 0 {
        return 6
    }
    storage : u8[4096]
    caught := testing.BufferReporter.{bytes = storage}
    failed :: testing.run(tests, testing.reporter_of(&caught))
    report :: testing.report_text(&caught)
    if failed != 2 {
        runtime.write_output(report)
        return 2
    }
    if report != EXPECTED {
        runtime.write_output(report)
        return 3
    }
    // Filtered, only the one that passes runs
    other_storage : u8[256]
    again := testing.BufferReporter.{bytes = other_storage}
    if testing.run(tests, testing.reporter_of(&again), testing.RunOptions.{filter = "digits"}) != 0 {
        return 4
    }
    if testing.report_text(&again) != "test parses_digits ... ok\n1 test: 1 passed, 0 failed, 3 filtered out\n" {
        runtime.write_output(testing.report_text(&again))
        return 5
    }
    return 42
}
