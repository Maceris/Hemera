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
Their entry function then has to do it before calling any Hemera code that needs it:

1. Point a carrier block's `stack_limit` at the end of the stack, and load it with `intrinsics.set_carrier`.
2. `push_context` a context built from constants, like `runtime.FAILING_ALLOCATOR`, until there's a heap.

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
