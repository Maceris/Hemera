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

Freestanding programs usually also set `TargetOptions.stack_check_failure` to `.Trap` or `.AssertionHandler`,
since they have no allocator for `morestack`.

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

A kernel loaded by a bootloader, with SIMD left off since the bootloader may not enable it:

```
hemera --os=none --no-startup-code --entry=kernel_entry --no-red-zone --stack-check=trap \
    --cpu-features=-mmx,-sse,-sse2,-avx,-avx2,+soft-float --linker-script=kernel.ld --output=kernel.elf kernel
```

A function that starts without a context has no stack check, since there's no carrier block yet when it starts, so
the functions it calls aren't inlined into it, which keeps their checks.
