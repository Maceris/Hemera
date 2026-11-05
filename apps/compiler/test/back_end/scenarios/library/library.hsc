/*
 * std's general-purpose packages in a hosted program: strings, time's calendar, memory's SharedPtr
 * and logger. main runs the package's tests, and returns 42 if they all passed, with nothing written
 * but the logger's lines, which are checked against output.txt and error.txt next to this file; if any
 * failed, it writes their report to standard output and returns 1.
 */
package library_test

import compiler from "base"
import runtime from "base"
import logger from "std"
import memory from "std"
import strings from "std"
import testing from "std"
import time from "std"

formats_and_compares_strings #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    formatted :: testing.require_ok(t, strings.format("% + % = %", 2, 3, "five"), "the allocator has room for a short string")?
    testing.expect(t, strings.equal(formatted, "2 + 3 = five"), "each % takes the next value, written as % writes it")
    strings.free_string(formatted)
    // Longer than the stack buffer, so formatted again from the allocator
    long :: testing.require_ok(t, strings.format("%1%2%3", "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789", "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789", "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"), "the allocator has room for 300 bytes")?
    testing.expect_eq(t, long.count, 300, "three values of 100 bytes, past the stack buffer, are formatted whole")
    testing.expect(t, strings.ends_with(long, "789"), "the last value's end is kept")
    strings.free_string(long)
    testing.expect(t, strings.starts_with("hemera", "hem"), "hemera starts with hem")
    testing.expect(t, !strings.starts_with("he", "hem"), "a prefix longer than the text isn't at its start")
    testing.expect(t, strings.ends_with("hemera", "era"), "hemera ends with era")
    return .Ok
}

searches_and_splits_strings #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    found :: strings.find("a needle in a haystack", "in")
    index :: testing.require_some(t, found, "in is in the text")?
    testing.expect_eq(t, index, 9, "the first in is the word, after a needle and its space")
    testing.expect(t, !strings.contains("haystack", "needle"), "haystack has no needle")
    testing.expect(t, strings.equal(strings.trim("  \tspaced \n"), "spaced"), "trim takes off spaces, tabs and newlines at both ends")
    pieces := strings.split("a,b,,c", ",")
    found_count := 0
    loop {
        piece :: strings.next(&pieces) or_break
        expected_count : usize = if found_count == 2 { 0 } else { 1 }
        testing.expect_eq(t, piece.count, expected_count, "a,b,,c splits into one letter each but the empty third")
        found_count += 1
    }
    testing.expect_eq(t, found_count, 4, "three commas make four pieces, the empty one among them")
    return .Ok
}

/**
 * Tell whether a parsed number is the one expected.
 *
 * @param parsed What was parsed; none if it wasn't a number.
 * @param expected The number it should be.
 * @return True only if parsed holds expected.
 */
parsed_unsigned :: fn(parsed: u64?, expected: u64) -> bool {
    match parsed {
        case Some(value) => return value == expected
        case None => return false
    }
}

/**
 * Tell whether a parsed number is the one expected.
 *
 * @param parsed What was parsed; none if it wasn't a number.
 * @param expected The number it should be.
 * @return True only if parsed holds expected.
 */
parsed_signed :: fn(parsed: i64?, expected: i64) -> bool {
    match parsed {
        case Some(value) => return value == expected
        case None => return false
    }
}

parses_numbers #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, parsed_unsigned(strings.parse_unsigned("ff", 16), 255), "ff in base 16 is 255")
    testing.expect(t, parsed_unsigned(strings.parse_unsigned("18446744073709551615"), 0xffff_ffff_ffff_ffff), "a u64's largest value parses")
    testing.expect(t, strings.parse_unsigned("18446744073709551616") == null, "one more than a u64's largest value overflows")
    testing.expect(t, strings.parse_unsigned("12x") == null, "x isn't a decimal digit")
    testing.expect(t, strings.parse_unsigned("") == null, "nothing isn't a number")
    testing.expect(t, parsed_signed(strings.parse_signed("-12"), -12), "a minus sign makes it negative")
    testing.expect(t, parsed_signed(strings.parse_signed("+7"), 7), "a plus sign is allowed")
    testing.expect(t, parsed_signed(strings.parse_signed("-9223372036854775808"), -9223372036854775807 - 1), "an i64's smallest value parses")
    testing.expect(t, strings.parse_signed("9223372036854775808") == null, "one more than an i64's largest value overflows")
    testing.expect(t, strings.parse_bool("yes") == null, "only true and false are bools")
    match strings.parse_bool("true") {
        case Some(value) => testing.expect(t, value, "true parses as true")
        case None => testing.fail(t, "true parses as a bool")
    }
    return .Ok
}

compares_optionals_with_values #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // An optional against a value of what it holds: equal only when it holds that value
    testing.expect(t, strings.parse_unsigned("ff", 16) == 255, "an optional holding 255 equals 255")
    testing.expect(t, !(strings.parse_unsigned("12x") == 12), "an empty optional equals no value")
    testing.expect(t, !(7 == strings.parse_unsigned("8")), "a value on the left, against an optional holding another")
    return .Ok
}

converts_instants_to_dates #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    epoch :: time.utc(time.Instant.{0, 0})
    testing.expect_eq(t, epoch.year, 1970, "the epoch is 1970-01-01 00:00 UTC: its year")
    testing.expect_eq(t, epoch.month, 1, "its month")
    testing.expect_eq(t, epoch.day, 1, "its day")
    testing.expect_eq(t, epoch.hour, 0, "its hour")
    // 2000-02-29 12:34:56, a leap day in a year divisible by 400
    leap :: time.utc(time.Instant.{951827696, 5})
    testing.expect_eq(t, leap.year, 2000, "2000 is a leap year, divisible by 400: its year")
    testing.expect_eq(t, leap.month, 2, "its leap day's month")
    testing.expect_eq(t, leap.day, 29, "its leap day")
    testing.expect_eq(t, leap.hour, 12, "the hour")
    testing.expect_eq(t, leap.minute, 34, "the minute")
    testing.expect_eq(t, leap.second, 56, "the second")
    testing.expect_eq(t, leap.nanosecond, 5, "the nanoseconds, kept")
    // 1969-12-31 23:59:59, before the epoch
    before :: time.utc(time.Instant.{-1, 0})
    testing.expect_eq(t, before.year, 1969, "a second before the epoch is the year before")
    testing.expect_eq(t, before.month, 12, "its last month")
    testing.expect_eq(t, before.day, 31, "its last day")
    testing.expect_eq(t, before.second, 59, "its last second")
    back :: time.from_utc(leap)
    testing.expect_eq(t, back.seconds, 951827696, "from_utc undoes utc: the seconds")
    testing.expect_eq(t, back.nanos, 5, "and the nanoseconds")
    testing.expect_eq(t, time.weekday(time.Instant.{0, 0}), .THURSDAY, "1970-01-01 was a Thursday")
    testing.expect_eq(t, time.weekday(time.Instant.{-1, 0}), .WEDNESDAY, "the second before was a Wednesday")
    return .Ok
}

adds_and_compares_instants #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    later :: time.add(time.Instant.{10, 900000000}, time.Duration.{1, 200000000})
    testing.expect_eq(t, later.seconds, 12, "0.9 s and 1.2 s carry a second: 10.9 + 1.2 is 12.1")
    testing.expect_eq(t, later.nanos, 100000000, "with 0.1 s left over")
    gap :: time.between(later, time.Instant.{10, 0})
    testing.expect_eq(t, gap.seconds, -3, "10 - 12.1 is -2.1, kept as -3 s and 0.9 s")
    testing.expect_eq(t, gap.nanos, 900000000, "the nanoseconds of a negative gap stay positive")
    testing.expect(t, time.is_before(time.Instant.{10, 0}, later), "10 s is before 12.1 s")
    return .Ok
}

/** A value a SharedPtr holds, which says when it's destroyed. */
Counter :: struct {
    /** What it holds, which a share can change. */
    value : int,
    /** Where its destruction is seen, once it's gone: destroyed writes value there. */
    seen : ptr[mut int],
}

/**
 * Destroy a Counter, writing its value where it's seen.
 *
 * @param counter The Counter, whose value is written to its seen.
 */
destroyed :: fn(counter: ptr[mut Counter]) {
    counter.seen^ = counter.value
}

shares_values #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    seen :: runtime.new(int)
    defer runtime.free(seen)
    seen^ = 0
    shared :: memory.make_shared(Counter.{value = 5, seen = seen}, destroyed)
    second :: memory.share(&shared)
    second.value += 1
    memory.release(second)
    testing.expect_eq(t, seen^, 0, "releasing one of two shares doesn't destroy the value")
    testing.expect_eq(t, shared.value, 6, "the shares hold the same value, which one changed")
    weak :: memory.weaken(&shared)
    memory.release(shared)
    testing.expect_eq(t, seen^, 6, "releasing the last share destroys the value, as it was")
    testing.expect(t, memory.upgrade(&weak) == null, "a weak pointer to a destroyed value can't be upgraded")
    memory.release_weak(weak)
    return .Ok
}

tells_results_apart #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    ok : Result[int, int] = .Ok(1)
    testing.expect(t, ok is_ok, "an Ok is ok")
    testing.expect(t, !(ok is_error), "and isn't an error")
    return .Ok
}

/** What look finds wrong. */
Problem :: enum {
    /** There's nothing for 0. */
    MISSING,
    /** 1 isn't allowed. */
    DENIED,
}

/**
 * Look a number up, failing for 0 and 1.
 *
 * @param n The number.
 * @return MISSING for 0, DENIED for 1, otherwise n.
 */
look :: fn(n: int) -> Result[int, Problem] {
    if n == 0 {
        return .Error(.MISSING)
    }
    if n == 1 {
        return .Error(.DENIED)
    }
    return .Ok(n)
}

/**
 * Match patterns inside a variant's values: what each arm gives, so the order of the arms shows.
 *
 * @param n What look is given.
 * @return 70 for 7, n for other values look gives, -1 for MISSING, -2 for any other error.
 */
classify :: fn(n: int) -> int {
    match look(n) {
        case Ok(7) => return 70
        case Ok(value) => return value
        case Error(.MISSING) => return -1
        case Error(_) => return -2
    }
}

/**
 * Make an optional of an optional, empty at either level.
 *
 * @param n 0 for none, 1 for an empty inner one, otherwise n inside both.
 * @return The optional.
 */
maybe :: fn(n: int) -> Optional[int?] {
    if n == 0 {
        return null
    }
    inner : int? = null
    if n == 1 {
        return inner
    }
    return n
}

matches_nested_patterns #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, classify(0), -1, "Error(.MISSING) matches 0's error")
    testing.expect_eq(t, classify(1), -2, "DENIED falls through to Error(_)")
    testing.expect_eq(t, classify(7), 70, "Ok(7) is matched before Ok(value)")
    testing.expect_eq(t, classify(5), 5, "other values reach Ok(value)")
    for n in 0..<3 {
        got :: match maybe(n) {
            case Some(.None) => 1
            case Some(Some(value)) => 10 + value
            case None => 0
        }
        expected :: if n == 0 { 0 } else if n == 1 { 1 } else { 12 }
        testing.expect_eq(t, got, expected, "the outer and inner optionals are matched apart, empty or not")
    }
    return .Ok
}

/** Where the tests' report goes until it's known whether any failed: a buffer, written out only then. */
Captured :: struct {
    /** The report's bytes, up to their count; what doesn't fit is dropped. */
    bytes : u8[8192],
    /** How many of bytes are used. */
    count : usize,
}

/**
 * Keep a line of the report, a reporter's write.
 *
 * @param target The Captured, as a rawptr.
 * @param text The line, as much of it as fits copied.
 */
capture :: fn(target: rawptr, text: string) {
    captured :: cast[ptr[mut Captured]](target)
    for character in text {
        if captured.count < captured.bytes.count {
            captured.bytes[captured.count] = cast[u8](character)
            captured.count += 1
        }
    }
}

/** What the detailed logger puts on each line: no time, which changes from run to run. */
DETAILED :: logger.Options.{time = false, location = true, function = true, thread = true}
/** What the plain logger puts on each line: only the level and message, on standard output. */
PLAIN :: logger.Options.{time = false, location = false, function = false, thread = false, stream = .OUTPUT}

main :: fn() -> int {
    // Kept quiet unless something failed, since what's written is compared
    captured := Captured.{}
    reporter :: testing.Reporter.{target = cast[rawptr](&captured), write = capture}
    if testing.run(#insert testing.tests_of(compiler.load_package(".")), reporter) != 0 {
        if captured.count > 0 {
            runtime.write_output(string_of(&captured.bytes[0], captured.count))
        }
        return 1
    }
    detailed :: logger.create(DETAILED)
    push_context verbose (logger = detailed, log_level = .DEBUG) {
        runtime.log_debug("% of % checks passed", 4, 4)
        runtime.log_trace("below the level")
    }
    plain :: logger.create(PLAIN)
    push_context to_output (logger = plain) {
        runtime.log_warn("on standard output")
    }
    logger.destroy(detailed)
    logger.destroy(plain)
    return 42
}
