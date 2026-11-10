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

### Property Tests

A property test checks something that should hold for every input, on inputs it draws: it takes a
`source: ptr[mut testing.Source]` after `t`, and the runner calls it on case after case, 100 by default.

```
reverses_back #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    words :: testing.draw[u32[8]](source)
    testing.expect_eq(t, reverse(reverse(words)), words, "reversing twice gives the words back")
    return .Ok
}
```

| Draw | Gives |
|---|---|
| `draw[V](source)` | Any value of a type made of numbers, booleans, characters and enums: those alone, or in structs, fixed arrays, vectors and unions. Integers and floats favor their edges now and then: 0, 1, the least and the most, and for floats the infinities and NaN |
| `draw_between(source, low, high)` | An integer from `low` to `high`, both included |
| `draw_below(source, bound)` | A `u64` from 0 to `bound - 1` |
| `draw_bool(source)` | A boolean |
| `draw_count(source, most)` | A count from 0 to `most`, for a test that draws that many things itself |
| `draw_bytes(source, most)` | Up to `most` bytes, a view of the source's own that lasts until the case ends |

A type holding a string, a pointer, a view, a dynamic array, an `any` or a function can't be drawn, as there's nothing
to say what it should point to or how much there should be; drawing one is a failure at the draw. A test draws what
such a value holds, and builds it.

A case is the bytes its draws read, fresh random ones from a seed. When a case fails, the runner makes it as small as
it can while it still fails, taking bytes out and lowering them, then runs the test on that once more, and reports that
run: each failure with the values drawn, and how the case was found.

```
test stays_below_500 ... FAILED
    limits.hsc:59: the value is below 500
        expected less than 500, got 500
        note: drew 500
    found by case 2 of 100 (seed 7), shrunk from 2 bytes to 2 in 63 runs
```

Every draw reads bytes so that fewer and lower bytes give smaller values, and zeros the smallest, so shrinking the
bytes shrinks the values, however they were drawn and built, with nothing for a test to write. Each test draws from its
own seed, from its name, the same in every run, so a failure comes back until it's fixed; `--test-seed=N` draws every
test's cases from another, and `--test-runs=N` draws more or fewer of them.

A case that doesn't fit what the test checks is discarded with `testing.assume(t, condition, why)?`, and drawn again;
a test whose cases are all discarded is skipped. A property test can't have cases of its own (`#test(CASES)`), and it
can't keep its source, or what it drew from it, past its return. A case reads at most `testing.MAX_CASE_BYTES`, 1024;
past them, every draw gives zeros. The same test can be fuzzed ([Fuzzing](#fuzzing)).

Something costly to make that every case starts from, like a volume's image, is a fixture, made on the first case that
asks and kept until the last:

```
volume_survives_damage #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    image :: testing.require_some(t, testing.fixture[Image](source, make_image, free_image), "the image is made")?
    ...   // damage it as drawn, use it, and put it back as it was
}
```

`make` gives the fixture, or null to be asked again by the next case; `release` gives back what it holds once the run
ends: after the test's cases and the shrinking of a failing one, or when fuzzing stops. Each case has to leave the
fixture as it found it, so a case gives the same result whichever ran before it, as shrinking and replaying need.

### Tags

`#tags(...)` after `#test` names a test's tags: constants of type `testing.Tag`, each a name a run asks for it by, and
whether its tests run when a run doesn't ask. A misspelled tag is an undeclared name, rather than a tag nothing asks
for. A test can have up to `testing.MAX_TAGS`.

```
NETWORK :: testing.Tag.{name = "network", by_default = .Included}

downloads_the_index #test #tags(NETWORK, testing.SLOW) :: fn(t: ptr[mut testing.T]) -> testing.Outcome { ... }
```

`std/testing` has `testing.SLOW` and `testing.PERFORMANCE`, both left out of a run unless it asks for them. A run's
tags are words separated by commas, as `--test-tags` takes them:

| Words | Run |
|---|---|
| (none) | Each test none of whose tags is left out by default |
| `+slow` | The slow tests too |
| `-network` | Not the tests tagged `network` |
| `all` | Every tag's tests, less those a `-` word leaves out |
| `performance` | Only the tests with a bare word's tag, whatever its default, less those a `-` word leaves out |

A test the tags leave out is counted apart, as `, 2 left out by tag`, so a summary always says something didn't run.

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
once, and a property test's cases go in `testing.Case`s on the runner's stack, a few at once while one is shrunk. So
tests work in freestanding code with no allocator, like a kernel's.

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
`text`; the summary says how many it left out, as `, 2 filtered out`. `--test-tags` says which tags' tests run
([Tags](#tags)), and `--test-seed` and `--test-runs` which cases property tests draw, and how many. A build package
asks for the same with `BuildOptions.test`, `test_filter`, `test_tags`, `test_seed` and `test_runs`.

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
* `testing.run(tests, reporter, options)` runs each test `options` includes with a fresh `T`, reports it, and gives
  how many failed. `testing.RunOptions` has the filter, tags, seed and runs `--test` takes; its zero value runs every
  test not left out by a tag.
* A `testing.Reporter` is where lines go: a function taking text, and a target for it. `testing.STANDARD_OUTPUT`
  writes to standard output; a kernel gives one writing to its console, a service one writing to its log. Lines are
  in the form above, so a script reading them can tell what passed and what didn't without exit codes.
* A `testing.BufferReporter` catches the report in bytes the caller gives (`testing.reporter_of(&buffer)`), to be
  compared (`testing.report_text`), or passed on only if a test failed (`testing.write_report_if_failed`), for a
  program whose output is compared and shouldn't show a report that says all is well.

## Fuzzing

A property test draws its cases at random, so it seldom comes on an input that only a few bytes in a row reach, like a
magic number, a length that matches, or a tag past several checks. A fuzzer searches for those by what they reach:
`hemera --fuzz=<test> <package>` builds a program that runs one of the package's property tests on input after input,
each made by changing one it has kept, and keeps those that reach code no input before them did.

```
fuzz reads_only_inside_the_copy: 4 inputs to start from, coverage 576
fuzz reads_only_inside_the_copy: 45504 inputs, coverage 1240, corpus 82, 45504 a second
test reads_only_inside_the_copy ... FAILED
    messages.hsc:88: the name is in the copy
        it points outside the copy
        note: drew [59, 250, 0, 0, 0, 0, 0, 0]
    found by fuzzing, 17213 inputs in, shrunk from 216 bytes to 6 in 194 runs
    kept as fuzz/reads_only_inside_the_copy/findings/8849598b3e9c4022, which hemera --fuzz=reads_only_inside_the_copy runs first, until the test passes on it
```

The program's code counts, in each basic block, how many times it ran, and the fuzzer zeroes the counts before each
input and reads them after. An input whose counts reach a block, or a block a number of times (1, 2, 3, 4 to 7, up to
128 and more), that no input before it did, is kept. Changes flip bits, set bytes, put in or take out bytes, copy some
of an input elsewhere in it or bring in some of another's, and put in values at the edges of integers and the
constants the program's code compares with or switches on, which the compiler gathers as it adds the counters.

The test is the same function a run of tests calls, its source giving the fuzzer's input rather than random bytes:
whatever the test draws, the input is the bytes it reads. A fuzz target is often a property that should hold for any
bytes at all, like a parser that never reads outside what it's given, so it draws them with `testing.draw_bytes`.

* It keeps its inputs in a folder, `fuzz/<test>` from where it runs unless `--fuzz-folder` says otherwise: `corpus`,
  the inputs it keeps, which a later run starts from, and `findings`, the inputs a test failed on.
* It stops when the test fails, after `--fuzz-seconds` (60 by default, 0 for no limit), or after `--fuzz-runs`
  inputs. Its exit code is 0 if the test passed on every input and 1 if it failed on one.
* A failing input is shrunk as a property test's is, reported as a test that failed is, and kept in `findings`; a
  later run runs those first, and stops at the first that still fails, so a fix is checked against what was found.
* An assertion that fails in the test ends the program, as it ends any program, with the input kept in `findings` as
  it was, as there's no going on to shrink it.
* Its changes come from the clock, so each run searches differently; `--fuzz-seed=N` repeats one.

It needs files, so the fuzzing program is a hosted one (`std/fuzzing`), while the test itself can be anywhere a
property test can.

A fuzzer of its own, for code it doesn't run itself, like an operating system's kernel, builds that code with
`TargetOptions.coverage` (`base/compiler/build.hsc`): the same counters and constants, given by
`intrinsics.coverage_counters` and `coverage_constants`, for the fuzzer to read however that code makes them reachable.

## Model Checking

Lock-free code goes wrong in interleavings a test rarely meets, and on weakly ordered CPUs in what a load can read. A
model-checked build (`--model-checked`, or `TargetOptions.model_checked` in a build package) makes each atomic operation
of 8 bytes or fewer, each fence and each `spin_hint` call a hook in `base/runtime/model.hsc` instead of being done where
it is, so a model checker running on the thread (`CarrierBlock.model`) chooses what happens: which of a test's threads
runs next, and which store a load reads. Without a checker, the hooks do the operation as the hardware would, so the
same program runs either way; without the option, nothing changes.

Only base's atomics, the runtime's own, and a checker's while one of its hooks runs, are done as they are. Plain (non-atomic)
accesses aren't seen, and atomics on more than 8 bytes aren't modelled.

`testing.check_model(t, body, data, options)` is the checker: `body` runs as a test's first thread, and the threads it
starts with `testing.spawn(function, data)` as others, which `testing.join` waits for; each is a fiber, all on the
calling thread, switched only at those hooks. It runs the test again and again, each time from the start: every
schedule within `options.preemptions` preemptions (2 by default), depth first, or `options.random_runs` schedules drawn at
random from `options.seed`. A preemption is switching away from a thread that could go on; a thread at a spin hint or a
join is waiting for another, and isn't chosen again until another changes memory or ends. The threads record failures in
a `T` as any test does; a schedule in which every thread is waiting, or that makes more than `options.most_steps`
choices, fails too. The first schedule that fails is reported, in `t`'s notes, as the choices `options.replay` takes to
run it again:

```
racy_increments #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    return testing.check_model(t, two_increments, shared)   // found in execution 5; its schedule ... 0,0,1,0,...
}
```

What each load reads is chosen too, as weak memory lets it: any store from the newest the thread has read, or that
happens before it, to the newest of all, as the C11 memory model has it, with acquire and release synchronizing through
vector clocks, and read-modify-writes reading the newest store (`std/testing/model_memory.hsc`). So a relaxed flag can be
seen before the data stored ahead of it, as a weakly ordered CPU shows it, and a released and acquired one can't. Two
choices keep it close to what CPUs do rather than all C11 allows: a sequentially consistent load reads the newest store,
and a thread's first load after a spin hint reads the newest, since stores become visible in time, which a thread waiting
for one relies on. Memory written plainly, or reused for something else, starts a location's history again. base's own
atomics, the runtime's machinery, aren't modelled.

The threads are fibers, so a model-checked test is built with stack checks that grow fibers' stacks
(`--stack-check=morestack`); without them, a thread that needs more than its first segment overruns it.
