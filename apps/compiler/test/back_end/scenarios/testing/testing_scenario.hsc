/*
 * std/testing (docs/testing.md): #test functions found through reflection, their assertions, and the runner's report,
 * caught and compared whole. main returns 42 if everything worked, or the number of the first check that failed.
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

// Not a test: no #test
helper :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.fail(t, "the helper ran")
    return .Ok
}

// Where the report goes: a buffer, so it can be compared
Captured :: struct {
    bytes : u8[2048],
    count : usize,
}

capture :: fn(target: rawptr, text: string) {
    captured :: cast[ptr[mut Captured]](target)
    for character in text {
        if captured.count < captured.bytes.count {
            captured.bytes[captured.count] = cast[u8](character)
            captured.count += 1
        }
    }
}

EXPECTED :: "test parses_digits ... ok\ntest reports_failures ... FAILED\n    testing_scenario.hsc:41: twelve isn't thirteen\n        expected 13, got 12\n    testing_scenario.hsc:42: plainly false\n    testing_scenario.hsc:43: negative numbers parse\n        expected Ok, got Error(Negative)\n2 tests: 1 passed, 1 failed\n"

main :: fn() -> int {
    tests :: #insert testing.tests_of(compiler.load_package("."))
    if tests.count != 2 || tests[0].name != "parses_digits" || tests[1].name != "reports_failures" {
        return 1
    }
    captured := Captured.{}
    reporter :: testing.Reporter.{target = cast[rawptr](&captured), write = capture}
    failed :: testing.run(tests, reporter)
    report :: string_of(&captured.bytes[0], captured.count)
    if failed != 1 {
        return 2
    }
    if report != EXPECTED {
        runtime.write_output(report)
        return 3
    }
    // Filtered, only the one that passes runs
    again := Captured.{}
    if testing.run(tests, testing.Reporter.{target = cast[rawptr](&again), write = capture}, "digits") != 0 {
        return 4
    }
    if string_of(&again.bytes[0], again.count) != "test parses_digits ... ok\n1 tests: 1 passed, 0 failed, 1 skipped\n" {
        return 5
    }
    return 42
}
