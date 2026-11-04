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
    testing.expect(t, parse_duration("") is_error, "nothing isn't a duration")
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
| `expect_ok(t, result, message)` | `result` is an `Error`, whose error is reported |
| `expect_error(t, result, wanted, message)` | `result` is `Ok`, or an `Error` other than `wanted` |
| `expect_some(t, optional, message)` / `expect_none` | the optional is empty / isn't |
| `fail(t, message)` | always |

`expect_` assertions record the failure and let the test go on, so one run reports every check that failed. Each has a
`require_` form, which returns `testing.Outcome` (and for `require_ok` and `require_some`, the value inside), to be
followed by `?`: a failure ends the test there, for when what follows can't go on without it.

```
file :: testing.require_ok(t, os.open(path, .READ), "the fixture is there")?   // stops if it isn't
```

The values compared are written with `%`, as `text_buffer`'s formatting writes them, so any type that formats can be
compared, and what's reported is what was there: `expected 5400, got 5300`.

Nothing allocates: a test's failures go into fixed space in `T`, the first `testing.MAX_FAILURES` of them in full and
a count of any more, each message and value cut at `testing.TEXT_BYTES`. So assertions work in freestanding code with
no allocator, like a kernel's.

## Running Tests

`hemera --test <package>` builds a program whose entry runs every `#test` function in the package, in the order
they're declared, and reports to standard output:

```
test parses_a_duration ... ok
test rejects_negative ... FAILED
    durations.hsc:41: a negative duration is refused
        expected Error(Negative), got Ok(-60)
2 tests: 1 passed, 1 failed
```

Its exit code is 0 when every test passed and 1 otherwise. `--test-filter=text` runs only the tests whose names
contain `text`.

A program with an entry of its own, like a kernel or a program run under another operating system's test harness,
runs its tests itself:

```
tests :: #insert testing.tests_of(compiler.load_package("."))
failed :: testing.run(tests, reporter)
```

* `testing.tests_of(package)` is compile-time code that gives a `testing.Test[]` literal: each `#test` function of
  `package`, in the order it declares them, reached by its name, so it's inserted in the tests' own package. It
  reports a `#test` function with the wrong signature as an error.
* `testing.run(tests, reporter, filter)` runs each test whose name contains `filter` with a fresh `T`, reports it,
  and gives how many failed.
* A `testing.Reporter` is where lines go: a function taking text, and a target for it. `testing.STANDARD_OUTPUT`
  writes to standard output; a kernel gives one writing to its console, a service one writing to its log. Lines are
  in the form above, so a script reading them can tell what passed and what didn't without exit codes.
