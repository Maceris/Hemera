package testing

import runtime from "base"
import text_buffer from "std"

/** How many of a test's failures are kept in full; past these, failures are only counted. */
MAX_FAILURES :: 8
/** How many bytes of a failure's message, and of its values' text, are kept; past these, the text is cut short. */
TEXT_BYTES :: 160

/** Why a test ended early: a require_ assertion failed. It carries nothing, as the failure is in the test's T. */
Stopped :: enum {
    /** A require_ assertion failed, and the test went no further. */
    Failed,
}

/**
 * What a test gives back: Ok once it's run to its end, whatever its expect_ assertions found; Error when a require_
 * assertion stopped it. Whether it passed is its T's to say (passed), not this.
 */
Outcome :: alias Result[void, Stopped]

/** One failed assertion, as it's reported. */
Failure :: struct {
    /** Where the assertion was made, its caller's location. */
    location : runtime.SourceCodeLocation,
    /** The assertion's message, why the check should hold; its first message_count bytes. */
    message : u8[TEXT_BYTES],
    /** How many bytes of message are used, 0 to TEXT_BYTES. */
    message_count : usize,
    /** What was found, like "expected 5400, got 5300"; its first detail_count bytes, none for a plain expect. */
    detail : u8[TEXT_BYTES],
    /** How many bytes of detail are used, 0 to TEXT_BYTES. */
    detail_count : usize,
}

/** A test's state, which its assertions record into: a fresh one for each test the runner runs. */
T :: struct {
    /** The test's name, its function's, for helpers that say which test they're in. */
    name : string,
    /** The first failures, in the order they happened; failure_count says how many of these are used. */
    failures : Failure[MAX_FAILURES],
    /** How many assertions failed in all, which may be more than MAX_FAILURES; 0 while the test passes. */
    failure_count : usize,
}

/** A test a runner runs: a #test function, and its name. */
Test :: struct {
    /** The function's name, which reports and filters use. */
    name : string,
    /** The function, which takes the test's state and gives back how it ended. */
    run : fn(t: ptr[mut T]) -> Outcome,
}

/**
 * Where a runner's report goes: a line at a time, each ending with its newline, written by write with target.
 */
Reporter :: struct {
    /** What write writes to, passed to it; null for a writer that needs nothing, like standard output's. */
    target : rawptr,
    /** Write text, which is good only during the call; it can't fail, so a writer with nowhere to put it drops it. */
    write : fn(target: rawptr, text: string),
}

/**
 * Tell whether a test has passed so far: no assertion has failed in it.
 *
 * @param t The test's state, only read.
 * @return True while no assertion has failed.
 */
passed :: fn(t: ptr[T]) -> bool {
    return t.failure_count == 0
}

/**
 * Record a failure: kept in full if there's room among MAX_FAILURES, otherwise only counted.
 *
 * @param t The test's state, whose failure_count goes up by one.
 * @param message Why the check should have held, as the assertion was given it; cut at TEXT_BYTES.
 * @param detail What was found instead, like "expected 1, got 2"; empty for none, and cut at TEXT_BYTES.
 * @param location Where the assertion was made.
 */
record :: fn(t: ptr[mut T], message: string, detail: string, location: runtime.SourceCodeLocation) {
    index :: t.failure_count
    t.failure_count += 1
    if index >= t.failures.count {
        return void
    }
    failure := Failure.{location = location}
    failure.message_count = copy_text(message, &failure.message)
    failure.detail_count = copy_text(detail, &failure.detail)
    t.failures[index] = failure
}

/**
 * Copy text into a failure's fixed bytes, as much as fits.
 *
 * @param text The text, any length.
 * @param into Where it's copied, from its start.
 * @return How many bytes were copied: text.count, or TEXT_BYTES if it didn't all fit.
 */
copy_text :: fn(text: string, into: ptr[mut u8[TEXT_BYTES]]) -> usize {
    count : usize = 0
    for character in text {
        if count >= into.count {
            break
        }
        into^[count] = cast[u8](character)
        count += 1
    }
    return count
}

/**
 * Check that a condition holds.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param condition What should be true.
 * @param message Why it should be, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return True if the condition held; false, the failure recorded, if not. Most callers ignore it.
 */
expect :: fn(t: ptr[mut T], condition: bool, message: string, location := #caller_location) -> bool {
    if !condition {
        record(t, message, "", location)
    }
    return condition
}

/**
 * Check that two values are equal, reporting both, written as % writes them, if they aren't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param expected What it should have given; of the same type, comparable with ==.
 * @param message Why they should be equal, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return True if they were equal; false, the failure recorded, if not.
 */
expect_eq :: fn[V](t: ptr[mut T], actual: V, expected: V, message: string, location := #caller_location) -> bool {
    if actual == expected {
        return true
    }
    storage : u8[TEXT_BYTES]
    detail := text_buffer.make(storage)
    text_buffer.append_format(&detail, "expected %, got %", expected, actual)
    record(t, message, text_buffer.as_string(&detail), location)
    return false
}

/**
 * Check that two values differ, reporting the value if they don't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param unexpected What it mustn't be; of the same type, comparable with ==.
 * @param message Why they should differ, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return True if they differed; false, the failure recorded, if not.
 */
expect_ne :: fn[V](t: ptr[mut T], actual: V, unexpected: V, message: string, location := #caller_location) -> bool {
    if actual != unexpected {
        return true
    }
    storage : u8[TEXT_BYTES]
    detail := text_buffer.make(storage)
    text_buffer.append_format(&detail, "expected anything but %", unexpected)
    record(t, message, text_buffer.as_string(&detail), location)
    return false
}

/**
 * Check that a result is Ok, reporting its error if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param result The result, of any Result type.
 * @param message Why it should succeed, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return True if it was Ok; false, the failure recorded, if not.
 */
expect_ok :: fn[V, E](t: ptr[mut T], result: Result[V, E], message: string, location := #caller_location) -> bool {
    match result {
        case Ok => return true
        case Error(error) => {
            storage : u8[TEXT_BYTES]
            detail := text_buffer.make(storage)
            text_buffer.append_format(&detail, "expected Ok, got Error(%)", error)
            record(t, message, text_buffer.as_string(&detail), location)
            return false
        }
    }
}

/**
 * Check that a result is a particular error, reporting what it was if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param result The result, of any Result type whose error is comparable with ==.
 * @param wanted The error it should be.
 * @param message Why it should fail so, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return True if it was Error(wanted); false, the failure recorded, if it was Ok or another error.
 */
expect_error :: fn[V, E](t: ptr[mut T], result: Result[V, E], wanted: E, message: string, location := #caller_location) -> bool {
    storage : u8[TEXT_BYTES]
    detail := text_buffer.make(storage)
    match result {
        case Ok => text_buffer.append_format(&detail, "expected Error(%), got Ok", wanted)
        case Error(error) => {
            if error == wanted {
                return true
            }
            text_buffer.append_format(&detail, "expected Error(%), got Error(%)", wanted, error)
        }
    }
    record(t, message, text_buffer.as_string(&detail), location)
    return false
}

/**
 * Check that an optional holds a value.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param optional The optional, of any type.
 * @param message Why it should hold one, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return True if it held one; false, the failure recorded, if it was empty.
 */
expect_some :: fn[V](t: ptr[mut T], optional: V?, message: string, location := #caller_location) -> bool {
    if optional is_some {
        return true
    }
    record(t, message, "expected a value, got none", location)
    return false
}

/**
 * Check that an optional is empty, reporting what it held if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param optional The optional, of any type.
 * @param message Why it should be empty, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return True if it was empty; false, the failure recorded, if it held a value.
 */
expect_none :: fn[V](t: ptr[mut T], optional: V?, message: string, location := #caller_location) -> bool {
    match optional {
        case Some(value) => {
            storage : u8[TEXT_BYTES]
            detail := text_buffer.make(storage)
            text_buffer.append_format(&detail, "expected none, got %", value)
            record(t, message, text_buffer.as_string(&detail), location)
            return false
        }
        case None => return true
    }
}

/**
 * Record a failure unconditionally, for a path a test shouldn't reach.
 *
 * @param t The test's state, which the failure is recorded in.
 * @param message What went wrong, for whoever reads the failure.
 * @param location Where it failed; the caller's own.
 */
fail :: fn(t: ptr[mut T], message: string, location := #caller_location) {
    record(t, message, "", location)
}

/**
 * Turn whether an expect_ assertion held into an Outcome, for its require_ form.
 *
 * @param held What the expect_ assertion gave.
 * @return Ok if it held; Error(Failed) if not, for the test to return with ?.
 */
outcome_of :: fn(held: bool) -> Outcome {
    if held {
        return .Ok
    }
    return .Error(.Failed)
}

/**
 * Require a condition, as expect does, ending the test with ? if it doesn't hold.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param condition What has to be true for the test to go on.
 * @param message Why it should be, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return Ok if it held; Error(Failed), the failure recorded, if not.
 */
require :: fn(t: ptr[mut T], condition: bool, message: string, location := #caller_location) -> Outcome {
    return outcome_of(expect(t, condition, message, location))
}

/**
 * Require two values to be equal, as expect_eq checks, ending the test with ? if they aren't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param expected What it should have given.
 * @param message Why they should be equal, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return Ok if they were equal; Error(Failed), the failure recorded, if not.
 */
require_eq :: fn[V](t: ptr[mut T], actual: V, expected: V, message: string, location := #caller_location) -> Outcome {
    return outcome_of(expect_eq(t, actual, expected, message, location))
}

/**
 * Require two values to differ, as expect_ne checks, ending the test with ? if they don't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param unexpected What it mustn't be.
 * @param message Why they should differ, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return Ok if they differed; Error(Failed), the failure recorded, if not.
 */
require_ne :: fn[V](t: ptr[mut T], actual: V, unexpected: V, message: string, location := #caller_location) -> Outcome {
    return outcome_of(expect_ne(t, actual, unexpected, message, location))
}

/**
 * Require a result to be Ok, giving its value, as expect_ok checks; ending the test with ? if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param result The result, of any Result type.
 * @param message Why it should succeed, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return The Ok value; Error(Failed), the failure recorded with the error, if it was an Error.
 */
require_ok :: fn[V, E](t: ptr[mut T], result: Result[V, E], message: string, location := #caller_location) -> Result[V, Stopped] {
    match result {
        case Ok(value) => return .Ok(value)
        case Error(error) => {
            _ = expect_ok(t, result, message, location)
            return .Error(.Failed)
        }
    }
}

/**
 * Require a result to be a particular error, as expect_error checks, ending the test with ? if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param result The result, of any Result type whose error is comparable with ==.
 * @param wanted The error it should be.
 * @param message Why it should fail so, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return Ok if it was Error(wanted); Error(Failed), the failure recorded, if not.
 */
require_error :: fn[V, E](t: ptr[mut T], result: Result[V, E], wanted: E, message: string, location := #caller_location) -> Outcome {
    return outcome_of(expect_error(t, result, wanted, message, location))
}

/**
 * Require an optional to hold a value, giving it, as expect_some checks; ending the test with ? if it's empty.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param optional The optional, of any type.
 * @param message Why it should hold one, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return The value; Error(Failed), the failure recorded, if it was empty.
 */
require_some :: fn[V](t: ptr[mut T], optional: V?, message: string, location := #caller_location) -> Result[V, Stopped] {
    match optional {
        case Some(value) => return .Ok(value)
        case None => {
            record(t, message, "expected a value, got none", location)
            return .Error(.Failed)
        }
    }
}

/**
 * Require an optional to be empty, as expect_none checks, ending the test with ? if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param optional The optional, of any type.
 * @param message Why it should be empty, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 * @return Ok if it was empty; Error(Failed), the failure recorded, if it held a value.
 */
require_none :: fn[V](t: ptr[mut T], optional: V?, message: string, location := #caller_location) -> Outcome {
    return outcome_of(expect_none(t, optional, message, location))
}

/**
 * Write a line of a report through a reporter, built in a buffer of its own so it goes in one write.
 *
 * @param reporter Where it goes.
 * @param format_string The line, without its newline, with % for each value, as text_buffer's append_format takes it.
 * @param values The values for its %s.
 */
report :: fn(reporter: Reporter, format_string: string, values: any...) {
    storage : u8[2 * TEXT_BYTES + 64]
    line := text_buffer.make(storage)
    text_buffer.append_format(&line, format_string, values)
    // The newline even when the line was cut short
    if line.truncated && line.count > 0 {
        line.count -= 1
    }
    text_buffer.append_byte(&line, cast[u8]('\n'))
    reporter.write(reporter.target, text_buffer.as_string(&line))
}

/**
 * Tell whether text contains other text, for a filter on tests' names.
 *
 * @param text The text looked in.
 * @param part What's looked for; empty is in everything.
 * @return Whether part appears in text, byte for byte.
 */
contains :: fn(text: string, part: string) -> bool {
    if part.count > text.count {
        return false
    }
    for start in 0..<text.count - part.count + 1 {
        same := true
        for character, i in part {
            at :: start + i
            if at >= text.count || text[at] != character {
                same = false
                break
            }
        }
        if same {
            return true
        }
    }
    return false
}

/**
 * Run tests in order, each with a fresh T, reporting each as it ends and a summary after.
 *
 * For each test: "test <name> ... ok", or "test <name> ... FAILED" then, for each failure kept, its file and line and
 * message, and the values found, indented beneath; "and N more failures" past MAX_FAILURES. Last, "N tests: P passed,
 * F failed", and ", S skipped" when a filter left some out.
 *
 * @param tests The tests, as tests_of makes them.
 * @param reporter Where the report goes.
 * @param filter Only tests whose names contain it are run; empty runs every test.
 * @return How many tests failed: 0 when all that ran passed.
 */
run :: fn(tests: Test[], reporter: Reporter, filter: string = "") -> usize {
    passed_count : usize = 0
    failed_count : usize = 0
    skipped : usize = 0
    for test in tests {
        if !contains(test.name, filter) {
            skipped += 1
            continue
        }
        t := T.{name = test.name}
        _ = test.run(&t)
        if t.failure_count == 0 {
            passed_count += 1
            report(reporter, "test % ... ok", test.name)
            continue
        }
        failed_count += 1
        report(reporter, "test % ... FAILED", test.name)
        for failure, i in t.failures {
            if i >= t.failure_count {
                break
            }
            message :: string_of(&failure.message[0], failure.message_count)
            report(reporter, "    %:%: %", failure.location.file_path, failure.location.line, message)
            if failure.detail_count > 0 {
                report(reporter, "        %", string_of(&failure.detail[0], failure.detail_count))
            }
        }
        if t.failure_count > t.failures.count {
            report(reporter, "    and % more failures", t.failure_count - t.failures.count)
        }
    }
    total :: passed_count + failed_count
    if skipped > 0 {
        report(reporter, "% tests: % passed, % failed, % skipped", total, passed_count, failed_count, skipped)
    }
    else {
        report(reporter, "% tests: % passed, % failed", total, passed_count, failed_count)
    }
    return failed_count
}

/**
 * Write text to standard output, where there is one: the hosted reporter's writer.
 *
 * @param target Not used.
 * @param text The text, written as it is.
 */
write_standard_output :: fn(target: rawptr, text: string) {
    runtime.write_output(text)
}

/** A reporter writing to standard output, for hosted programs; nowhere, where there's no standard output. */
STANDARD_OUTPUT :: Reporter.{target = null, write = write_standard_output}
