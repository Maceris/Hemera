# Compilation

An important note is that we have arbitrary compile-time execution.
This means that it ***is not safe*** to compile untrusted code,
just like it would not be safe to build with untrusted makefiles.

If dealing with potentially untrusted code, any IDE that will
automatically compile the code or do something like request that a language server
calculate values should be avoided, or opened in a safe mode which avoids such operations.

## Compilation Stages

1. Lexing
2. Parsing
3. Type Checking
4. MLIR Generation
5. Compile-Time Execution
6. Optimization
7. LLVM IR Generation
8. Optimization
9. Executable Generation (backend)

```
File Import --> Parse --> Type Check <--\
    /|\/|\                     |        |
     |  \--------+-------------+        |
     |           |            \|/       |
     |           |     Type Deduction --/
     |          \|/
 Execution <--- MLIR Generation 
                 |
                \|/
            Optimization
                 |
                \|/
           LLVM IR Generation
                 |
                \|/
            Optimization
                 |
                \|/
        Executable Generation
```

## Deterministic Output

The same inputs (source, `base` and `std`, options and settings, and the same compiler) give the
same output, byte for byte, wherever it's written and however the work was spread across threads.
That lets you check that two builds of a commit match, see only real changes when comparing two
compilers' output, and cache or bisect builds.

Work happens on many threads, in whatever order its dependencies allow, so nothing the compiler
writes may depend on that order or on memory addresses. Where the compiler walks a collection to
produce output, or a list compile-time code sees (a package's declarations, a program's packages),
it orders it by something in the source: a name, a path, a position. The object file is named
after the root package's folder, not the output file. Compile-time code can still make a build
differ, by reading the clock or a file that changed; that's the code's choice, not the compiler's.

## Compile-Time Execution

Compile-time code, like `#run` and a constant whose value calls a function, is compiled and run through a JIT: the
compiler generates the code an evaluation reaches as MLIR, lowers it the same way as the program, and runs it on the
machine doing the compiling. Its result becomes a constant in the program, so it can only hold what a constant can:
numbers, booleans, enums, characters, strings, and structs and arrays of them. Pointers other than null can't leave
compile time, since what they point to doesn't exist in the program.

Compile-time code runs once every function it reaches is checked, and only once: checking that needs its value,
like an array's count or an `#if` condition, waits for it, and the program uses the same result. So code that
computes such a value can't call a function whose own checking needs it; that's reported as a cycle. Checking can
use integers, booleans and enum members from it; anything else it gives is only for the program's constants.

Compile-time code runs with `runtime.COMPILE_TIME_CONTEXT`. What it logs is printed by the compiler at the line that
logged it, with `%` filled in like a run-time logger's; warnings are the compiler's warnings, and errors fail the build.
Its allocator gives memory that lasts until the code finishes. A failed assertion, a trap, or a crash, like reading
memory it can't, fails the build at that line, or at the constant or `#run` being worked out, and the compiler goes on
to report anything else wrong.

Each function compile-time code reaches is compiled once for the whole program: a later `#run` or constant that calls
it again, like the compile-time context's logger, which every run has, calls what an earlier one compiled. A function's
values, like a constant it reads, are worked out the same each time, so that's the same code either way. A value
compile-time code works out for reflection, like a constant `compiler.find_constant` finds, is worked out once too.

Compile-time code is the program's own code, with the `#if` choices made for the target, compiled for the machine
doing the compiling. Code that only computes runs the same either way; code that uses the operating system only works
at compile time when the target's operating system is the one compiling it, as it is for a build package.

Compile-time code can look at the program through `base/compiler`: `compiler.package_info` for a package the file
imports, with its files, imports, functions, constants (with their values) and types, `find_function` and
`find_constant` in one, and `report_error` and `report_warning` at any location. `compiler.target_setting` reads a
setting given on the command line as `--setting=name=value`.

## Code Values

Compile-time code can make code, as syntax trees, never as text: a `compiler.Code` is a tree the compiler keeps, which
compile-time code holds by handle. A **quote** makes one from Hemera written in place, parsed but not checked, so the
names in it needn't exist where it's written:

```
sum :: #code(a + b)          // one expression
body :: #code {              // statements
    total += item
}
```

In a quote, `#insert` puts a value there when the quote is evaluated, worked out where the quote is:

| What's inserted | Becomes |
|---|---|
| A `compiler.Code` | Its tree, copied; statements inserted among statements go in as statements |
| A type | That type, as itself, so nothing is looked up by its name |
| A number, boolean, character, string or enum member | A literal of it |

```
sum :: #code(a + b)
n := 6 * 7
product :: #code(#insert sum * #insert n)     // (a + b) * 42
sized :: #code(size_of(#insert u64))          // size_of(u64)
```

`#insert`'s operand binds like a prefix operator's, so `#insert sum * #insert n` multiplies two insertions; anything
bigger than a name, a call or a prefix operation goes in parentheses. An inserted tree gets the parentheses its operators
need where it lands. An `#insert` in a quote inside a quote belongs to the inner one.

`compiler.code_text(code)` gives the code as Hemera, formatted for reading, which parses back into the same tree.

Only compile-time code has code: like a pointer, a `compiler.Code` can't be a constant of the program, and a function
that quotes can only run at compile time.

### Inserting Code

Outside a quote, `#insert` puts code into the program, in a function's body: its operand is compile-time code giving a
`compiler.Code`, run once, like a `#run`, so it can call functions and use constants, but not the body's own variables.
The code is checked and generated as if it were written there:

```
definitions :: fn() -> compiler.Code {
    return #code {
        total := 0
        total += 40
    }
}

seven :: fn() -> compiler.Code {
    return #code(3 + 4)
}

main :: fn() -> int {
    #insert definitions()            // total is declared from here on
    total += #insert seven() - 5     // (3 + 4) - 5
    return total                     // 42
}
```

* **Statements** go in among the statements around them, so what they declare is seen after them. **An expression**
  goes where the `#insert` is, as one value, whatever its operators. Statements where an expression goes are an error.
* **Names** in the code are looked up where it's put, so it can use and declare the names around it. That's what
  makes `#insert` the general tool; for code that keeps to itself, use a [macro](#macros).
* **Each insertion is a copy**, so the same code inserted twice declares two sets of variables.
* **Errors** in inserted code are reported where it was written, the quote, followed by where it was inserted.
* **To see what was inserted**, `--show-inserted=file:line` prints the code each `#insert` on that line put there, as
  Hemera. The file is matched by the end of its path.
* `#insert` in a generic's body or a generic type isn't supported yet.

### Declarations, Members and Cases

`#insert` also goes at the top level of a file, where its code holds declarations, and among what's inside a struct,
union, enum, `match` or `switch`. What goes inside something else is quoted with a word after `#code` saying what it
holds, parsed as it is there:

| Quote | Holds | Inserted among |
|---|---|---|
| `#code { ... }` | Statements, or declarations | A body's statements, or the top level of a file |
| `#code fields { ... }` | Fields | A struct's fields |
| `#code variants { ... }` | Variants | A union's variants |
| `#code members { ... }` | Members | An enum's members |
| `#code patterns { ... }` | Patterns, each with what it runs | A `match`'s |
| `#code cases { ... }` | Cases | A `switch`'s |

```
position :: fn() -> compiler.Code {
    return #code fields {
        x : f32,
        y : f32,
    }
}

Point :: struct {
    #insert position(),
    z : f32,
}

#insert declarations()      // what it declares is the package's, like anything written here
```

The words are only special right after `#code`, so `#code(Point.{})` and a struct's own `fields` mean what they always
do. A list of such quotes (`compiler.list`) puts each one's items there, so a generator can make them one at a time.

In a quote, they're spliced the same way: an `#insert` among a quoted `match`'s patterns, or a quoted struct's fields,
puts each of the code's items there, so a generator can build a `match` from patterns it made:

```
#code {
    classify :: fn(color: Color) -> int {
        return match color {
            #insert patterns()
            case .Blue => 3
        }
    }
}
```

### Making and Inspecting Code

In a quote, `#insert` also puts a declaration's name in place (`#insert name :: fn() {...}`), a member's name
(`#insert name : int` among fields, `#insert name = 3` or `#insert name,` among an enum's members, `value.#insert name`
and `.#insert name` to reach one), parameters in a parameter list (`fn(#insert parameters)`), arguments in a call
(`f(#insert arguments)`) and a type where one goes (`-> #insert T`, `ptr[mut #insert T]`). `base/compiler` makes the
code for those from values, for what a quote can't say, like a name from a table:

| Function | Makes |
|---|---|
| `compiler.name(parts...)` | A name, its parts joined, like `compiler.name("load_", "u64")`, which is only ever an identifier: anything else is an error there |
| `compiler.literal(value)` | A literal of a number, boolean, character, string or enum member |
| `compiler.type_code(T)` | A type, as itself |
| `compiler.list(items)` | A list, whose items go in its place, each one of what holds it: arguments, parameters, statements. Statements given are each an item |
| `compiler.parameters(F)`, `compiler.arguments(F)` | A function type's parameters as a parameter list, and their names as arguments |
| `compiler.described_type(info)` | The type a `ptr[TypeInfo]` describes, for what takes a `type` |

Each comes from where it's called, which is where an error in it is reported. Text never becomes code any other way:
there's no parsing a string, so what's generated is always Hemera the compiler has parsed or built.

```
Calls :: struct {
    add : fn(a: int, b: int) -> int,
    negate : fn(value: int) -> int,
}

// A function per call, passing its number and arguments on to dispatch
stubs :: fn() -> compiler.Code {
    info :: cast[ptr[compiler.TypeInfoStruct]](type_info_of(Calls))
    made : compiler.Code[..]
    for member, i in info.members {
        function :: compiler.described_type(member.member_type)
        array_add(&made, #code {
            #insert compiler.name(member.name) :: fn(#insert compiler.parameters(function)) -> int {
                return dispatch(#insert i, #insert compiler.arguments(function))
            }
        })
    }
    return compiler.list(made)
}

#insert stubs()     // add and negate
```

Code that takes code can look at it: `compiler.code_kind(code)` says what it is (an expression, statements, a name, a
type, a literal, a list, or fields, variants, members, patterns or cases), `identifier_of` gives a name's text,
`items_of` the items of statements, a list and the rest, and `location_of` where it was written or made.

### The Top Level

At the top level, an `#insert` may declare any name, so a name the package doesn't declare otherwise waits for it, as it
waits for an `#if` that may declare it, and so does a name a file looks for in a package it imports whose `#insert` may
declare it. A name a file imports from elsewhere, or a builtin, is used without waiting; if inserted code turns out to
declare it too, that's an error, since the package's own would have been meant, or the use is ambiguous. Code an
`#insert` runs can't need a name only that `#insert` declares, which is reported as a cycle.

### Macros

A **macro** is a function marked `#macro` that gives a `compiler.Code`, called with `!` after its name. The call is an
`#insert` of what the function gives, run at compile time, with each argument for a `compiler.Code` parameter quoted as
it's written, unchecked. Other arguments are values, worked out at compile time like any `#insert`'s:

```
swap #macro :: fn(a: compiler.Code, b: compiler.Code) -> compiler.Code {
    return #code {
        temporary := #insert a
        #insert a = #insert b
        #insert b = temporary
    }
}

add #macro :: fn(target: compiler.Code, amount: int) -> compiler.Code {
    return #code {
        #insert target += #insert amount
    }
}

main :: fn() -> int {
    temporary := 1
    total := 41
    swap!(temporary, total)     // temporary is 41, total is 1: the macro's temporary is its own
    add!(total, 41)
    return total                // 42
}
```

A macro is called as `name!(...)` or `package.name!(...)`, in a body, as statements or as an expression, and nothing
follows the call. It's still a function, which other compile-time code can call without `!` to get its code.

A macro's code is **hygienic**, unlike a plain `#insert`'s:

* **What it declares is its own.** A local its code declares is seen only by code the same expansion wrote, so it
  can't hide the caller's variables or be used by them, even one with the same name. Each expansion is apart from the
  others, and from those of macros its code calls.
* **Its names are the macro's.** A name its code uses that isn't one of those locals is looked up from the file the
  macro was written in, with that file's imports, so the caller needn't import what the macro uses, and can't change
  what it means by declaring the same name.
* **The code it's given stays the caller's**, wherever the macro puts it: its names are looked up as they would be
  where the call is written.

So names reach the caller only through arguments: code a macro is given can name the caller's variables, and code a
macro writes can't. A name made with `compiler.name` is code the macro wrote.

Code a macro gives may call macros, including itself, but expansion stops with an error 64 insertions deep. Like any
`#insert`, a macro call isn't supported in a generic's body yet.

## Build Packages

A program whose compile-time code registers targets with `compiler.add_target` is a build package: it produces
nothing itself, and once it's checked, the compiler builds each target it registered, in the same process, several
at once (see below). A target is a root package and its `BuildOptions`, usually started from
`compiler.command_line_options()` so settings and options given on the command line carry over. Its `root`,
`output_path` and `linker_script` are relative to the build package's folder.

```
package build

import compiler from "base"

build :: fn() {
    kernel := compiler.command_line_options()
    kernel.name = "kernel"
    kernel.root = "../kernel"
    kernel.target_options.os = .None
    target :: compiler.add_target(kernel)
    compiler.add_check(check_program)
    step :: compiler.add_step(make_image, compiler.all_targets())
}

#run build()
```

A build package can find what to build instead of naming it. `compiler.subfolders(folder)` lists the folders in
one, and `compiler.load_package(folder)` gives a package's info whether the build imports it or not: a package
nothing imports is checked on its own, as the root of a program of its own, so its constants have that program's
types and are compared by name. What to build is then up to the build package's code, like every package in
`programs` whose `KIND` is `Program`:

```
for folder in compiler.subfolders("../programs") {
    package := compiler.load_package(folder) or_continue
    kind :: compiler.find_constant(&package, "KIND") or_continue
    if (reflection.enum_member_name(kind.value) or_else "") == "Program" {
        // add_target, with root = package.path
    }
}
```

Each target is checked on its own, with its own `#if` choices and settings, then every check registered with
`compiler.add_check` runs on it, with its `BuildOptions` and its whole program as a `ProgramInfo`. A check that
returns false, or reports an error, stops that target. The rest are generated and linked, then each step registered
with `compiler.add_step` runs, after the targets it depends on, with their outputs. Checks and steps are the build
package's own functions, so they run with its types: a value from a target, like a constant in its `ProgramInfo`,
has the target's types, which are compared by name (see `ConstantInfo`).

Targets are built several at once, each a program of its own: its files are read, parsed and checked for it, even
ones another target already used, since its `#if` choices, settings and package paths can make them mean something
else, and the work within a target is spread across threads like any program's. `--jobs=N` says how many are built
at once: 1 for one at a time, in the order they were registered, and by default a quarter of the machine's logical
processors. The checks take turns, since they run the build package's own code. Either way, each target's outputs
are the same (see Deterministic Output), and what it reports, its errors and warnings and `--time-phases`'s lines, is
printed in one piece and in the order the targets were registered, once it and every target before it are done.
A target's errors stop only it: the others are still built, and the build fails. Steps run once every target is done.
Sharing parsed files between targets is planned.

## Compile-Time Permissions

Compile-time code can't run other programs or write outside the output folder unless the command line grants it
with `--allow-run`. Code reads what it was granted with `compiler.build_permissions()`, and functions like
`os.run_process` check it themselves.

The grant only covers compile-time execution started by the build package: its own `#run` code, and the steps
and checks it registers. That includes any library code they call. `#run` code anywhere else, like in an imported
package, always runs without it, so importing a package never hands it the build's permissions.

## Freestanding Programs

Normally the output includes startup code that sets up the first carrier block (see
[calling_convention.md](calling_convention.md#carrier-register)) and context before calling the entry function.
Programs with nothing underneath them, like kernels, turn it off with `TargetOptions.startup_code = false`.
Their entry function is then entered from outside Hemera, so it's declared `#calling_convention(.c) #no_context`
([calling_convention.md](calling_convention.md#functions-entered-from-outside)), and keeps its own name for the linker
without needing `#export`. It has to set things up before calling any Hemera code that needs a context:

```
kernel_entry #calling_convention(.c) #no_context :: fn() #never_returns {/* ... */}
```


1. Point a carrier block's `stack_limit` at the end of the stack, and load it with `intrinsics.set_carrier`.
2. Push a context made of constants, like `push_context boot from runtime.MINIMAL_CONTEXT`, until there's a heap,
   a logger and a clock (see [control_flow.md](control_flow.md#pushing-a-whole-context)).

Programs with small fixed-size stacks, like kernels, can also set `TargetOptions.max_frame_size`: any function whose
stack frame is larger is a compile error, so a large stack buffer is caught when building rather than when the stack
runs out.

Freestanding programs usually also set `TargetOptions.stack_check_failure` to `.Trap`, since they have no allocator
for `morestack`.

## Linking

The compiler links the output itself, with the linker in `TargetOptions.linker`, or LLVM's `lld` if that's empty.
The object format follows the target's OS:

| OS | Format |
|---|---|
| `Linux`, `None`, `SlopOS` | ELF |
| `Windows`, `UEFI` | PE/COFF |
| `Mac` | Mach-O |

`TargetOptions.linker_script` places sections, for outputs loaded at fixed addresses like kernels.
`OutputType.FlatBinary` links the same way, then keeps only the loadable bytes.

### Starting on Linux

A hosted Linux program's entry is called as C's `main` is, with `argc`, `argv` and `envp`, which it keeps in the
runtime's process state for `runtime.process_arguments` and `std/os`'s environment. Without the C library, its `_start`
finds them on the stack the kernel set up (`argc`, then `argv`'s pointers and a null, then `envp`'s); with it, libc
passes them.

### Linux on AArch64

`--arch=aarch64` with `--os=linux` builds the same programs for 64-bit Arm: the runtime and `std/os` make the generic
system call table's calls (`clone`, `dup3`, `ppoll` and `renameat2` where x86-64 has `fork`, `dup2`, `poll` and
`renameat`), with `svc #0`, and threads, fibers, `morestack` and linking C all work as on x86-64. Without `--cpu`, code
is for ARMv8.2-A with the LSE atomics, which every 64-bit Arm server and desktop CPU of the last several years has.
The carrier register is `x28` (see [calling_convention.md](calling_convention.md#carrier-register)). An x86-64 Linux
machine can run the programs with `qemu-user`, given the AArch64 C library for those that link it.

### Linking C on Linux

A hosted Linux program is normally static, with no C library: the runtime makes its own system calls
(`base/runtime/linux.hsc`), it starts at a `_start` of its own, and it ends with `exit_group`. One that declares
`#foreign` functions of its own (base's don't count) links the C library instead, dynamically, which
`intrinsics.uses_c_library()` tells the runtime:

* It starts through libc: its `_start` calls `__libc_start_main` with the program's entry as `main`, as `crt1.o`'s
  would, so libc sets itself up first, and `main`'s result goes to `exit`, which flushes C's streams.
* The runtime starts threads with `pthread_create`, on the stack it maps for them, so C sets up its own state on each
  thread that may call it, and joins them with `pthread_join`.
* Each thread's carrier block is in an ELF thread-local slot, where callbacks from foreign code find it, so `.c`
  functions with a context work, as on Windows.
* It's linked against the target's own libraries, from the folder `--sysroot` names: `libc.so` (a copy of `libc.so.6`
  does), the `lib<name>.so` of each other `#library`, and the dynamic linker (`ld-linux-x86-64.so.2`, or
  `ld-linux-aarch64.so.1` on AArch64). No C runtime objects are needed.

## Generating Everything

`--generate-all` generates every function the program's packages declare, used or not, but those that only run at
compile time (constraints, macros, and functions taking or giving a `compiler.Code`), rather than only those
reachable from its entry, so what the compiler can't generate yet shows up before anything calls it. Generic
functions are only generated for the type arguments something gives them. The compiler's tests build a program that
imports all of `std` this way, with each generic in `base` and `std` instantiated, for Windows, Linux and a target with
no operating system, so each one's `#if` code is generated too.

## Checking Secrets

`--valgrind-secrets` has `compiler.secret` and `compiler.declassify` tell Valgrind's Memcheck which values are
secrets, so running the program under it reports any branch or memory address that depends on one (see
[memory.md](memory.md#checking-the-machine-code)). It's for x86-64, and changes nothing outside Valgrind.

## Generating in Parallel

A large program's machine code is generated on several threads. LLVM simplifies the whole module first, which is
where functions are inlined into each other, wherever they are; then it's split by function into up to 8 parts,
about one for every 2,500 instructions, and each part is optimized function by function and generated into an
object file of its own, all at once, and the linker takes them all. Which part a function goes in depends only on
the program, so it builds the same every time. A small program, or an object file asked for on its own with `-c`,
is one part.

The same program builds to the same bytes every time on every target: a Windows program is linked with `/Brepro`,
so neither it nor its PDB holds the time it was linked.

## Timing a Build

`--time-phases` prints how long each phase of compiling took, on standard error, for finding what makes a build slow:

```
phase check: 53 ms
phase check kernel.elf: 34 ms
phase describe the program for the build's checks: 77 ms
phase a build check: 0 ms
phase generate kernel.elf: 82 ms
phase lower kernel.elf: 33 ms
phase   simplify the whole of kernel.elf.o: 540 ms
phase   optimize and assemble kernel.elf.o in 7 parts: 183 ms
phase optimize and assemble kernel.elf: 724 ms
phase link kernel.elf: 29 ms
```

Checking is the packages read, resolved and checked; generating makes the program's MLIR, lowering its LLVM IR, and
optimizing and assembling is LLVM's passes and machine code: for a program generated in parts, the whole module
simplified first, then the parts at once (see [Generating in Parallel](#generating-in-parallel)). A build package's
targets each have their own phases, and the time its checks take, and what describing the program to them takes, is
shown too. The linker is run directly, found on the PATH: `lld-link` for PE/COFF and `ld.lld` for ELF.

## Debug Info

`--debug` (`BackendOptions.debug_info` in a build package) gives the program debug info, so debuggers and stack traces
can name its functions and lines:

* Each Hemera function has a subprogram, and each statement a location, which become DWARF for ELF programs and
  CodeView for PE/COFF ones, which lld-link puts in a PDB next to the program. Inlined calls are described too.
* The program has a table of its functions' starts and names (`intrinsics.function_names`), so a stack trace can name
  each frame while it runs, with `runtime.function_at`. `runtime.printing_assertion_handler` does.
* With CodeView, `switch`-like branches don't use jump tables, since LLVM describes a table it has optimized away
  with a label that's never defined.

Stack traces give their frames as offsets into the program's image (`runtime.image_offset`), which are the same every
run, wherever the system loaded it. `hemera --symbolize` turns them into functions, files and lines, from the
program's PDB or DWARF, innermost first, with each call that was inlined:

```
hemera --symbolize=app.exe 0x146a 0x15bd

0x146a
    runtime.assert at <base>/runtime/assertion.hsc:38, inlined
    app.check at src/main.hsc:10, inlined
    app.main at src/main.hsc:15:4
0x15bd
    hemera_entry
```

An offset is a return address, so it's looked up one byte earlier, in the call. For ELF, offsets are from the lowest
load segment, where `__ehdr_start` is in an ordinary program; a kernel that gives its frames relative to where its
image was loaded, like one moved by KASLR, matches that.

Functions are never tail calls, with or without debug info, so a frame is never left out of a stack trace by a
caller whose frame was reused (see [calling_convention.md](calling_convention.md#walking-the-stack)).

## Target Options on the Command Line

Until a build package can set `TargetOptions` (it needs `#run`), the compiler takes the ones freestanding programs
need as flags:

| Flag | `TargetOptions` |
|---|---|
| `--os=none` | `os = .None`, which also makes the output ELF |
| `--no-startup-code` | `startup_code = false` |
| `--entry=name` | The entry function, `main` by default |
| `--no-red-zone` | `red_zone = false` |
| `--address-zero-is-memory` | `address_zero_is_memory = true`, for targets where address 0 is memory (docs/types.md, Pointers) |
| `--stack-check=trap` | `stack_check_failure = .Trap`; `off`, the default, leaves the check out until hosted startup code sets up a carrier block |
| `--code-model=kernel` | `code_model`: `default`, `small`, `kernel`, `medium` or `large` |
| `--relocation-model=static` | `relocation_model`: `static`, or `pic`, the default |
| `--cpu-features=...` | `cpu_features` |
| `--linker-script=path` | `linker_script` |
| `--sysroot=path` | The target's own libraries, for a Linux program that links C (see [Linking C on Linux](#linking-c-on-linux)) |

A kernel loaded by a bootloader, with SIMD left off since the bootloader may not enable it:

```
hemera --os=none --no-startup-code --entry=kernel_entry --no-red-zone --stack-check=trap \
    --cpu-features=-mmx,-sse,-sse2,-avx,-avx2,+soft-float --linker-script=kernel.ld --output=kernel.elf kernel
```

A function that starts without a context has no stack check, since there's no carrier block yet when it starts, so
the functions it calls aren't inlined into it, which keeps their checks.
