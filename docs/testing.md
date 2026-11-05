# Testing

A test is a function marked `#test`. It takes the test's state, `t`, and says what it expects through `std/testing`'s
assertions, each of which records a failure with a message, where it was, and the values involved, so a failed run
says what went wrong rather than only that something did. A runner finds a package's tests through compile-time
reflection and runs each, reporting to wherever the program can write: standard output for a hosted program, or a
sink the program gives, down to a kernel's console.

```
import testing from "std"

parses_a_duration #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    parsed :: testing.require_ok(t, parse_duration("1h30m"), "a duration with two units")?
    testing.expect_eq(t, parsed.seconds, 5400, "an hour and a half, in seconds")
    testing.expect_any_error(t, parse_duration(""), "nothing isn't a duration")
    return .Ok
}
```

## Tests

`#test` goes after a function's name, like `#export`. A test function:

* takes one parameter, `t: ptr[mut testing.T]`, the state its assertions record into, which it passes on to helpers
  that assert too;
* returns `testing.Outcome`, a `Result[void, testing.Stopped]`, so a `require_` assertion followed by `?` ends it;
* isn't generic, and needn't be exported.

A function marked `#test` whose signature is anything else is an error where the runner's table is made (`tests_of`),
at the function.

### Tests Over Cases

`#test(CASES)` runs a test once for each case of `CASES`, a constant fixed array of the test's package, and each run
is a test of its own: it passes, fails, skips and is filtered by itself, and a `require_` assertion ends only its own
case. The function takes the case after `t`:

```
DIGESTS :: Digest.[
    Digest.{name = "empty", input = "", hex = "e3b0c442..."},
    Digest.{name = "abc", input = "abc", hex = "ba7816bf..."},
]

hashes_to_the_published_digest #test(DIGESTS) :: fn(t: ptr[mut testing.T], item: Digest) -> testing.Outcome {
    testing.expect_eq(t, hex_of(sha256(item.input)), item.hex, "the digest is the one published")
    return .Ok
}
```

Each case's test is named after the function and the case: by the case's `name`, when its type has a `name` string,
like `hashes_to_the_published_digest[abc]`, or by its index otherwise, like `squares[2]`. A filter of `[abc]` runs
that case alone. The cases' type has to be the second parameter's; anything else is an error at the function.

Tests sit beside the code they test, in its package, or in a test package of their own that imports it. They're
compiled only into programs that ask for them: an ordinary build leaves them out like any function nothing calls.

## Assertions

Every assertion takes `t` first and a message last: why the check holds, said for whoever reads the failure. Its
location is the caller's (`#caller_location`), so a failure points at the line that asserted.

| Assertion | Fails when |
|---|---|
| `expect(t, condition, message)` | `condition` is false |
| `expect_eq(t, actual, expected, message)` | `actual != expected` |
| `expect_ne(t, actual, unexpected, message)` | `actual == unexpected` |
| `expect_lt`, `expect_le`, `expect_gt`, `expect_ge(t, actual, bound, message)` | `actual` isn't `<`, `<=`, `>`, `>=` `bound` |
| `expect_within(t, actual, low, high, message)` | `actual` is outside `low` to `high`, both included |
| `expect_same_items(t, actual, expected, message)` | two views differ in count, or at an index, which is reported |
| `expect_ok(t, result, message)` | `result` is an `Error`, whose error is reported |
| `expect_error(t, result, wanted, message)` | `result` is `Ok`, or an `Error` other than `wanted` |
| `expect_error_in(t, result, errors, message)` | `result` is `Ok`, or an `Error` not among `errors` |
| `expect_any_error(t, result, message)` | `result` is `Ok`, whose value is reported |
| `expect_some(t, optional, message)` / `expect_none` | the optional is empty / isn't |
| `fail(t, message)` | always |

`expect_` assertions record the failure and let the test go on, so one run reports every check that failed. Each has a
`require_` form, which returns `testing.Outcome` (and for `require_ok` and `require_some`, the value inside), to be
followed by `?`: a failure ends the test there, for when what follows can't go on without it.

```
file :: testing.require_ok(t, os.open(path, .READ), "the fixture is there")?   // stops if it isn't
```

What was found is reported under the message, the values written as `%` writes them, so any type that formats can be
compared: `expected 5400, got 5300`. A string is written in double quotes, with its quotes, backslashes and control
characters escaped, so an empty one, or one with a trailing space, can be seen: `expected "a", got ""`.

### Messages That Format the Values

The message of an assertion over values is a format string over them (docs/format_strings.md): `%1`, `%2` and on are
the values under test, in the assertion's order, with any options. A message that uses one says what was found
itself, so the automatic line is left out:

```
testing.expect_lt(t, mask, LIMIT, "%1{08x} is below the limit %2{08x}")   // 0000ff35 is below the limit 0000ff31
```

For `expect_eq` they're the actual value then the expected, for `expect_within` the value, then the low and high ends,
and for the assertions over one result or optional, `%1` is it. A literal percent sign is `%%`. The message is checked
where it's written in place, as `log_info`'s are: a placeholder past the values, or options a value's type can't take,
is an error. `expect`, `fail` and `require` have no values, so their messages are plain text.

This comes from `#format` on a function's string parameter, which names the parameters it formats. A function of a
program's own can use it too:

```
check_less :: fn(actual: int, bound: int, message #format(actual, bound) : string) -> bool
```

### Notes

A failure in a loop, or in a helper, can say which case it was on with a note (for cases that should each be a test of
their own, see [Tests Over Cases](#tests-over-cases)): `testing.note(t, format, values...)`
adds a line that every failure from there on reports, until `testing.end_note(t)` takes it away. Notes nest, the
newest last.

```
for case, i in CASES {
    testing.note(t, "case % of %: %", i + 1, CASES.count, case.name)
    testing.expect_eq(t, hex_of(hash(case.input)), case.digest, "the digest is the one published")
    testing.end_note(t)
}
```

```
    hashes.hsc:88: the digest is the one published
        expected "ba7816bf8f01", got "3c1b8a6d7e20"
        note: case 7 of 12: two blocks
```

### Assertions of Your Own

An assertion is a function that checks something, records a failure with `testing.record(t, message, detail,
location)`, and gives back whether it held. It takes `location := #caller_location` and passes it on, so the failure
points at its caller's line rather than its own, and its `require_` form is `testing.outcome_of(held)`:

```
expect_sorted :: fn(t: ptr[mut testing.T], values: int[], message: string, location := #caller_location) -> bool {
    for value, i in values {
        if i > 0 && i < values.count && values[i - 1] > value {
            testing.record(t, message, "out of order", location)
            return false
        }
    }
    return true
}
```

### State Past the Test

`t` belongs to the runner's stack, and lasts as long as the test does. Code the test starts and waits for, like a
fiber or a callback, can be handed it and record into it; the test returns only once that code is done with it.
Something that outlives the test can't keep `t`.

### Skipping

A test that can't run, because what it tests isn't there, skips itself: `return testing.skip(t, "no system volume")`.
It's reported as skipped with the reason, and counted apart from those that passed or failed, so a summary still says
how many tests there were. A test that failed before skipping is reported as failed.

### Fixed Space

Nothing allocates: a test's failures go into fixed space in `T`, the first `testing.MAX_FAILURES` of them in full and
a count of any more, each message, value and note cut at `testing.TEXT_BYTES`, and up to `testing.MAX_NOTES` notes at
once. So assertions work in freestanding code with no allocator, like a kernel's.

## Running Tests

`hemera --test <package>` builds a program whose entry runs every `#test` function in the package, in the order
they're declared, and reports to standard output:

```
test parses_a_duration ... ok
test rejects_negative ... FAILED
    durations.hsc:41: a negative duration is refused
        expected Error(Negative), got Ok(-60)
test reads_the_zone_files ... skipped: no zoneinfo
3 tests: 1 passed, 1 failed, 1 skipped
```

Its exit code is 0 when no test failed and 1 otherwise. `--test-filter=text` runs only the tests whose names contain
`text`; the summary says how many it left out, as `, 2 filtered out`. A build package asks for the same with
`BuildOptions.test` and `test_filter`.

A program with an entry of its own, like a kernel or a program run under another operating system's test harness,
runs its tests itself:

```
tests :: #insert testing.tests_of(compiler.load_package("."))
failed :: testing.run(tests, reporter)
```

* `testing.tests_of(package, file)` is compile-time code that gives a `testing.Test[]` literal: each `#test` function
  of `package`, in the order it declares them, reached by its name, so it's inserted in the tests' own package. Given
  a file, like `"accounts_check.hsc"`, only that file's tests: for checks kept in one file of a bigger package. It
  reports a `#test` function with the wrong signature as an error.
* `testing.run(tests, reporter, filter)` runs each test whose name contains `filter` with a fresh `T`, reports it,
  and gives how many failed.
* A `testing.Reporter` is where lines go: a function taking text, and a target for it. `testing.STANDARD_OUTPUT`
  writes to standard output; a kernel gives one writing to its console, a service one writing to its log. Lines are
  in the form above, so a script reading them can tell what passed and what didn't without exit codes.
* A `testing.BufferReporter` catches the report in bytes the caller gives (`testing.reporter_of(&buffer)`), to be
  compared (`testing.report_text`), or passed on only if a test failed (`testing.write_report_if_failed`), for a
  program whose output is compared and shouldn't show a report that says all is well.
