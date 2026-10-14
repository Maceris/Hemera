# LLVM Patches

Changes Hemera needs in LLVM that aren't upstream. They're kept as patch files rather than committed to the
`llvm-project` submodule, which tracks upstream LLVM unchanged.

Apply them to the submodule before building LLVM:

```bash
cd apps/compiler/third-party/llvm-project
git apply ../patches/llvm/*.patch
```

`git apply --check` reports whether a patch still applies after updating LLVM.

## 0001-x86-split-stack-limit-register.patch

The prologue stack check from `docs/calling_convention.md` (*Prologue Stack Check*) on x86-64. LLVM's
segmented-stack prologue (the `"split-stack"` function attribute) compares the stack pointer against a limit in
thread-local storage, at an offset fixed per operating system, and refuses any other platform. This adds function
attributes to read the limit at an offset from a register the program reserves instead, which works on any
platform, including freestanding ones:

| Attribute | Meaning |
|---|---|
| `"split-stack-limit-register"="r14"` | Read the limit at an offset from this register (`r12` to `r15`). Reserve it with the `+reserve-r14` target feature |
| `"split-stack-limit-offset"="0"` | The offset, in bytes. Defaults to 0 |
| `"split-stack-failure"="trap"` | Run `ud2` when the stack is too small, instead of calling `__morestack` |

Hemera's carrier register is `r14`, and `stack_limit` is the first field of the carrier block, so a function
compiled with `.Trap` as its `stack_check_failure` gets:

```
    cmpq    (%r14), %rsp          # frames under 256 bytes
    jbe     .Ltrap
    ...
.Ltrap:
    ud2
```

Includes `llvm/test/CodeGen/X86/segmented-stacks-limit-register.ll`. LLVM's existing segmented-stack tests are
unchanged.
