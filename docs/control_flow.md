# Control Flow

## Conditionals

The `if` and `else` keywords are used for conditional branching. If is directly followed by any expression that evaluates to a boolean. All if's and else's require curly braces.

If/else statements can be chained, as in `if ... else if ... else if ... else ...`.

```
foo :: fn() {
    bool b = is_it_tuesday()

    if b {
        println("b is true")
    }
    else if 5 >= 3 + bar() {
        println("I'm not sure what this is supposed to be for")
    }
    else {
        println("b is false")
    }
}
```

## Defer

The `defer` keyword is used to defer a statement until the end of a block. It will be executed before leaving the block,
whether that is by reaching the end, having a `return`, `break`, `continue`, or anything else.


```
foo :: fn() {
    defer println("This prints last")
    defer println("This prints second")
    println("This prints first")
}
```

When there are multiple `defer` statements, they will execute in reverse order from how they appear, as if being pushed onto a stack.
The reason for this is we usually want to clean up resources in the reverse order of their creation, and this allows
sub-resources to be cleaned up before parent resources which were used to create them.

```
foo :: fn() {
    a := new A()
    defer delete a

    b := new B(a)
    defer delete b

    // b is cleaned up here
    // a is cleaned up here
}
```

This works in any block and whole expressions can be provided. Here is a more complex example involving loops:

```
foo :: fn() {
    with {
        i : int = 0
        matched : bool = false
    }
    loop {
        defer i += 1
        defer matched = false
        defer println()
        defer if !matched { print(i) }

        if i % 3 == 0 {
            print("fizz")
            matched = true
        }
        if i % 5 == 0 {
            println("buzz")
            matched = true
        }

        if i % 8 == 0 {
            // be careful, defers all run here too
            break
        }

        // "if !matched { print(i) }" runs here
        // "println()" runs here
        // "matched = false" runs here
        // "i += 1" runs here
    }
    while(i <= 10)
}
```

## Loops

### Loop control statements

`break` can be used to break out of the current loop.

A positive integer can also be provided to break out of multiple loops like `break 2` 
will break out of 2 layers of loops (or similar structures where `break` applies).

Finally, `break all` will break out of all loops (or similar structures where `break` applies).

`continue` will skip the rest of the current iteration of a loop, and continue again at the beginning.

### Range-based for
```
// 0 to 10, excluding 10
for i in 0..<10 {
    println(i)
}

// 0 to 10, including 10
for i in 0..=10 {
    println(i)
}

// The bounds can be variables, expressions
for i in x..<random_integer() {

}

some_array : int[3] : {1, 3, 19}

for value in some_array {
    println(value)
}

// You can add an optional second parameter for the index number 
for value, index in some_array {
    println(value)
}
```

You can iterate arrays and views by reference:

```
for &value in some_array {
    println(value)
}

// Index is not affected
for &value, index in some_array {
    println(value)
}
```

The `#reverse` directive indicates a loop should be done in reverse: from the last value or element down to the first.
It works on ranges and on arrays, whose index still counts the element's position, and never goes below the range's
first value, so an unsigned range down to 0 doesn't wrap.

```
for i in 0..=10 #reverse {
    println(i)          // 10, 9, ..., 0
}

for value, index in values #reverse {
    println(value)      // the last element first, with index values.count - 1
}
```

### While

```
loop {
    println("This is an infinite loop")
}
```

`while` is used to specify a condition that must be true for a loop to execute. It appears at the end, which has nothing to do with when the condition is checked. It is always checked *before* running the loop, besides when using a directive that will be discussed later.

`with` is used to define things that are in scope for the body of the loop (and condition).

`with` behaves as if wrapping the whole loop in a new block scope. So 
anything declared there is not in scope after the loop, and any `defer`s
appearing in the `with` execute *after* the loop completes (or breaks, returns, etc.).

The following is equivalent to `for (int i = 0; i <= 10; ++i) println(i)` in C++.

```
with {
    i : int = 0
}
loop {
    println(i)
    i += 1
}
while i <= 10
```

`#at_least_once` causes a loop operation to occur at least once, skipping the first condition check. This is equivalent to turning a C while loop into a do-while loop.

```
loop #at_least_once {
    println("This will run")
}
while false

loop {
    println("This will not run")
}
while false
```

## Compute Blocks

A block doesn't evaluate to its last expression: putting statements in braces never changes what they mean. When a
value takes statements to work out, `compute[T] { ... }` runs them, and `give` gives its value, of type `T`, leaving the
block:

```
total :: compute[u64] {
    sum : u64 = 0
    for each in sizes {
        sum += each
    }
    give sum
}

key :: lookup(name) or_else compute[Key] {
    log_line.write(to, "no key for %", name)
    return .Error(.NotFound)
}
```

* `give` leaves the innermost compute block it's in, from inside loops, `if`s and other blocks in it, and what's
  deferred in them runs as it does, as for `break`.
* Every path through the block gives a value or leaves it some other way: by `return`, by `break` or `continue` to a
  loop around the block (which they pass through, since a compute block isn't a loop), or by a call that never
  returns. A block that can finish without either is an error, as a function that can finish without returning is.
* What's given has the block's type, as what's returned has the function's.
* What's deferred can't `give`, since it runs as the block is left.

It's an expression like any other: a variable's value, a function's argument, a match arm's value, or `or_else`'s
fallback, where a block that only leaves, like the one above, is how a missing value returns from the function after
doing something first.

## Match

Match expressions evaluate to a value using pattern matching.

The cases can be any of these types:

* Integer (including ranges)
* Character (including ranges)
* String (a `string`, which knows its length; a `cstring` is made one first, with std's `c_string.to_string`)
* Enums
* Unions
* Boolean

Example:
```
result : string : match foo {
    case 1 => "a"
    case 2, 3 => "b"
    case 4..=10 => "c"
    case _ => "x"
}

result2 : int = match bar {
    case Ok(foo, _) => foo + 1
    case Fail(_) => 0
    case _ => -1
}
```

* Like `switch`, each arm starts with `case`, so arms need no separators. Commas only separate the values of one
  arm, like `case 2, 3`.
* What's matched is a name, a member or a call, and `?` after it unwraps a result first, as it does anywhere else:
  `match find(key)? { ... }` returns an error from the function, and matches on the value.
* An arm's result can be a block, and an arm can also be a statement like `return`:

```
match load_settings() {
    case Ok(settings) => {
        apply(settings)
        log_info("loaded")
    }
    case Error(error) => return error
}
```

* A variant's values can be patterns too, rather than names: an enum member, a literal, a range, or another variant.
  The arm matches only when they do, and it doesn't cover the whole variant on its own, so another arm (or `case _`)
  covers the rest. Arms that together cover every value inside do cover it, like `Some(.None)` and `Some(Some(x))`.

```
match os.read_entire_file(path) {
    case Ok(text) => apply(text)
    case Error(.NotFound) => use_defaults()
    case Error(error) => report(error)
}
```

  A name alone inside the parentheses is always a new name for the value, so a variant without values is written
  with a dot there: `Some(.None)`, not `Some(None)`.
* `match` gives a value to a declaration, a `return`, or a function argument. It can't be the right side of a plain
  assignment (`x = match ...`), so assign inside the arms instead.

## Push Context

The context can't be modified. To use a different one, the `push_context` keyword is used, which does two things:

1. Defines a new context: a copy of the current context, with the listed fields overridden.
2. Saves the current context, uses the new one for the block (and every function called from it),
   then switches back to the saved one when the block is left.

```
push_context my_context (allocator = memory.ArenaAllocator, log_level = .WARN) {
    // context in this block, and any function calls in it, is referring to my_context
    print_something("You can do whatever you want here")
}
// back to the previous context here
```

* At least one field must be listed, and each field at most once. Fields not listed keep their current values.
* Override values can't point into the stack (see [memory.md](memory.md#contexts)),
  so a context can always be copied, for example into a new thread or fiber.
  The exception is `extensions`, whose nodes can be on the pushing frame's stack.
  A trailing comma is allowed, as in other lists.
* The override expressions are evaluated in order, before the switch, so they see the old context.
  For example, in `push_context scratch (allocator = make_arena(context.allocator))`, the arena gets its memory
  from the allocator that was current before the push.
* `my_context` names the new context inside the block. It refers to the same value as `context` there,
  and is read-only like it. The name is useful for referring to an outer context from inside a nested `push_context`.
* The new context lives in the current function's stack frame, and is destroyed when the block is left.
  That happens however the block is left: reaching its end, `return`, `break` or `continue`.
  `defer` statements inside the block run before the old context is restored, so they still see the new one.
* New threads and fibers get a copy of the context that was current when they were created
  (see [multitasking.md](multitasking.md#contexts)).

### Pushing a Whole Context

`push_context name from value` pushes a copy of a whole `runtime.Context` instead of a copy of the current one:

```
push_context boot from runtime.MINIMAL_CONTEXT {
    start_kernel()
}

push_context cpu_context from cpu.context^ {
    handle_interrupt(frame)
}
```

* The value is copied into the current function's stack frame, so the pushed context can't change under the block
  even if the original does. Everything else is as above: the same rules for what it may point to, the name, how long it
  lasts, and `defer`.
* It works anywhere, including where there is a current context, which it replaces for the block.
* It can't be combined with overrides: `from value (allocator = x)` would read as a call to `value`. Nest them instead:

```
push_context cpu_context from cpu.context^ {
    push_context quiet (log_level = .ERROR) {/* ... */}
}
```

`runtime.MINIMAL_CONTEXT` is made only of constants, for code that needs a context before it has anything real:
allocations fail, log messages are dropped, the clock has no time, and asking for random bytes or failing an assertion
traps.

A hosted program's `main` starts with `runtime.HOSTED_CONTEXT` instead, on Windows and Linux:

* The allocator is the system's: the process heap on Windows, and the runtime's own heap on Linux (see
  [multitasking.md](multitasking.md#threads)).
* The logger is `runtime.STANDARD_LOGGER`, which writes each message on a line of its own to standard error, after
  its level, like `[info] loaded 3 files`, and `log_level` is `.INFO`, so trace and debug messages are dropped until a
  `push_context` lowers it. `std/logger` makes loggers that also put the time, the file and line, the function or
  the thread on each line, like `[warn] 14:03:27.412 loader.hsc:88 load_file [thread 2] missing 3 files`.
* The assertion handler is `runtime.printing_assertion_handler`, which writes the failure to standard error, then ends
  the process with `runtime.ASSERTION_EXIT_CODE` (134) (see [directives.md](directives.md)).
* The clock is the system's (`runtime.SYSTEM_CLOCK`): `time.now()` is the wall-clock time, from
  `GetSystemTimePreciseAsFileTime` on Windows and `clock_gettime(CLOCK_REALTIME)` on Linux, and `time.monotonic()` a
  time that only goes forward, from the performance counter or `CLOCK_MONOTONIC`, for measuring with `time.since`.
* Random numbers are the system's (`runtime.SYSTEM_RANDOM`), suitable for keys: `BCryptGenRandom` on Windows and
  `getrandom` on Linux. `std/random` has `fill`, `next_u64`, and `below` and `between`, which give each number in a
  range the same chance.

```
main :: fn() -> int {
    runtime.log_info("starting with % files", count)    // [info] starting with 3 files
    push_context verbose (log_level = .DEBUG) {
        runtime.log_debug("shown here")
    }
    return 0
}
```

Standard output and error are written with `runtime.write_output` and `runtime.write_error`, which go nowhere on a
target without them, like a kernel. `std/io` prints through them: `print`, `println` and `printf` to standard output,
and `eprint`, `eprintln` and `eprintf` to standard error, with `printf` formatting like `text_buffer.append_format`
into a buffer on the stack, so none of them allocate. Each call is one write, so lines from several threads don't mix. Format strings,
with options like `%{08x}`, are in [format_strings.md](format_strings.md).

`std/os` has the rest of what a hosted program needs from its system, on Windows and Linux, with UTF-8 paths and names
throughout:

* `os.arguments()`, the command line, worked out once and kept for the whole process (on Windows, split the way the C
  runtime splits it), and `os.get_environment(name)`.
* Files: `open` (`.READ`, `.WRITE`, `.APPEND`, `.READ_WRITE`), `read`, `write`, `file_size`, `close`, and
  `read_entire_file` and `write_entire_file`.
* Paths: `delete_file`, `rename`, `path_kind`, `exists` and `is_directory`; folders: `make_directory`,
  `remove_directory` and `list_directory`; and `current_directory` and `set_current_directory`.
* Directories held open: `open_directory(path)` and `working_directory()` give an `os.Directory`, which
  `close_directory` closes, and the path functions have forms that take one first and resolve beneath it:
  `open_in`, `read_entire_file_in`, `write_entire_file_in`, `delete_file_in`, `rename_in`, `path_kind_in`,
  `make_directory_in`, `remove_directory_in`, `open_directory_in` and `list_directory_in`, where `""` is the directory
  itself. A path that isn't beneath it, absolute or climbing out with `..`, fails with `.InvalidPath` (`os.is_beneath`
  says which are, by the path's text, not where a link in it leads), and a Directory keeps naming the same directory when it's renamed or moved. On Linux these are
  `openat` and the other `*at` calls; on Windows, opens relative to the directory's handle.

What gives something back gives a `Result[T, os.OsError]`, `#unrestricted` when it's memory from the allocator, and
what doesn't gives an `os.OsError?`:

```
match os.read_entire_file("settings.txt") {
    case Ok(text) => apply(text)
    case Error(.NotFound) => use_defaults()
    case Error(error) => runtime.log_error("can't read settings: %", error)
}
```

### Functions Without a Context

Most functions are called with a context. Some start without one: functions marked `#no_context`, like a
freestanding program's entry (see [compilation.md](compilation.md#freestanding-programs)) and functions a bootloader
or other foreign code calls ([calling_convention.md](calling_convention.md#functions-entered-from-outside)), and
[interrupt functions](calling_convention.md#interrupt-functions) and [entry functions](calling_convention.md#entry-functions).
Until they push one with `push_context ... from`:

* `context` can't be used, and the override form of `push_context` is an error, since there is nothing to copy.
* Only intrinsics (bodiless declarations in `base`, which compile to instructions) and other `#no_context` functions
  can be called, like `intrinsics.set_carrier`. Every other call needs a context to pass.

Calls inside the `push_context ... from` block get the pushed context as usual.

### The Context is Read-Only

The compiler rejects anything that would change the current context, rather than replace it for a scope:

```
context.allocator = memory.ArenaAllocator   // Error: the context can't be assigned to
context.allocator.data = some_data          // Error: neither can any of its fields, at any depth
context = other_context                     // Error
x : ptr[mut Allocator] = &context.allocator // Error: no mutable pointers into the context
modify_allocator(&context.allocator)        // Error, if the parameter is ptr[mut Allocator]
```

Fields that are pointers, like `logger : ptr[Logger]`, follow the usual rules for what they point to:
`ptr[Logger]` isn't `mut`, so the logger can't be modified through it either.
State that does need to change, like an allocator's or a random number generator's, is changed by calling
the functions they hold, which receive their data pointer as `mut`.

These checks are for well-behaved code. Laundering a pointer to the context through `rawptr` or a cast can get
around them, and the result is undefined behavior.
The point of pushing contexts is that a function can rely on the context it was given, and can't change
the allocator or logger out from under the function that called it.

## Switch

Switch statements work similar to C's, except they never fall through except where a directive is explicitly provided to do so.
Like C, a case runs every statement up to the next case, so a case with several statements doesn't need braces.

The cases can be any of these types:
* Integer (including ranges)
* Character (including ranges)
* String (a `string`, which knows its length; a `cstring` is made one first, with std's `c_string.to_string`)
* Enums

Example:
```
switch foo {
    case 1: print("a")
    #fall_through
    case 2, 3: print("b")
    case 4..=10:
        print("c")
        print("d")
    case _: print("x")
}
```
