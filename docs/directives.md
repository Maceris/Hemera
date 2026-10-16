# Directives

## Compilation

`#assert` is used to check conditions at compile time. If the condition evaluates to false, 
we stop the build and throw an error.

```
#assert size_of(Foo) >= size_of(Bar)
```

We also have a runtime assert, where the handler can be specified, and the compiler
will behave similarly if you do a `#run assert(/*...*/, "Custom error here")`, but that version
allows for a specific error message instead of the `#assert /* expression */` reporting style.

The runtime `assert` calls `context.assertion_handler` when the assertion is false, which can be changed with
`push_context`. Handlers end the program: `AssertionHandler` is `#never_returns`, so execution never continues
past a failed assertion. If an assertion fails inside a handler, `assert` stops the program with `intrinsics.trap()`
(an illegal instruction) instead of calling the handler again. At compile time, that fails the build.

The checks the language does at run time fail the same way, through `context.assertion_handler` with a message
saying what went wrong:

* integer division or remainder by zero
* unwrapping an empty optional
* running out of stack, if the target's `stack_check_failure` is `.AssertionHandler`

Array indexes aren't checked at run time, since they must be proven in bounds at compile time
(see [types.md](types.md#bounds-checking)). Integer overflow isn't a check either: it wraps (two's complement).

`#if` used to conditionally include sections of code, evaluated (as in chosen, not executed) at compile time.
The boolean expression is executed at compile time, but the block is either included in the code or not. 
Also used with `#else_if` and `#else`.

```
foo :: fn() {
    #if OS == .WINDOWS {
        init_socket() 
    }
}
```

`#is_compile_time` evaluates to `true` during compile time and `false` during run time.

`#run` specifies code should be run during compile time. It is followed by an expression to execute.

When the `#run` directive appears at the top level of a file, it is executed when that file gets processed (each unique file should be processed once).
When included in the body of a function, it is executed when that function is processed.
When included in places like the right-hand side of an expression, function arguments, etc. it will be evaluated as an expression and the result used as if it were
a constant value.

```
#run println("I am processing a file")

example :: fn() {
    #run println("I am processing example()")

    // equivalent to writing some_fn(21), assuming fibonacci() behaves as expected
    some_fn(#run fibonacci(8))
}
```

## Constants

### `#externally_initialized`

`#externally_initialized` on a top-level constant means its value is only the initial contents of the program's image.
Something outside the program, like a bootloader, a loader or a tool run after linking, may replace it before the program starts,
and the program sees the replaced value. It's placed after the identifier in a declaration.

```
MEMORY_MAP_REQUEST #externally_initialized #section(".limine_requests") :: MemoryMapRequest.{
    id = u64.[COMMON_MAGIC_0, COMMON_MAGIC_1, 0x67cf3d9d378a806f, 0xe304acdfc50c3c62],
}

memory_map :: fn() -> ptr[MemoryMapResponse]? {
    // Read from the image at run time, never replaced by the initializer's null
    return MEMORY_MAP_REQUEST.response
}
```

* It's always in the output, even if nothing in the program uses it.
* Reads at run time load it from the image. The compiler never replaces a read with the initializer, but may still assume
  the value doesn't change while the program runs.
* It's still a constant: it can't be assigned to, and `&` gives a `ptr[T]`, not a `ptr[mut T]`.
* Reading it at compile time is an error, since the value isn't known until the program is loaded. Its address and
  `size_of`/`align_of` are fine.

This isn't a mutable global. The value is fixed before the program's first instruction, and is the same for every reader
for the whole run, the same way relocations already fill in addresses when a position-independent program is loaded.

### `#section`

`#section(name)` places an `#externally_initialized` constant in the output section `name`, for a linker script to place.
It's only allowed together with `#externally_initialized`. Every other constant goes in the read-only data section on
platforms that have one.

The compiler doesn't promise an order between constants in the same section.
When an order matters, put them in separate sections and order those in the linker script.

```
REQUESTS_START #externally_initialized #section(".limine_requests_start") :: REQUESTS_START_MARKER
REQUESTS_END #externally_initialized #section(".limine_requests_end") :: REQUESTS_END_MARKER
```

## Control

`#at_least_once` causes a loop operation to occur at least once, skipping the first condition check. This is equivalent to turning a C while loop into a do-while loop.

`#fall_through` is used in switch statements to fall through (continue on) to the next case.

`#reverse` indicates a loop over a range should be done in reverse, for example:

```
for i in 0..=10 #reverse {
    println(value)
}
```

## Enums

`#backed_by(x)` is used to specify `x` as the backing type, which must be one of the unsigned integer types (u8, u16, u32, u64, u128). By default enums are backed by uint.

## Functions

`#export` on a function marks it as part of a library or program's public interface.
This is placed after the identifier in a declaration.

```
example #export :: fn() {/* ... */}
```

You could in theory put this on a function inside other functions, as they are effectively hoisted out anyway.
However that is a fairly confusing thing to do, since it's visible outside the program by name but must be passed 
around by function pointer inside the program, so it's discouraged.

`#calling_convention(.interrupt)` makes a function an interrupt handler, entered by the CPU instead of called
(x86-64 only). It is also placed after the identifier, and is part of the function's type.
See [calling_convention.md](calling_convention.md#interrupt-functions).

```
timer_interrupt #calling_convention(.interrupt) :: fn(frame: ptr[x86_64.InterruptFrame]) {/* ... */}
```

`#calling_convention(.entry)` and `#calling_convention(.syscall_entry)` make a function a kernel entry point, which gets
the interrupted code's registers as an `x86_64.RegisterFrame` (x86-64 only).
See [calling_convention.md](calling_convention.md#entry-functions).

### `#never_returns`

`#never_returns` marks a function that never returns to its caller, like `os.exit` or `intrinsics.trap`.
It's part of the function's type. On a declaration it's placed after the identifier, and in a function type after the signature.

```
exit #never_returns :: fn(code: int) {/* ... */}
trap #never_returns : fn() : ---
AssertionHandler :: alias fn(location: SourceCodeLocation, message: string) #never_returns
```

* The function has no results.
* Its body can't `return` or reach its end: every path ends in a call to another `#never_returns` function, or in a
  `loop` with no `break` out of it. Declarations without a body (`---`), like intrinsics and foreign functions, are trusted.
* For the caller, code after the call is unreachable, as after a `return`, so a path ending in one needs no return value.
* The caller's `defer`s don't run, since the call never returns and its scopes are never left.
* A `#never_returns` function can be used where the same function type without it is expected, but not the other way around.
* The compiler gives the function LLVM's `noreturn` attribute, and puts `unreachable` after every call to it,
  including calls through function pointers.

A call to it has no value, so `lookup(key) or_else exit(1)` isn't allowed. Use an `if` instead.

## Function Parameters

### `#caller_location`

`#caller_location` is (only) used to set a function parameter's default value to the location of the code calling the function.

### `#escaping`

`#escaping` marks a parameter that the function may keep after it returns, for example by storing it on the heap.
Callers can't pass anything that points into their stack to it.
Parameters that carry pointers and aren't marked can't be kept. See [memory.md](memory.md#escaping-parameters).

It is placed after the parameter's name, and is part of the function's type.

```
register :: fn(registry: ptr[mut Registry], name #escaping : string) {/* ... */}
Callback :: alias fn(data #escaping : any)
```

## Structs

`#align(n)` is used to align to `n` bytes, for example `struct #align(8) {...}` aligns the struct to at least 8 bytes.
It only raises the alignment; with `#packed`, it sets it exactly (see [types.md](types.md#memory-layout)).
`#packed` is used to remove padding between fields in a struct
`#union` turns the struct into a c-style union, where every field is located at the same offset and share memory
`#scoped` is used for structs meant to hold pointers into the stack and be passed around by pointer, like parsers and iterators over a stack buffer.
Values of these structs can never be stored on the heap. See [memory.md](memory.md#scoped-structs).

## Values

`#file_path` is the path to the file in which this directive appears.

`#file_data("path")` is the contents of a file, read when the program is compiled, as a `u8[N]` with `N` the file's
size. The path is relative to the folder of the file the directive is in. Data a program needs but shouldn't keep in
source, like a font, an image or a table, goes in the program this way, without a step that turns it into a constant
first.

```
FONT :: #file_data("fonts/console.psf")

load_font :: fn() -> Font {
    return parse_font(FONT) // FONT is a u8[N], so it passes as a u8[]
}
```

It's a compile error if the file can't be read, or if the path isn't a string literal. Like any constant, the bytes are
part of the program's read-only data.

