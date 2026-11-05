/*
 * Tags (docs/testing.md, Tags) and property tests (Property Tests): which tests a run's tags leave out, and property
 * tests drawing their cases, shrinking a failing one to the smallest, and discarding cases. main returns 42 if each run's
 * report is what it should be.
 */
package property_tests

import runtime from "base"
import compiler from "base"
import testing from "std"

/** The package's own tag, run unless left out. */
NETWORK :: testing.Tag.{name = "network", by_default = .Included}

Shade :: enum {
    Light,
    Dark,
}

/** A value made of parts draw can make. */
Pixel :: struct {
    x : u16,
    y : i8,
    shade : Shade,
    lit : bool,
    weights : u8[3],
}

takes_long #test #tags(testing.SLOW) :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    return .Ok
}

reaches_the_network #test #tags(NETWORK) :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    return .Ok
}

measures_speed #test #tags(testing.PERFORMANCE, NETWORK) :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    return .Ok
}

adds_both_ways #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    a :: testing.draw_between(source, -1000, 1000)
    b :: testing.draw_between(source, -1000, 1000)
    testing.expect_eq(t, a + b, b + a, "addition commutes")
    return .Ok
}

draws_whole_values #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    pixel :: testing.draw[Pixel](source)
    testing.expect(t, pixel.shade == .Light || pixel.shade == .Dark, "the shade is a member")
    bytes :: testing.draw_bytes(source, 16)
    testing.expect_le(t, bytes.count, 16, "no more bytes than asked for")
    return .Ok
}

// Wrong on purpose: fails from 500 up, so the case shrinks to 500
stays_below_500 #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    value :: testing.draw_between(source, 0, 1000)
    testing.expect_lt(t, value, 500, "the value is below 500")
    return .Ok
}

// Wrong on purpose: the smallest failing case draws 0, then 100
sums_below_100 #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    a :: testing.draw_between(source, 0, 1000)
    b :: testing.draw_between(source, 0, 1000)
    testing.expect_lt(t, a + b, 100, "the sum is below 100")
    return .Ok
}

// Every case is discarded, so it's skipped
discards_everything #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    value :: testing.draw_between(source, 0, 10)
    testing.assume(t, value > 10, "above 10")?
    return .Ok
}

// Asks for what draw can't make, which fails
draws_a_string #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    _ = testing.draw[string](source)
    return .Ok
}

/**
 * Run the tests with options, and check the report.
 *
 * @param tests The tests.
 * @param options Which to run.
 * @param expected The report wanted.
 * @return Whether the report is expected; if not, it's written out.
 */
reports :: fn(tests: testing.Test[], options: testing.RunOptions, expected: string) -> bool {
    storage : u8[4096]
    caught := testing.BufferReporter.{bytes = storage}
    _ = testing.run(tests, testing.reporter_of(&caught), options)
    report :: testing.report_text(&caught)
    if report != expected {
        runtime.write_output(report)
        runtime.write_output("\n")
        return false
    }
    return true
}

main :: fn() -> int {
    tests :: #insert testing.tests_of(compiler.load_package("."))
    if tests.count != 9 || tests[0].tag_count != 1 || tests[0].tags[0].name != "slow" || tests[2].tag_count != 2 {
        return 1
    }
    tagged :: tests[0..<3]
    // By default the slow and performance tests are left out
    if !reports(tagged, testing.RunOptions.{}, "test reaches_the_network ... ok\n1 test: 1 passed, 0 failed, 2 left out by tag\n") {
        return 2
    }
    if !reports(tagged, testing.RunOptions.{tags = "+slow,-network"}, "test takes_long ... ok\n1 test: 1 passed, 0 failed, 2 left out by tag\n") {
        return 3
    }
    if !reports(tagged, testing.RunOptions.{tags = "all"}, "test takes_long ... ok\ntest reaches_the_network ... ok\ntest measures_speed ... ok\n3 tests: 3 passed, 0 failed\n") {
        return 4
    }
    // A bare tag runs only its tests, whatever their defaults
    if !reports(tagged, testing.RunOptions.{tags = "performance"}, "test measures_speed ... ok\n1 test: 1 passed, 0 failed, 2 left out by tag\n") {
        return 5
    }
    properties :: tests[3..<9]
    expected :: "test adds_both_ways ... ok\ntest draws_whole_values ... ok\ntest stays_below_500 ... FAILED\n    property_tests.hsc:59: the value is below 500\n        expected less than 500, got 500\n        note: drew 500\n    found by case 2 of 100 (seed 7), shrunk from 2 bytes to 2 in 63 runs\ntest sums_below_100 ... FAILED\n    property_tests.hsc:67: the sum is below 100\n        expected less than 100, got 100\n        note: drew 0, 100\n    found by case 1 of 100 (seed 7), shrunk from 4 bytes to 4 in 137 runs\ntest discards_everything ... skipped: every case was discarded\ntest draws_a_string ... FAILED\n    property_tests.hsc:80: draw can't make string: draw what it holds, and build it\n6 tests: 2 passed, 3 failed, 1 skipped\n"
    if !reports(properties, testing.RunOptions.{seed = 7}, expected) {
        return 6
    }
    return 42
}
