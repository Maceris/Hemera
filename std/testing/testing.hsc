package testing

import runtime from "base"
import reflection from "std"
import text_buffer from "std"

/** How many of a test's failures are kept in full; past these, failures are only counted. */
MAX_FAILURES :: 8
/** How many bytes of a failure's message, of its values' text, and of its notes are kept; past these, text is cut. */
TEXT_BYTES :: 160
/** How many notes a test can have at once (note); one past these is counted, not kept. */
MAX_NOTES :: 4

/** Why a test ended early: a require_ assertion failed, or it skipped itself. The failure or reason is in its T. */
Stopped :: enum {
    /** A require_ assertion failed, and the test went no further. */
    Failed,
    /** The test skipped itself (skip), as what it tests isn't there. */
    Skipped,
}

/**
 * What a test gives back: Ok once it's run to its end, whatever its expect_ assertions found; Error when a require_
 * assertion stopped it, or it skipped itself. Whether it passed is its T's to say (passed), not this.
 */
Outcome :: alias Result[void, Stopped]

/** Some text in fixed space: its first count bytes. */
Text :: struct {
    /** The text's bytes. */
    bytes : u8[TEXT_BYTES],
    /** How many of bytes are used, 0 to TEXT_BYTES. */
    count : usize,
}

/** One failed assertion, as it's reported. */
Failure :: struct {
    /** Where the assertion was made, its caller's location. */
    location : runtime.SourceCodeLocation,
    /** The assertion's message, formatted with its values; why the check should hold. */
    message : Text,
    /** What was found, like "expected 5400, got 5300"; empty when the message says it, or for a plain expect. */
    detail : Text,
    /** The notes in force when it failed, joined with "; "; empty for none. */
    notes : Text,
}

/** A test's state, which its assertions record into: a fresh one for each test the runner runs. */
T :: struct {
    /** The test's name, its function's, for helpers that say which test they're in. */
    name : string,
    /** The first failures, in the order they happened; failure_count says how many of these are used. */
    failures : Failure[MAX_FAILURES],
    /** How many assertions failed in all, which may be more than MAX_FAILURES; 0 while the test passes. */
    failure_count : usize,
    /** The notes in force, oldest first; note_count says how many are used. */
    notes : Text[MAX_NOTES],
    /** How many notes are in force, which may be more than MAX_NOTES, the rest counted but not kept. */
    note_count : usize,
    /** Whether the test skipped itself (skip). */
    skipped : bool,
    /** Why it skipped itself, as skip was given. */
    skip_reason : Text,
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
 *
 * It's #scoped, since its target is usually something on the stack, like a buffer the report is caught in: it's passed
 * by value to run, and can't be kept on the heap (docs/memory.md, Scoped Structs).
 */
Reporter :: struct #scoped {
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
 * Give some fixed-space text as a string.
 *
 * @param text The text, only read.
 * @return A view of its bytes, good while it's unchanged; "" for none.
 */
text_of :: fn(text: ptr[Text]) -> string {
    if text.count == 0 || text.count > text.bytes.count {
        return ""
    }
    return string_of(&text.bytes[0], text.count)
}

/**
 * Put text in fixed space, as much as fits.
 *
 * @param from The text, any length.
 * @return It in a Text, cut at TEXT_BYTES.
 */
text_from :: fn(from: string) -> Text {
    made := Text.{}
    for character in from {
        if made.count >= made.bytes.count {
            break
        }
        made.bytes[made.count] = cast[u8](character)
        made.count += 1
    }
    return made
}

/**
 * Tell whether a format string references any value: a % that isn't %%.
 *
 * @param format The format string, as an assertion's message is.
 * @return True if it has a placeholder, so the message says what the values were and the automatic detail is left out.
 */
references_values :: fn(format: string) -> bool {
    at : usize = 0
    loop {
        if at >= format.count {
            break
        }
        if format[at] == '%' {
            if at + 1 < format.count && format[at + 1] == '%' {
                at += 2
                continue
            }
            return true
        }
        at += 1
    }
    return false
}

/**
 * Record a failure: kept in full if there's room among MAX_FAILURES, otherwise only counted. The notes in force are
 * kept with it.
 *
 * This is the base of every assertion, and of assertions of a test's own: a helper that checks something, records a
 * failure here with its caller's location (its own location := #caller_location, passed on), and gives back whether
 * it held, which outcome_of turns into a require_ form.
 *
 * @param t The test's state, whose failure_count goes up by one.
 * @param message Why the check should have held, already formatted; cut at TEXT_BYTES.
 * @param detail What was found instead, like "expected 1, got 2"; empty for none, and cut at TEXT_BYTES.
 * @param location Where the assertion was made.
 */
record :: fn(t: ptr[mut T], message: string, detail: string, location: runtime.SourceCodeLocation) {
    index :: t.failure_count
    t.failure_count += 1
    if index >= t.failures.count {
        return void
    }
    failure := Failure.{location = location, message = text_from(message), detail = text_from(detail)}
    storage : u8[TEXT_BYTES]
    notes := text_buffer.make(storage)
    for &note, i in t.notes {
        if i >= t.note_count {
            break
        }
        if i > 0 {
            text_buffer.append(&notes, "; ")
        }
        text_buffer.append(&notes, text_of(note))
    }
    if t.note_count > t.notes.count {
        text_buffer.append_format(&notes, "; and % more", t.note_count - t.notes.count)
    }
    failure.notes = text_from(text_buffer.as_string(&notes))
    t.failures[index] = failure
}

/**
 * Record a failure of an assertion over values: its message formatted with them, and, unless the message references
 * them, the automatic detail.
 *
 * @param t The test's state.
 * @param message The assertion's message, a format string over values.
 * @param values The values under test, in the assertion's order, which %1, %2... in message name.
 * @param detail What the assertion says was found, used when message references no value.
 * @param location Where the assertion was made.
 */
record_formatted :: fn(t: ptr[mut T], message: string, values: any[], detail: Text, location: runtime.SourceCodeLocation) {
    storage : u8[TEXT_BYTES]
    formatted := text_buffer.make(storage)
    text_buffer.append_format(&formatted, message, values)
    record(t, text_buffer.as_string(&formatted), if references_values(message) { "" } else { text_of(&detail) }, location)
}

/**
 * Append a value as a failure shows it: as % writes it, but a string in double quotes, its quotes, backslashes and
 * control characters escaped, so an empty string or a trailing space can be seen.
 *
 * @param text The buffer. If it fills, what fits is kept.
 * @param value The value, of any type.
 */
append_shown :: fn(text: ptr[mut text_buffer.TextBuffer], value: any) {
    info :: type_info_of(value.type)
    if cast[rawptr](info) == null || reflection.unaliased(info).variant != .STRING {
        text_buffer.append_value(text, value)
        return void
    }
    shown :: cast[ptr[string]](value.data)^
    text_buffer.append_byte(text, cast[u8]('"'))
    for character in shown {
        byte :: cast[u8](character)
        if byte == cast[u8]('"') || byte == cast[u8]('\\') {
            text_buffer.append_byte(text, cast[u8]('\\'))
            text_buffer.append_byte(text, byte)
        }
        else if byte == cast[u8]('\n') {
            text_buffer.append(text, "\\n")
        }
        else if byte == cast[u8]('\t') {
            text_buffer.append(text, "\\t")
        }
        else if byte < 0x20 || byte == 0x7f {
            text_buffer.append(text, "\\x")
            text_buffer.append_unsigned(text, cast[u64](byte), 16, 2)
        }
        else {
            text_buffer.append_byte(text, byte)
        }
    }
    text_buffer.append_byte(text, cast[u8]('"'))
}

/**
 * Make an assertion's detail: words, with values shown between them as append_shown shows them.
 *
 * @param parts The words before each value, then after the last; one more than values.
 * @param values The values, shown in order.
 * @return The detail, cut at TEXT_BYTES.
 */
detail_of :: fn(parts: string[], values: any[]) -> Text {
    storage : u8[TEXT_BYTES]
    detail := text_buffer.make(storage)
    for part, i in parts {
        text_buffer.append(&detail, part)
        if i < values.count {
            append_shown(&detail, values[i])
        }
    }
    return text_from(text_buffer.as_string(&detail))
}

/**
 * Check that a condition holds.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param condition What should be true.
 * @param message Why it should be, for whoever reads a failure; plain text, as there are no values to format.
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
 * Check that two values are equal, reporting both if they aren't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param expected What it should have given; of the same type, comparable with ==.
 * @param message Why they should be equal: a format string, %1 actual and %2 expected, like "%1{x} is the mask";
 *     with no placeholder, the failure adds "expected <expected>, got <actual>".
 * @param location Where the check is; the caller's own.
 * @return True if they were equal; false, the failure recorded, if not.
 */
expect_eq :: fn[V](t: ptr[mut T], actual: V, expected: V, message #format(actual, expected) : string, location := #caller_location) -> bool {
    if actual == expected {
        return true
    }
    record_formatted(t, message, any.[actual, expected], detail_of(string.["expected ", ", got ", ""], any.[expected, actual]), location)
    return false
}

/**
 * Check that two values differ, reporting the value if they don't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param unexpected What it mustn't be; of the same type, comparable with ==.
 * @param message Why they should differ: a format string, %1 actual and %2 unexpected.
 * @param location Where the check is; the caller's own.
 * @return True if they differed; false, the failure recorded, if not.
 */
expect_ne :: fn[V](t: ptr[mut T], actual: V, unexpected: V, message #format(actual, unexpected) : string, location := #caller_location) -> bool {
    if actual != unexpected {
        return true
    }
    record_formatted(t, message, any.[actual, unexpected], detail_of(string.["expected anything but ", ""], any.[unexpected]), location)
    return false
}

/**
 * Check that a value is less than a bound.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param bound What it has to be less than; of the same type, ordered with <.
 * @param message Why it should be: a format string, %1 actual and %2 bound.
 * @param location Where the check is; the caller's own.
 * @return True if actual < bound; false, the failure recorded, if not.
 */
expect_lt :: fn[V](t: ptr[mut T], actual: V, bound: V, message #format(actual, bound) : string, location := #caller_location) -> bool {
    if actual < bound {
        return true
    }
    record_formatted(t, message, any.[actual, bound], detail_of(string.["expected less than ", ", got ", ""], any.[bound, actual]), location)
    return false
}

/**
 * Check that a value is at most a bound.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param bound What it has to be at most; of the same type, ordered with <=.
 * @param message Why it should be: a format string, %1 actual and %2 bound.
 * @param location Where the check is; the caller's own.
 * @return True if actual <= bound; false, the failure recorded, if not.
 */
expect_le :: fn[V](t: ptr[mut T], actual: V, bound: V, message #format(actual, bound) : string, location := #caller_location) -> bool {
    if actual <= bound {
        return true
    }
    record_formatted(t, message, any.[actual, bound], detail_of(string.["expected at most ", ", got ", ""], any.[bound, actual]), location)
    return false
}

/**
 * Check that a value is more than a bound.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param bound What it has to be more than; of the same type, ordered with >.
 * @param message Why it should be: a format string, %1 actual and %2 bound.
 * @param location Where the check is; the caller's own.
 * @return True if actual > bound; false, the failure recorded, if not.
 */
expect_gt :: fn[V](t: ptr[mut T], actual: V, bound: V, message #format(actual, bound) : string, location := #caller_location) -> bool {
    if actual > bound {
        return true
    }
    record_formatted(t, message, any.[actual, bound], detail_of(string.["expected more than ", ", got ", ""], any.[bound, actual]), location)
    return false
}

/**
 * Check that a value is at least a bound.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param bound What it has to be at least; of the same type, ordered with >=.
 * @param message Why it should be: a format string, %1 actual and %2 bound.
 * @param location Where the check is; the caller's own.
 * @return True if actual >= bound; false, the failure recorded, if not.
 */
expect_ge :: fn[V](t: ptr[mut T], actual: V, bound: V, message #format(actual, bound) : string, location := #caller_location) -> bool {
    if actual >= bound {
        return true
    }
    record_formatted(t, message, any.[actual, bound], detail_of(string.["expected at least ", ", got ", ""], any.[bound, actual]), location)
    return false
}

/**
 * Check that a value is within a range, both ends included.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param low The least it may be.
 * @param high The most it may be; of the same type as actual and low, ordered with <=.
 * @param message Why it should be: a format string, %1 actual, %2 low and %3 high.
 * @param location Where the check is; the caller's own.
 * @return True if low <= actual <= high; false, the failure recorded, if not.
 */
expect_within :: fn[V](t: ptr[mut T], actual: V, low: V, high: V, message #format(actual, low, high) : string, location := #caller_location) -> bool {
    if low <= actual && actual <= high {
        return true
    }
    record_formatted(t, message, any.[actual, low, high], detail_of(string.["expected ", " to ", ", got ", ""], any.[low, high, actual]),
        location)
    return false
}

/**
 * Check that two views hold the same items, in order.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param expected What it should have held; items of the same type, comparable with ==.
 * @param message Why they should be the same: a format string, %1 actual and %2 expected.
 * @param location Where the check is; the caller's own.
 * @return True if they have the same count and items; false, the failure recorded with both counts or the first
 *     index that differs and both items there, if not.
 */
expect_same_items :: fn[V](t: ptr[mut T], actual: V[], expected: V[], message #format(actual, expected) : string, location := #caller_location) -> bool {
    if actual.count != expected.count {
        record_formatted(t, message, any.[actual, expected], detail_of(string.["expected ", " items, got ", ""], any.[expected.count, actual.count]), location)
        return false
    }
    for item, i in actual {
        if i < expected.count && item != expected[i] {
            record_formatted(t, message, any.[actual, expected], detail_of(string.["at ", ", expected ", ", got ", ""],
                any.[i, expected[i], item]), location)
            return false
        }
    }
    return true
}

/**
 * Check that a result is Ok, reporting its error if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param result The result, of any Result type.
 * @param message Why it should succeed: a format string, %1 the result.
 * @param location Where the check is; the caller's own.
 * @return True if it was Ok; false, the failure recorded, if not.
 */
expect_ok :: fn[V, E](t: ptr[mut T], result: Result[V, E], message #format(result) : string, location := #caller_location) -> bool {
    match result {
        case Ok => return true
        case Error(error) => {
            record_formatted(t, message, any.[result], detail_of(string.["expected Ok, got Error(", ")"], any.[error]), location)
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
 * @param message Why it should fail so: a format string, %1 the result and %2 wanted.
 * @param location Where the check is; the caller's own.
 * @return True if it was Error(wanted); false, the failure recorded, if it was Ok or another error.
 */
expect_error :: fn[V, E](t: ptr[mut T], result: Result[V, E], wanted: E, message #format(result, wanted) : string, location := #caller_location) -> bool {
    match result {
        case Ok => {
            record_formatted(t, message, any.[result, wanted], detail_of(string.["expected Error(", "), got Ok"], any.[wanted]), location)
        }
        case Error(error) => {
            if error == wanted {
                return true
            }
            record_formatted(t, message, any.[result, wanted], detail_of(string.["expected Error(", "), got Error(", ")"], any.[wanted, error]), location)
        }
    }
    return false
}

/**
 * Check that a result is an error, any of them.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param result The result, of any Result type.
 * @param message Why it should fail: a format string, %1 the result.
 * @param location Where the check is; the caller's own.
 * @return True if it was an Error; false, the failure recorded with what it held, if it was Ok.
 */
expect_any_error :: fn[V, E](t: ptr[mut T], result: Result[V, E], message #format(result) : string, location := #caller_location) -> bool {
    if result is_error {
        return true
    }
    // What the Ok held, written as Ok(...); a Result[void, E]'s holds nothing
    #if size_of(V) == 0 {
        record_formatted(t, message, any.[result], text_from("expected an error, got Ok"), location)
    }
    #else {
        match result {
            case Ok(held) => record_formatted(t, message, any.[result], detail_of(string.["expected an error, got Ok(", ")"], any.[held]), location)
            case Error(error) => {}
        }
    }
    return false
}

/**
 * Check that a result is one of several errors.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param result The result, of any Result type whose error is comparable with ==.
 * @param errors The errors any of which will do.
 * @param message Why it should fail so: a format string, %1 the result and %2 errors.
 * @param location Where the check is; the caller's own.
 * @return True if it was an Error among errors; false, the failure recorded, if it was Ok or another error.
 */
expect_error_in :: fn[V, E](t: ptr[mut T], result: Result[V, E], errors: E[], message #format(result, errors) : string,
    location := #caller_location) -> bool {

    match result {
        case Ok => {
            record_formatted(t, message, any.[result, errors], detail_of(string.["expected one of ", ", got Ok"], any.[errors]), location)
        }
        case Error(error) => {
            for each in errors {
                if each == error {
                    return true
                }
            }
            record_formatted(t, message, any.[result, errors], detail_of(string.["expected one of ", ", got Error(", ")"], any.[errors, error]), location)
        }
    }
    return false
}

/**
 * Check that an optional holds a value.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param optional The optional, of any type.
 * @param message Why it should hold one: a format string, %1 the optional.
 * @param location Where the check is; the caller's own.
 * @return True if it held one; false, the failure recorded, if it was empty.
 */
expect_some :: fn[V](t: ptr[mut T], optional: V?, message #format(optional) : string, location := #caller_location) -> bool {
    if optional is_some {
        return true
    }
    record_formatted(t, message, any.[optional], text_from("expected a value, got none"), location)
    return false
}

/**
 * Check that an optional is empty, reporting what it held if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param optional The optional, of any type.
 * @param message Why it should be empty: a format string, %1 the optional.
 * @param location Where the check is; the caller's own.
 * @return True if it was empty; false, the failure recorded, if it held a value.
 */
expect_none :: fn[V](t: ptr[mut T], optional: V?, message #format(optional) : string, location := #caller_location) -> bool {
    match optional {
        case Some(value) => {
            record_formatted(t, message, any.[optional], detail_of(string.["expected none, got ", ""], any.[value]), location)
            return false
        }
        case None => return true
    }
}

/**
 * Record a failure unconditionally, for a path a test shouldn't reach.
 *
 * @param t The test's state, which the failure is recorded in.
 * @param message What went wrong, for whoever reads the failure; plain text.
 * @param location Where it failed; the caller's own.
 */
fail :: fn(t: ptr[mut T], message: string, location := #caller_location) {
    record(t, message, "", location)
}

/**
 * Skip the rest of a test, as what it tests isn't there: it's reported as skipped with the reason, and counted apart
 * from those that passed and failed. One that failed before it skipped is reported as failed.
 *
 * @param t The test's state, marked skipped.
 * @param reason Why, like "no system volume"; cut at TEXT_BYTES.
 * @return Error(Skipped), for the test to return: return testing.skip(t, "no disk").
 */
skip :: fn(t: ptr[mut T], reason: string) -> Outcome {
    t.skipped = true
    t.skip_reason = text_from(reason)
    return .Error(.Skipped)
}

/**
 * Add a note to every failure from here until end_note: what case or input a test is on, like "case % of %", so a
 * failure in a loop or a helper says which. Notes nest, the newest last, and are kept in fixed space.
 *
 * @param t The test's state, whose notes grow by one; past MAX_NOTES it's counted, not kept.
 * @param format_string The note, each % replaced by the next value, as text_buffer's append_format does.
 * @param values The values for its placeholders.
 */
note :: fn(t: ptr[mut T], format_string: string, values: any...) {
    index :: t.note_count
    t.note_count += 1
    if index >= t.notes.count {
        return void
    }
    storage : u8[TEXT_BYTES]
    text := text_buffer.make(storage)
    text_buffer.append_format(&text, format_string, values)
    t.notes[index] = text_from(text_buffer.as_string(&text))
}

/**
 * End the newest note, as note added it.
 *
 * @param t The test's state, whose notes shrink by one; none to end does nothing.
 */
end_note :: fn(t: ptr[mut T]) {
    if t.note_count > 0 {
        t.note_count -= 1
    }
}

/**
 * Turn whether an expect_ assertion held into an Outcome, for its require_ form, as a test's own assertions can too.
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
 * @param message Why it should be, for whoever reads a failure; plain text.
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
 * @param message As expect_eq's.
 * @param location Where the check is; the caller's own.
 * @return Ok if they were equal; Error(Failed), the failure recorded, if not.
 */
require_eq :: fn[V](t: ptr[mut T], actual: V, expected: V, message #format(actual, expected) : string, location := #caller_location) -> Outcome {
    return outcome_of(expect_eq(t, actual, expected, message, location))
}

/**
 * Require two values to differ, as expect_ne checks, ending the test with ? if they don't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param unexpected What it mustn't be.
 * @param message As expect_ne's.
 * @param location Where the check is; the caller's own.
 * @return Ok if they differed; Error(Failed), the failure recorded, if not.
 */
require_ne :: fn[V](t: ptr[mut T], actual: V, unexpected: V, message #format(actual, unexpected) : string, location := #caller_location) -> Outcome {
    return outcome_of(expect_ne(t, actual, unexpected, message, location))
}

/**
 * Require a value less than a bound, as expect_lt checks, ending the test with ? if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param bound What it has to be less than.
 * @param message As expect_lt's.
 * @param location Where the check is; the caller's own.
 * @return Ok if it was; Error(Failed), the failure recorded, if not.
 */
require_lt :: fn[V](t: ptr[mut T], actual: V, bound: V, message #format(actual, bound) : string, location := #caller_location) -> Outcome {
    return outcome_of(expect_lt(t, actual, bound, message, location))
}

/**
 * Require a value at most a bound, as expect_le checks, ending the test with ? if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param bound What it has to be at most.
 * @param message As expect_le's.
 * @param location Where the check is; the caller's own.
 * @return Ok if it was; Error(Failed), the failure recorded, if not.
 */
require_le :: fn[V](t: ptr[mut T], actual: V, bound: V, message #format(actual, bound) : string, location := #caller_location) -> Outcome {
    return outcome_of(expect_le(t, actual, bound, message, location))
}

/**
 * Require a value more than a bound, as expect_gt checks, ending the test with ? if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param bound What it has to be more than.
 * @param message As expect_gt's.
 * @param location Where the check is; the caller's own.
 * @return Ok if it was; Error(Failed), the failure recorded, if not.
 */
require_gt :: fn[V](t: ptr[mut T], actual: V, bound: V, message #format(actual, bound) : string, location := #caller_location) -> Outcome {
    return outcome_of(expect_gt(t, actual, bound, message, location))
}

/**
 * Require a value at least a bound, as expect_ge checks, ending the test with ? if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param bound What it has to be at least.
 * @param message As expect_ge's.
 * @param location Where the check is; the caller's own.
 * @return Ok if it was; Error(Failed), the failure recorded, if not.
 */
require_ge :: fn[V](t: ptr[mut T], actual: V, bound: V, message #format(actual, bound) : string, location := #caller_location) -> Outcome {
    return outcome_of(expect_ge(t, actual, bound, message, location))
}

/**
 * Require a value within a range, as expect_within checks, ending the test with ? if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param low The least it may be.
 * @param high The most it may be.
 * @param message As expect_within's.
 * @param location Where the check is; the caller's own.
 * @return Ok if it was; Error(Failed), the failure recorded, if not.
 */
require_within :: fn[V](t: ptr[mut T], actual: V, low: V, high: V, message #format(actual, low, high) : string, location := #caller_location) -> Outcome {
    return outcome_of(expect_within(t, actual, low, high, message, location))
}

/**
 * Require two views to hold the same items, as expect_same_items checks, ending the test with ? if they don't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param actual What the code under test gave.
 * @param expected What it should have held.
 * @param message As expect_same_items's.
 * @param location Where the check is; the caller's own.
 * @return Ok if they did; Error(Failed), the failure recorded, if not.
 */
require_same_items :: fn[V](t: ptr[mut T], actual: V[], expected: V[], message #format(actual, expected) : string, location := #caller_location) -> Outcome {
    return outcome_of(expect_same_items(t, actual, expected, message, location))
}

/**
 * Require a result to be Ok, giving its value, as expect_ok checks; ending the test with ? if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param result The result, of any Result type; one of Result[void, E] gives Ok with nothing.
 * @param message As expect_ok's.
 * @param location Where the check is; the caller's own.
 * @return The Ok value; Error(Failed), the failure recorded with the error, if it was an Error.
 */
require_ok :: fn[V, E](t: ptr[mut T], result: Result[V, E], message #format(result) : string, location := #caller_location) -> Result[V, Stopped] {
    // A Result[void, E]'s Ok holds nothing, so it's checked without taking a value out
    #if size_of(V) == 0 {
        if expect_ok(t, result, message, location) {
            return .Ok
        }
        return .Error(.Failed)
    }
    #else {
        match result {
            case Ok(value) => return .Ok(value)
            case Error(error) => {
                _ = expect_ok(t, result, message, location)
                return .Error(.Failed)
            }
        }
    }
}

/**
 * Require a result to be a particular error, as expect_error checks, ending the test with ? if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param result The result, of any Result type whose error is comparable with ==.
 * @param wanted The error it should be.
 * @param message As expect_error's.
 * @param location Where the check is; the caller's own.
 * @return Ok if it was Error(wanted); Error(Failed), the failure recorded, if not.
 */
require_error :: fn[V, E](t: ptr[mut T], result: Result[V, E], wanted: E, message #format(result, wanted) : string, location := #caller_location) -> Outcome {
    return outcome_of(expect_error(t, result, wanted, message, location))
}

/**
 * Require a result to be an error, any of them, as expect_any_error checks, ending the test with ? if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param result The result, of any Result type.
 * @param message As expect_any_error's.
 * @param location Where the check is; the caller's own.
 * @return Ok if it was an Error; Error(Failed), the failure recorded, if it was Ok.
 */
require_any_error :: fn[V, E](t: ptr[mut T], result: Result[V, E], message #format(result) : string, location := #caller_location) -> Outcome {
    return outcome_of(expect_any_error(t, result, message, location))
}

/**
 * Require a result to be one of several errors, as expect_error_in checks, ending the test with ? if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param result The result, of any Result type whose error is comparable with ==.
 * @param errors The errors any of which will do.
 * @param message As expect_error_in's.
 * @param location Where the check is; the caller's own.
 * @return Ok if it was; Error(Failed), the failure recorded, if not.
 */
require_error_in :: fn[V, E](t: ptr[mut T], result: Result[V, E], errors: E[], message #format(result, errors) : string,
    location := #caller_location) -> Outcome {

    return outcome_of(expect_error_in(t, result, errors, message, location))
}

/**
 * Require an optional to hold a value, giving it, as expect_some checks; ending the test with ? if it's empty.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param optional The optional, of any type.
 * @param message As expect_some's.
 * @param location Where the check is; the caller's own.
 * @return The value; Error(Failed), the failure recorded, if it was empty.
 */
require_some :: fn[V](t: ptr[mut T], optional: V?, message #format(optional) : string, location := #caller_location) -> Result[V, Stopped] {
    match optional {
        case Some(value) => return .Ok(value)
        case None => {
            _ = expect_some(t, optional, message, location)
            return .Error(.Failed)
        }
    }
}

/**
 * Require an optional to be empty, as expect_none checks, ending the test with ? if it isn't.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param optional The optional, of any type.
 * @param message As expect_none's.
 * @param location Where the check is; the caller's own.
 * @return Ok if it was empty; Error(Failed), the failure recorded, if it held a value.
 */
require_none :: fn[V](t: ptr[mut T], optional: V?, message #format(optional) : string, location := #caller_location) -> Outcome {
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
 * Give "s" for a count that isn't one, for the summary's words.
 *
 * @param count How many there are.
 * @return "" for 1, "s" for any other count.
 */
plural :: fn(count: usize) -> string {
    return if count == 1 { "" } else { "s" }
}

/**
 * Run tests in order, each with a fresh T, reporting each as it ends and a summary after.
 *
 * For each test: "test <name> ... ok"; "test <name> ... skipped: <reason>"; or "test <name> ... FAILED" then, for each
 * failure kept, its file and line and message, the values found and the notes in force, indented beneath; "and N more
 * failures" past MAX_FAILURES. Last, "N tests: P passed, F failed", with ", S skipped" when some skipped themselves and
 * ", L filtered out" when the filter left some out.
 *
 * @param tests The tests, as tests_of makes them.
 * @param reporter Where the report goes.
 * @param filter Only tests whose names contain it are run; empty runs every test.
 * @return How many tests failed: 0 when all that ran passed or skipped themselves.
 */
run :: fn(tests: Test[], reporter: Reporter, filter: string = "") -> usize {
    passed_count : usize = 0
    failed_count : usize = 0
    skipped_count : usize = 0
    filtered : usize = 0
    for test in tests {
        if !contains(test.name, filter) {
            filtered += 1
            continue
        }
        t := T.{name = test.name}
        _ = test.run(&t)
        if t.failure_count == 0 && t.skipped {
            skipped_count += 1
            report(reporter, "test % ... skipped: %", test.name, text_of(&t.skip_reason))
            continue
        }
        if t.failure_count == 0 {
            passed_count += 1
            report(reporter, "test % ... ok", test.name)
            continue
        }
        failed_count += 1
        report(reporter, "test % ... FAILED", test.name)
        for &failure, i in t.failures {
            if i >= t.failure_count {
                break
            }
            report(reporter, "    %:%: %", failure.location.file_path, failure.location.line, text_of(&failure.message))
            if failure.detail.count > 0 {
                report(reporter, "        %", text_of(&failure.detail))
            }
            if failure.notes.count > 0 {
                report(reporter, "        note: %", text_of(&failure.notes))
            }
        }
        if t.failure_count > t.failures.count {
            more :: t.failure_count - t.failures.count
            report(reporter, "    and % more failure%", more, plural(more))
        }
    }
    total :: passed_count + failed_count + skipped_count
    storage : u8[128]
    summary := text_buffer.make(storage)
    text_buffer.append_format(&summary, "% test%: % passed, % failed", total, plural(total), passed_count, failed_count)
    if skipped_count > 0 {
        text_buffer.append_format(&summary, ", % skipped", skipped_count)
    }
    if filtered > 0 {
        text_buffer.append_format(&summary, ", % filtered out", filtered)
    }
    report(reporter, "%", text_buffer.as_string(&summary))
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

/**
 * A report caught in the caller's bytes, to be compared, kept, or passed on only if something failed
 * (report_text, reporter_of).
 */
BufferReporter :: struct #scoped {
    /** Where the report goes, the caller's; what doesn't fit is dropped. */
    bytes : mut u8[],
    /** How many of bytes hold the report. */
    count : usize,
    /** Whether some of the report didn't fit. */
    truncated : bool,
}

/**
 * Catch report lines in a BufferReporter, as a Reporter's write.
 *
 * @param target The BufferReporter, which lasts while run does.
 * @param text The line, appended as it is.
 */
write_buffer :: fn(target: rawptr, text: string) {
    buffer :: cast[ptr[mut BufferReporter]](target)
    for character in text {
        if buffer.count >= buffer.bytes.count {
            buffer.truncated = true
            return void
        }
        buffer.bytes[buffer.count] = cast[u8](character)
        buffer.count += 1
    }
}

/**
 * Make a reporter that catches the report in a buffer.
 *
 * @param buffer The buffer, which has to last while the reporter is used; what it's caught is added after what it has.
 * @return The reporter, for run.
 */
reporter_of :: fn(buffer: ptr[mut BufferReporter]) -> Reporter {
    return Reporter.{target = cast[rawptr](buffer), write = write_buffer}
}

/**
 * Give what a buffer has caught.
 *
 * @param buffer The buffer, only read.
 * @return The report so far, a view of its bytes, good while it's unchanged; "" for none.
 */
report_text :: fn(buffer: ptr[BufferReporter]) -> string {
    if buffer.count == 0 || buffer.count > buffer.bytes.count {
        return ""
    }
    return string_of(&buffer.bytes[0], buffer.count)
}

/**
 * Pass a caught report on, whole, only if some test failed: for a program whose output is compared, which shows the
 * report only when it says something.
 *
 * @param buffer The caught report, only read.
 * @param failed What run gave, how many tests failed.
 * @param out Where the report goes when failed isn't 0.
 */
write_report_if_failed :: fn(buffer: ptr[BufferReporter], failed: usize, out: Reporter) {
    if failed > 0 {
        out.write(out.target, report_text(buffer))
    }
}
