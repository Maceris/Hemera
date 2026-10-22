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

## Build Packages

A program whose compile-time code registers targets with `compiler.add_target` is a build package: it produces
nothing itself, and once it's checked, the compiler builds each target it registered, in the same process, in the
order they were registered. A target is a root package and its `BuildOptions`, usually started from
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

Targets are built one at a time, and each is a program of its own: its files are read, parsed and checked for it,
even ones another target already used, since its `#if` choices, settings and package paths can make them mean
something else. The work within a target is spread across threads like any program's. Sharing parsed files between
targets, and building targets that don't depend on each other at the same time, are planned; neither will change
what a build produces (see Deterministic Output).

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
  does), the `lib<name>.so` of each other `#library`, and `ld-linux-x86-64.so.2`. No C runtime objects are needed.

## Generating Everything

`--generate-all` generates every function the program's packages declare, used or not, rather than only those
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
phase check: 150 ms
phase check kernel.elf: 168 ms
phase describe the program for the build's checks: 206 ms
phase a build check: 347 ms
phase generate kernel.elf: 267 ms
phase lower kernel.elf: 34 ms
phase optimize and assemble kernel.elf: 958 ms
phase link kernel.elf: 95 ms
```

Checking is the packages read, resolved and checked; generating makes the program's MLIR, lowering its LLVM IR, and
optimizing and assembling is LLVM's passes and machine code. A build package's targets each have their own phases,
and the time its checks take, and what describing the program to them takes, is shown too.

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
