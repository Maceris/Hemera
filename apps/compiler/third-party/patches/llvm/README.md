# LLVM Patches

Changes Hemera needs in LLVM that aren't upstream. They're kept as patch files rather than committed to the
`llvm-project` submodule, which tracks upstream LLVM unchanged.

Configuring the compiler applies them to the submodule, in order, skipping any already applied
(`apply_patches.cmake`), and stops with the reason if one doesn't apply, as can happen after updating LLVM. To apply
them by hand instead:

```bash
cd apps/compiler/third-party/llvm-project
git apply ../patches/llvm/*.patch
```

`git apply --check` reports whether a patch still applies, and `git apply --reverse --check` whether it's applied.

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
| `"split-stack-morestack"="symbol"` | Call `symbol` with Hemera's protocol instead of `__morestack`: a minimal frame (`push rbp`, `mov rbp, rsp`), the frame size in `r10`, the stack parameters' size in `r11`, the body's address in `rax`, `call symbol`, `pop rbp`, `ret` (`docs/calling_convention.md`, *Growing the Stack*) |

Hemera's carrier register is `r14`, and `stack_limit` is the first field of the carrier block, so a function
compiled with `.Trap` as its `stack_check_failure` gets:

```
    leaq    -FRAME(%rsp), %r11
    cmpq    (%r14), %r11
    jbe     .Ltrap
    ...
.Ltrap:
    ud2
```

With a limit register the frame's end is compared whatever the frame's size. LLVM's own segmented stacks compare the
stack pointer directly for frames under 256 bytes, which would let such a frame use most of a 256-byte guard before
anything that grows the stack is pushed.

Functions with a limit register don't mark the object with `.note.GNU-split-stack`, which tells linkers to adjust
calls into code without the check so they call `__morestack_non_split`. That's for limits in thread-local storage
grown through `__morestack`; with a carrier block, any function can be called from any other.

Includes `llvm/test/CodeGen/X86/segmented-stacks-limit-register.ll`. LLVM's existing segmented-stack tests are
unchanged.

## 0002-x86-classic-frame.patch

Hemera's frames on Windows x64 (`docs/calling_convention.md`, *Windows x64*). Apply it after 0001. LLVM gives every
function on Windows x64 the prologue its unwind information can describe: `push rbp`, `sub rsp, N`,
`lea rbp, [rsp + N]`, with `rbp` up to 240 bytes into the frame rather than at the saved one. The fiber resume loop,
`morestack` and stack walks follow `[rbp]` and `[rbp + 8]`, so this adds a function attribute to get the prologue
other targets have instead:

| Attribute | Meaning |
|---|---|
| `"classic-frame"` | On targets with Windows unwind information: `push rbp`, `mov rbp, rsp`, `sub rsp, N`, and no unwind information (no `.seh_*` directives). `llvm.frameaddress` is the frame pointer, as elsewhere |

Elsewhere it changes nothing. A function with it can't be unwound through by Windows' unwinder, so structured
exception handling and C++ exceptions can't pass through it.

Includes `llvm/test/CodeGen/X86/win64-classic-frame.ll`.

## 0003-aarch64-split-stack-limit-register.patch

The same prologue stack check on AArch64, which LLVM has no segmented stacks for at all. It takes 0001's attributes,
with `x27` or `x28` as the limit register (Hemera's carrier register is `x28`, reserved with `+reserve-x28`) and an
offset that's a multiple of 8. `x16` and `x17`, which nothing holds at a function's entry, are its scratch registers:

```
    ldr     x16, [x28, #OFFSET]
    sub     x17, sp, #FRAME
    cmp     x17, x16
    b.ls    .Lgrow
    ...
.Lgrow:
    brk     #1                  ; "split-stack-failure"="trap"
```

With `"split-stack-morestack"="symbol"`, `.Lgrow` calls `symbol` with Hemera's protocol on AArch64: a frame record
(`stp x29, x30, [sp, #-16]!`, `mov x29, sp`), the frame size in `x9`, the stack parameters' size in `x10`, the body's
address in `x11`, `bl symbol`, `ldp x29, x30, [sp], #16`, `ret`. `x0` to `x8` pass through untouched.

Functions with segmented stacks aren't shrink-wrapped, as on X86: the check has to come first, before any of the
function's own code, rather than just before the part that needs the frame.

Includes `llvm/test/CodeGen/AArch64/segmented-stacks-limit-register.ll`.

## 0004-aarch64-frame-record-at-top.patch

Hardware control-flow integrity on AArch64 (`docs/compilation.md`, *Control-Flow Integrity*). A function's return
address is signed with the stack pointer at its entry (`paciasp`), and a resumed fiber's frames return into the resume
loop (`docs/calling_convention.md`, *Resuming*), which has to sign its own return address the same way. It only knows
each frame's frame pointer, and outside Darwin LLVM puts the frame record at the bottom of the callee-saved registers,
so the entry stack pointer is the frame pointer plus their size, which differs from function to function. The
`"frame-record-at-top"` function attribute gives a function Darwin's order of callee-saved registers, which puts the
frame record at the top, so the entry stack pointer is always the frame pointer plus 16. Not on Windows, and not for
SVE's calling convention.

## 0005-landing-pads-after-calls.patch

The resume loop also reaches each frame's continuation, the instruction after a call, with an indirect branch, which
indirect branch tracking and branch target identification refuse unless a landing pad is there. LLVM puts one after a
call only to a `returns_twice` function, like `setjmp`. The `"landing-pads-after-calls"` function attribute puts one
after every call: `endbr64` on x86-64 (`X86IndirectBranchTracking`), `bti j` on AArch64 (`AArch64BranchTargets`), each
where the module enables that pass (`"cf-protection-branch"`, `"branch-target-enforcement"`).

The same patch makes a block whose address is taken a `bti jc` in such a function, rather than `bti j`: morestack
reaches a function's body with `blr`, which only a `bti c` or `bti jc` accepts.

## 0006-aarch64-split-stack-signed-frame.patch

On top of 0003: the frame `.Lgrow` makes to call morestack signs its link register (`paciasp` before it's stored,
`autiasp` before `ret`) when the function signs return addresses (`"sign-return-address"`). A fiber suspended on a
new stack segment has that frame in its chain, and the resume loop re-enters it like any other, signing its own return
address with the frame pointer plus 16, which is the stack pointer at its entry there too.
