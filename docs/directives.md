# Directives

## Compilation

`#assert` is used to check conditions at compile time. If the condition evaluates to false, 
we stop the build and throw an error.

```
#assert size_of(Foo) >= size_of(Bar)
```

The condition is worked out when compiling: literals and named constants, with arithmetic, comparisons, `&&` and `||`,
the bitwise operators and shifts, `cast` from one integer type to another (which wraps, as at run time) or of an enum
member to an integer type, builtins like
`size_of` and `offset_of`, and calls, which are run at compile time.

```
#assert cast[u32](READ | WRITE) == 3
#assert cast[u8](300) == 44
```

We also have a runtime assert, where the handler can be specified, and the compiler
will behave similarly if you do a `#run assert(/*...*/, "Custom error here")`, but that version
allows for a specific error message instead of the `#assert /* expression */` reporting style.

The runtime `assert` calls `context.assertion_handler` when the assertion is false, which can be changed with
`push_context`. Handlers end the program: `AssertionHandler` is `#never_returns`, so execution never continues
past a failed assertion. If an assertion fails inside a handler, `assert` stops the program with `intrinsics.trap()`
(an illegal instruction) instead of calling the handler again. At compile time, that fails the build.

A hosted program starts with `runtime.printing_assertion_handler`, which writes the message, where the assertion was
and the stack to standard error, then ends the process with `runtime.ASSERTION_EXIT_CODE` (134):

```
assertion failed: count must be positive
    at src/main.hsc:10:18, in check
    0x146a  app.main+0x6a
    0x15bd
    (hemera --symbolize=app.exe 0x146a 0x15bd for files and lines)
```

The stack is its return addresses, innermost first, starting in `assert` (or where it was inlined), as offsets into
the program's image, which are the same every run. With debug info, each is followed by the Hemera function it's in,
and `hemera --symbolize` gives their files and lines (see [compilation.md](compilation.md#debug-info)). Freestanding
programs start with `MINIMAL_CONTEXT`'s `trap_assertion_handler`, which traps.

The checks the language does at run time fail the same way, through `context.assertion_handler` with a message
saying what went wrong:

* integer division or remainder by zero
* unwrapping an empty optional

Running out of stack, on a target that doesn't grow its stacks, traps instead (see
[calling_convention.md](calling_convention.md#prologue-stack-check)).

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

An `if` whose condition `#is_compile_time` decides, alone or through `!`, `&&` and `||` (like
`#is_compile_time && !allowed()`), only has the branch that can run generated. So a function can call what only works
at compile time, like `compiler.report_error`, in a branch that only compile-time code takes, and still be used in the
program. Both branches are checked.

`#code(expression)` and `#code { statements }` quote code, giving a `compiler.Code`, and `#insert` in a quote puts a
value there: code, a type or a literal. Outside a quote, `#insert` puts code into the program: in a body, at the top
level of a file, or among a struct's, union's or enum's members or a `match`'s or `switch`'s cases (see
[compilation.md](compilation.md#code-values)). A [`#macro`](#macro) call is an `#insert` of what the macro gives.

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

### `#constraint`

`#constraint` after a function's name makes it a constraint, which generics can name to say what they need from their
parameters (see [types.md](types.md#constraints)):

```
Equatable #constraint :: fn(T: type) {
    require_equality(T)
}
```

A constraint only runs at compile time, while generics that use it are checked, so it's made of `base/compiler`'s
requirements (`compiler.require_*`, `compiler.require`, `compiler.note`, and `compiler.require_any` for
alternatives), calls to other constraints, and what compile-time code can always do. It's never generated into the program.

### `#macro`

`#macro` after a function's name makes it a macro: a function giving a `compiler.Code`, called as `name!(...)`, whose
code is put where the call is, hygienically (see [compilation.md](compilation.md#macros)):

```
swap #macro :: fn(a: compiler.Code, b: compiler.Code) -> compiler.Code {
    return #code {
        temporary := #insert a
        #insert a = #insert b
        #insert b = temporary
    }
}
```

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
the interrupted code's registers as an `x86_64.RegisterFrame`, or an `aarch64.RegisterFrame` on AArch64, which has
`.entry` only.
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

A call to it has no value, but fits wherever a value is expected, since there's never a value to use: `lookup(key) or_else exit(1)` is fine.

### `#no_context`

`#no_context` marks a function that's called without a context, and has no prologue stack check, since it may start
before there's a carrier block. It's part of the function's type, placed like `#never_returns`. Its body sets up a
carrier block and pushes a context before calling anything that needs them, and can call intrinsics and other
`#no_context` functions until then (see [control_flow.md](control_flow.md#functions-without-a-context)). It's for
functions entered from outside Hemera, usually with `#calling_convention(.c)` (see
[calling_convention.md](calling_convention.md#functions-entered-from-outside)).

```
kernel_entry #calling_convention(.c) #no_context :: fn() #never_returns {/* ... */}
```

### `#foreign`, `#library` and `#link_name`

A foreign function, written in C or anything else that uses the platform's convention, is declared without a body and
marked `#foreign`, naming the library it comes from. The library is a constant made by `#library("name")`, declared
once and used by every function from it, in the same package or an imported one:

```
KERNEL32 :: #library("kernel32")

GetCurrentThreadId #foreign(KERNEL32) : fn() -> u32 : ---
ExitProcess #foreign(KERNEL32) : fn(code: u32) #never_returns : ---
multi_byte_to_wide_char #foreign(KERNEL32) #link_name("MultiByteToWideChar") : fn(/* ... */) -> i32 : ---
```

* The function is linked by its own name, or by `#link_name("symbol")` when that's different.
* Its type uses the platform's C convention, without a context, like `#calling_convention(.c) #no_context`, so it can't
  have those directives itself, nor `#export`.
* The program is linked with every library its foreign functions come from: `name.lib` for PE/COFF outputs, and
  `-lname` for ELF. On Linux that also links the C library, dynamically (see
  [compilation.md](compilation.md#linking-c-on-linux)).
* Calls go through a shim that runs the function on the thread's own stack, see
  [calling_convention.md](calling_convention.md#calls-to-foreign-code). For now each parameter and the result have
  to fit a register (integers, pointers, floating-point values, booleans and enums), there are no variadic foreign
  functions, and only x86-64 and AArch64 are supported.

### `#constant_time`

A function whose parameters or results are secrets is marked `#constant_time`, like
`keys_equal #constant_time :: fn(a: ptr[Key], b: ptr[Key]) -> bool`, so it shows in its signature. One that works with
no secret is warned about. A generic's instances needn't be marked. See [memory.md](memory.md#secrets).

### `#target_features`

A function whose code uses CPU features beyond the target's, like AES instructions on an x86-64 CPU that may not have
them, names them, and is only called once the CPU is known to have them:

```
encrypt_block #target_features("aes") :: fn(keys: ptr[v128[11]], block: v128) -> v128 {
    state := block ~ keys[0]
    for round in 1..<10 {
        state = x86_64.aes_encrypt_round(state, keys[round])
    }
    return x86_64.aes_encrypt_last(state, keys[10])
}

if (x86_64.cpuid(1).ecx & (1 << 25)) != 0 {
    cipher = encrypt_block(&keys, block)
}
```

* The names are LLVM's for the architecture, separated by commas, like `"aes,pclmul"`. Each is added to the target's
  own features, which the function keeps, along with the carrier register being kept for the program
  (see [calling_convention.md](calling_convention.md#carrier-register)).
* Only a function with a body has them, since it's its code that uses them.
* Calling it on a CPU without them is an illegal instruction, so check first, like with `cpuid`.

## Function Parameters

### `#caller_location`

`#caller_location` is (only) used to set a function parameter's default value to the location of the code calling the function.

### `#crosses_threads`

`#crosses_threads` marks a parameter whose value goes to another thread, like a new thread's data or what a channel
sends, so it can't be given anything `#thread_bound`. It's placed after the parameter's name, with `#escaping`, which
such a parameter usually is too. See [multitasking.md](multitasking.md#values-that-stay-on-their-thread).

```
channel_send :: fn[T, capacity: usize](channel: ptr[mut Channel[T, capacity]], value #escaping #crosses_threads : T) -> T?
```

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
`#unrestricted` is used for structs that never point into the stack, like allocators: their values can be stored anywhere,
and passing one to a function doesn't tie what it returns to the stack. See [memory.md](memory.md#unrestricted-structs).
`#owned(release)` is used for structs whose values are resources, like files: each has one owner, which releases it
with `release` or moves it on, and the compiler checks every path does. `#owned(release, condition)` decides for each
instance of a generic. See [memory.md](memory.md#owned-types).
`#thread_bound` is used for structs whose values can't leave the thread they were made on, like a reference count kept
without atomics; `#thread_bound(condition)` decides for each instance. They can't be given to a `#crosses_threads`
parameter. See [multitasking.md](multitasking.md#values-that-stay-on-their-thread).
`#secret` is used for structs whose values are secrets, like keys, which can't decide timing; it also goes after a
distinct alias's type, like `Word :: distinct alias u32 #secret`. See [memory.md](memory.md#secrets).

### `#release`

`#release` after a parameter's or a local's name releases it, with its type's release function, where its scope ends,
as a `defer` written there would. It can't be moved. See [memory.md](memory.md#owners).

```
consume :: fn(file #release : File) -> int {/* ... */}
buffer #release :: make_buffer(4096)
```

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

