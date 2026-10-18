/*
 * std's general-purpose packages in a hosted program: strings, time's calendar, memory's SharedPtr
 * and logger. main returns 42 if everything worked, or the number of the first check that failed;
 * the logger's lines are checked against error.txt next to this file.
 */
package library_test

import runtime from "base"
import logger from "std"
import memory from "std"
import strings from "std"
import time from "std"

// Formatting, comparing, searching and splitting: 0 if it all worked, or the first check that didn't.
check_strings :: fn() -> int {
    formatted, error :: strings.format("% + % = %", 2, 3, "five")
    if error != null || !strings.equal(formatted, "2 + 3 = five") {
        return 1
    }
    strings.free_string(formatted)
    // Longer than the stack buffer, so formatted again from the allocator
    long, long_error :: strings.format("%1%2%3", "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789", "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789", "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789")
    if long_error != null || long.count != 300 || !strings.ends_with(long, "789") {
        return 2
    }
    strings.free_string(long)
    if !strings.starts_with("hemera", "hem") || strings.starts_with("he", "hem") || !strings.ends_with("hemera", "era") {
        return 3
    }
    match strings.find("a needle in a haystack", "in") {
        case Some(index) => {
            if index != 9 {
                return 4
            }
        }
        case None => return 4
    }
    if strings.contains("haystack", "needle") || !strings.equal(strings.trim("  \tspaced \n"), "spaced") {
        return 5
    }
    pieces := strings.split("a,b,,c", ",")
    expected :: "abc"
    found := 0
    loop {
        match strings.next(&pieces) {
            case Some(piece) => {
                if found == 2 {
                    if piece.count != 0 {
                        return 6
                    }
                }
                else if piece.count != 1 {
                    return 6
                }
                found += 1
            }
            case None => break
        }
    }
    if found != 4 {
        return 7
    }
    return 0
}

// Whether parsed is expected.
parsed_unsigned :: fn(parsed: u64?, expected: u64) -> bool {
    match parsed {
        case Some(value) => return value == expected
        case None => return false
    }
}

parsed_signed :: fn(parsed: i64?, expected: i64) -> bool {
    match parsed {
        case Some(value) => return value == expected
        case None => return false
    }
}

// Parsing numbers: 0 if it all worked, or the first check that didn't.
check_parsing :: fn() -> int {
    if !parsed_unsigned(strings.parse_unsigned("ff", 16), 255) || !parsed_unsigned(strings.parse_unsigned("18446744073709551615"), 0xffff_ffff_ffff_ffff) {
        return 1
    }
    if strings.parse_unsigned("18446744073709551616") != null || strings.parse_unsigned("12x") != null || strings.parse_unsigned("") != null {
        return 2
    }
    if !parsed_signed(strings.parse_signed("-12"), -12) || !parsed_signed(strings.parse_signed("+7"), 7)
        || !parsed_signed(strings.parse_signed("-9223372036854775808"), -9223372036854775807 - 1) {
        return 3
    }
    if strings.parse_signed("9223372036854775808") != null || strings.parse_bool("yes") != null {
        return 4
    }
    match strings.parse_bool("true") {
        case Some(value) => {
            if !value {
                return 5
            }
        }
        case None => return 5
    }
    return 0
}

// The calendar: 0 if it all worked, or the first check that didn't.
check_time :: fn() -> int {
    epoch :: time.utc(time.Instant.{0, 0})
    if epoch.year != 1970 || epoch.month != 1 || epoch.day != 1 || epoch.hour != 0 {
        return 1
    }
    // 2000-02-29 12:34:56, a leap day in a year divisible by 400
    leap :: time.utc(time.Instant.{951827696, 5})
    if leap.year != 2000 || leap.month != 2 || leap.day != 29 || leap.hour != 12 || leap.minute != 34 || leap.second != 56 || leap.nanosecond != 5 {
        return 2
    }
    // 1969-12-31 23:59:59, before the epoch
    before :: time.utc(time.Instant.{-1, 0})
    if before.year != 1969 || before.month != 12 || before.day != 31 || before.second != 59 {
        return 3
    }
    back :: time.from_utc(leap)
    if back.seconds != 951827696 || back.nanos != 5 {
        return 4
    }
    if time.weekday(time.Instant.{0, 0}) != .THURSDAY || time.weekday(time.Instant.{-1, 0}) != .WEDNESDAY {
        return 5
    }
    later :: time.add(time.Instant.{10, 900000000}, time.Duration.{1, 200000000})
    if later.seconds != 12 || later.nanos != 100000000 {
        return 6
    }
    gap :: time.between(later, time.Instant.{10, 0})
    if gap.seconds != -3 || gap.nanos != 900000000 || !time.is_before(time.Instant.{10, 0}, later) {
        return 7
    }
    return 0
}

destroyed :: fn(value: ptr[mut int]) {
    value^ = -1
}

// SharedPtr: 0 if it worked, or the first check that didn't.
check_memory :: fn() -> int {
    value :: runtime.new(int)
    value^ = 5
    shared :: runtime.new(memory.SharedPtr[int])
    shared.count = 1
    shared.value = value
    shared.destructor = destroyed
    memory.increment(shared)
    if memory.decrement(shared) || value^ != 5 {
        return 1
    }
    if !memory.decrement(shared) || value^ != -1 {
        return 2
    }
    runtime.free(shared)
    runtime.free(value)
    ok : Result[int, int] = .Ok(1)
    if !memory.is_ok(ok) || memory.is_error(ok) {
        return 3
    }
    return 0
}

// What the logger puts on each line: no clock in a hosted program yet, so no time
DETAILED :: logger.Options.{time = true, location = true, function = true, thread = true}
PLAIN :: logger.Options.{time = false, location = false, function = false, thread = false, stream = .OUTPUT}

main :: fn() -> int {
    failure := check_strings()
    if failure != 0 {
        return 10 + failure
    }
    failure = check_parsing()
    if failure != 0 {
        return 20 + failure
    }
    failure = check_time()
    if failure != 0 {
        return 30 + failure
    }
    failure = check_memory()
    if failure != 0 {
        return 40 + failure
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
