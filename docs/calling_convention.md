# Calling Convention


## Our Convention
Passes an implicit context pointer on every call.
On x86-64 the caller pops the stack parameters, as in System V; a convention where the callee pops its own, which the
example below shows, isn't done yet.
Values too large for registers go through pointers (see [Large Values](#large-values)).
Every function keeps a base pointer, so the chain of saved base pointers always links every frame to its caller's
(`morestack` and resuming fibers both rely on it).

### Version

This convention is `hemera-abi-v1`. Anything that separately compiled code or tools depend on gets a new version
when it changes: register use, frame layout, carrier block and fiber offsets, the fiber resume loop
(`FiberResumeState`, `.loop_return`), stack segment layout, and the layout of `RegisterFrame` for
[entry functions](#entry-functions). Within a version, those are stable, so debuggers and
profilers can unwind suspended fibers from outside the process.

### Carrier Register

One register always holds a pointer to the current thread's carrier block (see [multitasking.md](multitasking.md#carriers)):

| Architecture | Register |
|--------------|----------|
| x86-64       | `r14`    |
| AArch64      | `x28`    |
| RISC-V 64    | `s11`    |

The register allocator never uses it, functions never save or restore it, and fiber switches leave it alone.
It is callee-saved in the platform conventions, so foreign code preserves it too.
It is only loaded from the OS's thread-local storage when a thread starts, and when foreign code calls into Hemera.
Code that starts without Hemera's startup code (freestanding entry points, [interrupt functions](#interrupt-functions),
[entry functions](#entry-functions),
threads on systems without thread-local storage) loads it itself with `intrinsics.set_carrier`.

The first field of the carrier block is `stack_limit`, so the prologue check below is a single memory operand.

### Stack Frame

With the stack growing downwards, a stack frame is formatted like this:

                 (higher addresses /\)
|                                                        |                                                |
|--------------------------------------------------------|------------------------------------------------|
| (Previous Stack Frame)                                 |                                                |
|--------------------------------------------------------|------------------------------------------------|
| Pointers to Return Values                              | Written by the caller, but owned by this frame |
| Stack Parameters                                       |                                                |
|-  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  - |                                                |
| Return Address                                         |                                                |
| Base Address of Previous Frame                         | Callers base pointer                           |
|-  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  - |                                                |
| Local Variables                                        |                                                |
| Callee-Saved Registers                                 | <- The bottom of this is the stack pointer     |
|                                                        |    whenever this frame calls out to another    |
|                                                        |    function                                    |
|--------------------------------------------------------|------------------------------------------------|
| (Next Stack Frame)                                     | Outgoing arguments go here                     |
                  (lower addresses \/)

#### Large Values

A result or parameter larger than 16 bytes, more than two registers hold, goes through memory. Frames never move once
they are created, including on fibers, so it's through plain pointers:

* **Results.** The caller passes a pointer to room for them as the first argument, before the context, and the callee
  writes its results there and returns nothing. Several results count together: if they come to more than 16 bytes,
  they're written as a struct of them, in order.
* **Parameters.** The caller makes a copy in its own frame and passes a pointer to it, and the callee uses that copy as
  its parameter, so nothing it does to it changes the caller's value.

That's Hemera's own convention. A function with a `#calling_convention`, like `.c`, follows that convention instead,
and `#foreign` functions only take and give values that fit a register so far
(see [directives.md](directives.md#foreign-library-and-link_name)).

#### Concrete Example

Example stack:
```
main :: fn() { // 0xABCD
    // calls foo somewhere
}

foo :: fn(a, b : LargeStruct) { // 0xCAFE
    unimportant : u8 = 5
    c : BigStruct : bar(a)
}

bar :: fn(d: LargeStruct) -> BigStruct { // 0xBABE
    e : BigStruct
    // Frame shown here
    // ...
    return e
}
```

This example assumes x86-64, with `LargeStruct` being 32 bytes and `BigStruct` being 48 bytes, so neither fit in registers.
It shows the frames as a convention where the callee pops its arguments would lay them out, which isn't done yet: today
the pointer to `c` is bar's first argument, in a register, `d` is passed as a pointer to foo's copy of `a`, and bar
returns with a plain `ret` (see [Large Values](#large-values)). What it shows about base pointers, frame bottoms and
resuming is the same either way.
`main` is the fiber's entry function, and its stack pointer is `0x2000` when it calls `foo`.
The context pointer is passed in a register, so it only shows up in a frame if it gets spilled.
Addresses like `0xAC0A` stand for "somewhere inside that function, just after the call instruction".

Each frame's bottom is 16-byte aligned, and so is the stack pointer at every `call`,
which is why `foo` and `bar` end with padding, and `bar`'s arguments include 8 bytes of padding.

| Address  | From BP | Value                                              | Notes                                                     |
|----------|---------|----------------------------------------------------|-----------------------------------------------------------|
|          |         | (main's Stack Frame)                               | main's BP is `0x2030`                                     |
| `0x2000` |         | ---------------- foo's frame top ----------------- | main's stack pointer when it called foo                   |
| `0x1FE0` | BP+48   | (contents of b, 32 bytes)                          | Stack parameter, written by main                          |
| `0x1FC0` | BP+16   | (contents of a, 32 bytes)                          | Stack parameter, written by main                          |
| `0x1FB8` | BP+8    | `0xAC0A`                                           | Return address, in main right after `call foo`            |
| `0x1FB0` | BP      | `0x2030`                                           | main's BP. foo's BP points here                           |
| `0x1F80` | BP-48   | (space for c, 48 bytes)                            | bar writes its return value here                          |
| `0x1F78` | BP-56   | (space for unimportant, 1 byte + 7 padding)        |                                                           |
| `0x1F70` | BP-64   | (saved rbx)                                        | main's value of rbx                                       |
| `0x1F68` | BP-72   | (saved r12)                                        | main's value of r12                                       |
| `0x1F60` | BP-80   | (padding)                                          | foo's frame bottom, foo's stack pointer when it calls bar |
|          |         | ---------------- bar's frame top ----------------- |                                                           |
| `0x1F58` | BP+56   | `0x1F80`                                           | Pointer to c, where bar writes its return value           |
| `0x1F50` | BP+48   | (padding)                                          | Keeps the stack pointer 16-byte aligned at `call bar`     |
| `0x1F30` | BP+16   | (contents of d, 32 bytes)                          | Stack parameter, a copy of a written by foo               |
| `0x1F28` | BP+8    | `0xCB1C`                                           | Return address, in foo after `call bar`                   |
| `0x1F20` | BP      | `0x1FB0`                                           | foo's BP. bar's BP points here                            |
| `0x1EF0` | BP-48   | (space for e, 48 bytes)                            |                                                           |
| `0x1EE8` | BP-56   | (saved rbx)                                        | foo's value of rbx                                        |
| `0x1EE0` | BP-64   | (padding)                                          | bar's frame bottom (frame shown here)                     |

The "From BP" column for each row is relative to the base pointer of the frame that row belongs to.

When bar runs `return e`:
1. Read the pointer at `[BP+56]` (`0x1F80`), and copy e from `0x1EF0` to `0x1F80`, which is c.
2. Restore rbx from `0x1EE8`, then `mov rsp, rbp`, `pop rbp` (BP is `0x1FB0` again), and `ret 48`, which pops bar's 48 bytes of arguments.
3. The stack pointer is now `0x1F60`, foo's frame bottom, exactly where it was before foo started the call.

That last property, that a callee always returns with the stack pointer at its caller's frame bottom, is what lets
a suspended fiber be resumed one frame at a time (see below).

#### The Same Frames, Suspended and Resumed

Say bar called `fiber_yield()`, the scheduler suspended the fiber, and the fiber is resumed later on another carrier.
The frames stay exactly where they were.

The loop first re-enters the scheduler's yield function and `fiber_yield`, which return.
`fiber_yield`'s return leaves the stack pointer at `0x1EE0`, bar's frame bottom, and the loop re-enters bar:
it saves bar's return address (`0xCB1C`) and foo's BP (`0x1FB0`), sets the stack pointer to `0x1F30`, and calls `fiber_reenter`:

| Address  | From BP | Value                         | Notes                                                                       |
|----------|---------|-------------------------------|-----------------------------------------------------------------------------|
| `0x1F58` | BP+56   | `0x1F80`                      | Unchanged                                                                   |
| `0x1F30` | BP+16   | (contents of d)               | Unchanged                                                                   |
| `0x1F28` | BP+8    | `.loop_return`                | Pushed by the loop's `call`. `0xCB1C` is in the carrier's `resume_return`   |
| `0x1F20` | BP      | `0x1FB0`                      | Unchanged                                                                   |
| `0x1EF0` | BP-48   | (e)                           |                                                                             |
| `0x1EE8` | BP-56   | (saved rbx)                   | foo's value of rbx                                                          |
| `0x1EE0` | BP-64   | (padding)                     | `fiber_reenter` sets the stack pointer here, BP to `0x1F20`, and jumps back into bar |

When bar runs `return e` this time:
1. It does exactly the same thing as before: e is copied to `0x1F80`, which is c, in foo's frame.
2. `ret 48` pops `.loop_return`, which matches the shadow stack, and leaves the stack pointer at `0x1F60`, foo's frame bottom.
3. The loop re-enters foo: it saves `0xAC0A` and main's BP (`0x2030`), sets the stack pointer to `0x1FC0`, and calls
   `fiber_reenter`, which writes `.loop_return` into `0x1FB8`, sets BP to `0x1FB0` and the stack pointer to `0x1F60`,
   and jumps to `0xCB1C`.
4. foo continues after `call bar` with the stack pointer at its frame bottom, and finds the result in c at `BP-48 = 0x1F80`.

If foo yields again before it returns, `fiber_suspend` puts `0xAC0A` back into `0x1FB8`, so a suspended fiber's
frames always hold their real return addresses (which is also what debuggers walking them need).

### Windows x64

On Windows, Hemera's own functions use System V's registers rather than Windows': arguments in `rdi`, `rsi`, `rdx`,
`rcx`, `r8` and `r9`, `rbx`, `rbp` and `r12` to `r15` callee-saved, no shadow space, and `xmm6` to `xmm15` not kept.
Their frames are the ones above: `push rbp`, `mov rbp, rsp`, `sub rsp, N`, with `rbp` pointing at the saved one
whatever the frame's size, and no red zone. So the fiber switches, the resume loop, `morestack` and stack walks are
the same code on every x86-64 system.

Windows' convention stays where code crosses into or out of Hemera: `.c` functions, the program's entry, and calls to
foreign functions. A function using Windows' convention that calls Hemera code saves `xmm6` to `xmm15` itself.

The cost is unwind information. Windows finds x64 frames through tables the compiler emits for each function, and its
own prologues (`push rbp`, `sub rsp, N`, `lea rbp, [rsp + N]`) point `rbp` up to 240 bytes into the frame, which breaks
the chain. Hemera's functions get the classic prologue and no tables instead (the `"classic-frame"` attribute,
`apps/compiler/third-party/patches/llvm`). Windows' unwinder can't step through them, so:

* Structured exception handling's frame-based handlers and C++ exceptions can't pass through Hemera frames. Crashes
  are caught with vectored exception handlers, which run before any unwinding, as the compiler does for compile-time
  code.
* Debuggers that rely on the tables show Hemera frames as leaf functions.
* `capture_stack_trace` follows the frame chain, as on other systems (see [Walking the Stack](#walking-the-stack)).

A frame bigger than a page still touches each page in order first, through `__chkstk`, which the compiler defines.
Stack segments are committed memory, so that works on them too.

The thread environment block's stack bounds stay those of the thread's own stack, even while a fiber runs on a
segment; switching fibers doesn't change them, unlike Windows' own fibers. System code only runs on the thread's own
stack, since foreign calls move there first ([Calls to Foreign Code](#calls-to-foreign-code)), so the bounds are right
whenever it reads them. A fault in Hemera code on a segment reaches vectored exception handlers, which run before
Windows looks at the bounds to walk frames, as Go relies on too.

### Prologue Stack Check

Every function checks that it has room on the current stack segment before it builds its frame,
comparing against `stack_limit` in the carrier block:

```
; FRAME is the frame size, saved registers included, plus the largest outgoing argument area
foo:
    lea     r11, [rsp - FRAME]
    cmp     r11, [r14 + CARRIER_STACK_LIMIT]
    jbe     .grow
.body:
    push    rbp
    mov     rbp, rsp
    ; ...
```

Every function with a frame compares where its frame will end, whatever its size, so after any prologue the stack
pointer is at or above `stack_limit`. Functions without a frame, which use nothing below the return address, don't
check at all.

`stack_limit` is `STACK_GUARD` (256) bytes above the real end of the segment. Below it there only has to be room for
what's pushed while growing: the next call's return address, `.grow`'s saved base pointer and its call into
`morestack`, and `morestack`'s own frame (about 64 bytes), plus `fiber_suspend`'s (64 bytes, or 80 with SSE), since a
fiber suspends from wherever it is. (LLVM's own segmented stacks compare the stack pointer directly for frames under
256 bytes, which would let such a frame use most of the guard before anything is pushed; the patch for Hemera's limit
register always compares the frame's end.)

The check costs a load, a compare and a predicted branch. Plain threads run on segments like fibers, so the check
grows their stacks too. On a thread with a fixed stack, `stack_limit` is that stack's limit, so the same check catches
stack overflow there.

What happens when the check fails is a per-target option, `TargetOptions.stack_check_failure`: call `morestack`
(the default) or trap. Code with one fixed-size stack and no allocator, like a kernel, traps. Nothing runs Hemera code
in the failing prologue itself: there's no reliable context there (LLVM drops a context parameter a function doesn't
use), and only the guard's bytes of stack, so a handler would need a stack of its own, which is what a trap gets from
whatever handles faults, like a kernel's handler for invalid instructions.

### Growing the Stack: morestack

`.grow` is out of line, at the end of the function, so the normal path falls straight through:

```
.grow:
    push    rbp                  ; a minimal frame, so this function has its own link in the base pointer chain
    mov     rbp, rsp
    mov     r10d, FRAME          ; the frame size, including the outgoing argument area
    mov     r11d, PARAM_BYTES    ; the size of this function's stack parameters
    lea     rax, [rip + .body]
    call    morestack            ; runs .body on a new segment, returns once it has returned
    pop     rbp
    ret                          ; return to the original caller
```

`r10`, `r11` and `rax` stand for scratch registers that aren't used for arguments. On x86-64 the caller pops the
stack parameters, from the argument area at the bottom of its own frame, so `.grow` returns with a plain `ret`
(with a convention where the callee pops them, it would be `ret PARAM_BYTES`).

The minimal frame matters when a fiber is suspended while the function is running on the new segment:
the resume loop re-enters frames by following base pointers, and without it the `ret PARAM_BYTES` above would be
re-entered as if it belonged to the caller, and fail the shadow stack check.

`morestack` is an ordinary function as far as frames are concerned:

```
morestack:
    push    rbp
    mov     rbp, rsp                        ; [rbp+8]: return into .grow, [rbp+16]: .grow's saved BP,
                                            ; [rbp+24]: the original return address, [rbp+32]: the stack parameters
    push    [r14 + CARRIER_STACK_LIMIT]     ; [rbp-8]
    push    [r14 + CARRIER_STACK_SEGMENT]   ; [rbp-16]
    ; take a segment big enough for FRAME, PARAM_BYTES and STACK_GUARD: the carrier's spare, or one from its cache,
    ; or a new one (below)
    ; copy PARAM_BYTES from [rbp+32] to the top of the new segment
    ; set the carrier's stack_segment and stack_limit to the new segment
    ; rsp = new segment top - PARAM_BYTES
    call    rax                             ; the function's body, on the new segment
.continue:                                  ; it returned and popped its parameters
    lea     rsp, [rbp - 16]
    ; the segment just left becomes the carrier's spare (an older spare goes back to the cache)
    pop     [r14 + CARRIER_STACK_SEGMENT]
    pop     [r14 + CARRIER_STACK_LIMIT]
    pop     rbp
    ret
```

The function's body pushes `morestack`'s base pointer as its saved base pointer, and its return address is
`.continue`, so the base pointer chain goes function body → `morestack` → `.grow`'s frame → the original caller,
like any other chain of calls. Return values are written through pointers, so they land in the caller's frame
on the old segment.

Every transition is a real `call` matched with a real `ret`, so this works with shadow stacks.

With no segment big enough in the cache, `morestack` allocates one with `runtime.allocate_stack_segment`, which runs
on the thread's native stack, since the current one has no room left:

* On a fiber, below the scheduler's stack pointer. On a thread already on a segment, below `native_sp`, which
  `morestack` recorded in the carrier block when it first took the thread off its native stack. On a thread still on
  its native stack, or inside foreign code, where it is.
* It saves the argument registers (and `xmm0` to `xmm7`, with SSE), the body's address and the parameters' size there
  first, and puts them back after.
* The allocation counts as foreign code (`foreign_depth`), so nothing in it yields, and foreign calls it makes, like
  the system's heap, stay on the native stack rather than moving again. It runs with no stack limit: a thread may
  already be at its native stack's limit, which leaves room below it for this (`NATIVE_STACK_RESERVE`).
* `allocate_stack_segment` takes no context, since the function being grown may not have one to give: LLVM drops a
  parameter an internal function doesn't use, the context included. It uses the carrier's `segment_allocator`, set
  when the thread starts from its context's allocator, and traps without one or without memory.

A segment, once allocated, stays with the carriers: it goes back to the cache of whichever carrier the fiber
returns from it on.

`morestack` is generated by the compiler, for targets whose `stack_check_failure` is `.Morestack`: for now x86-64
targets. Until the body runs, it only uses `rax`, `r10` and `r11`, and two callee-saved registers it saves and
restores, so the function's arguments reach the body untouched.

### Calls to Foreign Code

A call to a foreign function goes through a shim that:

1. Increments the carrier's `foreign_depth` and saves the current context pointer in the carrier,
   for any callbacks.
2. If the stack pointer is on a segment, switches to the thread's native stack (on a fiber, just below where the
   scheduler's stack pointer was when it resumed the fiber), copies any stack arguments,
   and sets `stack_limit` to that stack's limit. On systems that don't give every thread a stack, the native stack is
   allocated here on the thread's first foreign call.
3. Calls the function with the platform's convention.
4. Undoes 2 and 1.

The compiler makes one shim per foreign function (see `#foreign` in [directives.md](directives.md#foreign-library-and-link_name)),
which Hemera code calls with the platform's convention, so the arguments are already where the function expects them.
On x86-64 the shim builds a frame like any other, so the frame chain continues through it, saves `rbx` and `r12`, and
only uses `rax` until the call. On a fiber (the carrier's `current_fiber` isn't null), it moves to the scheduler's
stack pointer, aligned down to 16 bytes, and sets `stack_limit` to the carrier's `native_stack_limit`; elsewhere it
stays where it is. Either way it copies the stack arguments: on Windows x64, the ones after the first four, above
the 32 bytes of shadow space it leaves; on System V, the integers after the first six and the floating-point values
after the first eight, in order. Results come back in `rax` or `xmm0`, untouched. On Windows the native stack is also
the stack the thread environment block describes, so system functions that check where they're running, and
Windows' exception dispatch, see the stack they expect.

A thread on a segment moves below `native_sp` instead, where `morestack` took it off its native stack. Only the
outermost foreign call moves: one made while `foreign_depth` is already above zero (from foreign code, or from
`morestack` allocating a segment) is on the native stack already.

Not done yet: allocating a native stack on systems that don't give threads one.

Each call to a foreign function also keeps the caller's context in the carrier block's `foreign_context` for the
call, and puts back what was there after, so callbacks from inside it run with the caller's context.

Hemera functions that foreign code can call (`.c` functions with a context) get an entry shim, which has the
function's symbol and is what its value points to:

1. It keeps foreign code's value of the carrier register.
2. It loads the thread's carrier block from the OS's thread-local storage. With a slot below 64, which the program
   allocates first thing, that's one load from the thread environment block (`gs:[0x1480 + 8 * slot]`). Otherwise,
   or on a thread that has never run Hemera code, where that load is null, `runtime.callback_carrier` finds it,
   with a temporary carrier block on the shim's stack loaded meanwhile, counting a foreign call, since finding the
   real one makes foreign calls itself. A thread Hemera didn't start gets a carrier block of its own the first
   time, from the process heap, with its stack's limits, kept for the rest of the thread's life.
3. It calls the function's body with the context the foreign call it's inside kept (`foreign_context`), or, on a
   thread Hemera didn't start, `HOSTED_CONTEXT`.
4. It puts foreign code's carrier register back.

The body runs where the shim was called: on the native stack, which a foreign call from a fiber already moved to,
with `foreign_depth` still counting that call, so nothing in it yields, and foreign calls from it stay where they
are. Hemera code calling the function by name calls its body directly, with its own context. The thread-local
storage slot is the program's (`intrinsics.carrier_slot`), allocated by `runtime.register_carrier`, which the program's
entry calls for the main thread and each thread's entry for itself. On Linux x86-64, for a program that links C, the
slot is an ELF thread-local variable, which libc sets up on every thread, and a thread Hemera didn't start gets a carrier
block with no stack limit, since its stack's bounds aren't known. Windows x64 and Linux x86-64 linking C, so far.

### Suspending and Resuming a Fiber

A suspended fiber's state is on its own stack, where `fiber_suspend` pushed it, and the fiber's `FiberResumeState`
(`base/runtime/fiber.hsc`) only keeps `saved_sp`, where it is. From `saved_sp` up, on x86-64:

| Offset           | Contents                                                                |
|------------------|-------------------------------------------------------------------------|
| 0                | MXCSR and the x87 control word, 16 bytes, only with SSE (*F* = 16, else 0) |
| *F*              | Base pointer of the innermost suspended frame (the top frame)           |
| *F* + 8          | The carrier's `stack_limit` for the fiber's current segment            |
| *F* + 16         | The carrier's `stack_segment` for it                                    |
| *F* + 24 to + 48 | `r15`, `r13`, `r12`, `rbx`                                              |
| *F* + 56         | `fiber_suspend`'s return address: where the top frame continues          |

While a fiber runs, the resume loop's state is in the carrier block, since a fiber only runs on one carrier at a time:

| Field           | Meaning                                                                          |
|-----------------|----------------------------------------------------------------------------------|
| `resume_frame`  | The frame most recently re-entered, whose return address slot points at the loop |
| `resume_return` | The original contents of that slot (still signed, on AArch64)                    |
| `resume_parent` | That frame's caller's base pointer, saved before it could be popped              |

#### Suspending

The scheduler's yield function runs on the fiber's stack, and calls `fiber_suspend` once it has decided to switch:

```
fiber_suspend:
    push    callee-saved registers (never r14)
    push    carrier.stack_segment, carrier.stack_limit
    push    rbp                             ; the caller's frame, fiber_suspend doesn't build one
    push    MXCSR and the x87 control word  ; with SSE
    fiber.saved_sp = rsp                    ; the return address above all this is where the fiber continues
    if carrier.resume_frame:
        [carrier.resume_frame + 8] = carrier.resume_return   ; suspended frames always hold real return addresses
        carrier.resume_frame = null
    INCSSP  (carrier.shadow_stack_base - RDSSP) / 8   ; drop the fiber's entries from this thread's shadow stack
    rsp = carrier.scheduler_sp
    pop     the scheduler's callee-saved registers
    eax = .Yielded
    ret                                     ; fiber_resume / fiber_start returns to the scheduler
```

When shadow stacks aren't enabled, `RDSSP` and `INCSSP` do nothing (start with a register holding 0, so the
difference is 0). `INCSSP` pops at most 255 entries at a time, so it runs in a loop.

#### Resuming

```
fiber_resume(fiber) -> FiberExit:           ; called by the scheduler, on the carrier thread's own stack
    push    the scheduler's callee-saved registers
    carrier.scheduler_sp      = rsp
    carrier.shadow_stack_base = RDSSP       ; the top entry is the return into the scheduler
    carrier.current_fiber     = fiber
    carrier's stack_segment, stack_limit = the ones at fiber.saved_sp
    frame = the top frame at fiber.saved_sp,  cont = the return address there,  restore_registers = true

reenter_next:
    carrier.resume_frame  = frame
    carrier.resume_return = [frame + 8]
    carrier.resume_parent = [frame]
    rsp = frame + 16                        ; just above the frame's return address slot
    call    fiber_reenter                   ; pushes .loop_return into [frame + 8], and onto the shadow stack

.loop_return:                               ; the frame returned. Return value and callee-saved registers are untouched
    bottom = rsp                            ; the callee popped its parameters, so this is the caller's frame bottom
    cont   = carrier.resume_return
    frame  = carrier.resume_parent
    restore_registers = false
    jmp     reenter_next

fiber_reenter:                              ; only ever reached by the call above
    rbp = frame
    if restore_registers:
        rsp = fiber.saved_sp
        skip MXCSR, the top frame, the limit and the segment
        pop     callee-saved registers, and skip fiber_suspend's return address
    else:
        rsp = bottom
    jmp     cont
```

The loop keeps `frame`, `cont`, `bottom` and `restore_registers` in scratch registers that aren't used for return values,
and copies through another such register (on x86-64 System V: `r10`, `r11`, `rcx`, `rsi`, and `r9` for copying, with the
fiber in `rdi`). Switching away from the scheduler also saves the carrier's `stack_limit`, `stack_segment` and
`current_fiber` on the scheduler's stack, and switching back restores them.

While the loop re-enters a frame, the stack pointer is just above that frame's return address slot, so the frame's live
data is below the stack pointer until the jump to `cont`. Anything that pushes onto the current stack in that moment
overwrites it. In a process that's a signal handler without an alternate stack, which the runtime avoids (see
[multitasking.md](multitasking.md#signals)). A kernel that runs fibers has to take interrupts on a stack of their own,
or mask them while fibers run.

Re-entering every frame with a `call` means each frame's eventual `ret` pops an address that was really pushed,
both on the stack and on the shadow stack. No return address is ever rewritten by anything but a `call`,
the fiber doesn't need its own shadow stack, and frames never move.

Implemented for x86-64: System V, Windows (whose Hemera frames chain the same way, see [Windows x64](#windows-x64)),
and freestanding.

The loop doesn't need a way to stop. The fiber's bottom frame is `fiber_entry` (see `fiber_start` in
`base/intrinsics/fibers.hsc`), which is re-entered like any other frame. Its continuation is the code that runs
when the fiber's function returns, which switches back to the scheduler with `.Finished`, the same way `fiber_suspend` does.

`cont` is reached with an indirect jump. On builds that enable indirect branch tracking, the compiler puts an
`endbr64` after every call instruction, since any call might be suspended across.
On other builds nothing is added.

#### AArch64

The frame record is the saved frame pointer (`x29`) and link register (`x30`) at the frame pointer,
the same shape as the x86-64 frame above, so the loop is the same, with these differences:

* The loop re-enters with `bl fiber_reenter`, which pushes onto the Guarded Control Stack when GCS is enabled.
* Functions reload the link register from their frame record before returning. So `fiber_reenter` also stores
  the loop's return address into `[frame + 8]`. With pointer authentication enabled, it signs it first with the
  same modifier the frame's prologue used (its stack pointer on entry, which is `frame + 16`).
  This only ever signs that one fixed address.
* `fiber_suspend` writes `resume_return` back exactly as it was, still signed, so nothing else needs re-signing.
* Shadow stack entries are dropped with `GCSPOPM` in a loop. (I'm not aware of a bulk equivalent of `INCSSP`.)
* Builds with branch target identification put `bti j` after every call instead of `endbr64`.

#### Walking the Stack

Stack traces aren't recorded as code runs. `intrinsics.capture_stack_trace` builds one when asked, by following
saved base pointers from the current frame and collecting each frame's return address (`[BP + 8]`). Every function
keeps its frame pointer for this, so the chain is never broken by an optimized-out frame, and no call is made a tail
call, which would reuse its caller's frame and leave the caller out. A function inlined into its caller has no frame
of its own, so its addresses are its caller's:

* Across segments, `morestack` and `.grow` build ordinary frames, so the chain leads from a function on a new segment
  back to its caller on the old one. A body that `morestack` ran returns to `morestack`'s continuation, and
  `morestack`'s own frame returns into the function's `.grow`, so the walk leaves out both of those addresses: the
  next one is the function's real caller.
* On a running fiber, the outermost re-entered frame's return address is `.loop_return`. When the walk reaches it,
  it continues with the carrier's `resume_return` as that frame's real return address, and `resume_parent` as the
  next frame.
* On a suspended fiber (`intrinsics.capture_fiber_stack_trace`), the trace starts with the return address at the top
  of what `fiber_suspend` saved, and the walk with the top frame saved below it. `fiber_suspend` has already put the real return address back, so the chain is ordinary all the way
  down. The fiber switches keep the fiber's `state` current (`.Running` or `.Suspended`), and a fiber that isn't
  suspended gives an empty trace.
* The walk stops at `fiber_entry` for fibers (whose address is the last one, as the fiber function's caller's), and at the thread's entry function for threads. A program's entry
  function (the startup code's, or the freestanding entry) clears the frame pointer it saved, since whatever called it
  isn't Hemera code: the walk ends there, without its caller's return address.
* An interrupt function's frame chains to the interrupted code's, so a trace from a fault handler continues through the
  code that faulted.
* On AArch64 with pointer authentication, return addresses are stripped (`XPACI`) before being recorded.

Turning the addresses into function names, files and lines uses the debug information, and only happens when a
trace is printed or reported.

### Interrupt Functions

A function declared with `#calling_convention(.interrupt)` is entered by the CPU through the interrupt descriptor
table, not called (x86-64 only, like LLVM's `x86_intrcc`). It takes a pointer to the frame the CPU pushed, and for
the exceptions that push an error code, the code as a second parameter:

```
timer_interrupt #calling_convention(.interrupt) :: fn(frame: ptr[x86_64.InterruptFrame]) {/* ... */}
page_fault #calling_convention(.interrupt) :: fn(frame: ptr[x86_64.InterruptFrame], error_code: u64) {/* ... */}
```

* It saves every register it changes, and returns with `iretq`.
* It can't be called from Hemera code. Its address goes in the interrupt descriptor table.
* It gets no context, and the carrier register holds whatever the interrupted code had, which may not be a
  carrier at all (user-mode code, for example). So its prologue has no stack check, and before calling anything
  that needs them, it loads a carrier block with `intrinsics.set_carrier` (found through per-CPU data, like the
  `gs` base after `swapgs`) and pushes a context with `push_context ... from`
  (see [control_flow.md](control_flow.md#functions-without-a-context)).

### Entry Functions

Entry functions are how a kernel is entered from user mode, and returns to it (x86-64 only for now). Unlike an
[interrupt function](#interrupt-functions), an entry function gets every register of the interrupted code as data,
in a `RegisterFrame`, and doesn't have to return to it: a kernel can save the frame, switch to another thread, and
leave with `x86_64.return_to_user`.

```
user_entry #calling_convention(.entry) :: fn(frame: ptr[mut x86_64.RegisterFrame]) #never_returns {
    // No carrier yet: find this CPU's through per-CPU data, then set up a context
    cpu : ptr[ArchCpu] : cast[ptr[ArchCpu]](x86_64.read_gs_base())
    intrinsics.set_carrier(cpu.carrier)
    push_context cpu_context from cpu.context^ {
        dispatch(frame)
    }
}

system_call #calling_convention(.syscall_entry) :: fn(frame: ptr[mut x86_64.RegisterFrame]) #never_returns {/* ... */}
```

`#calling_convention(.entry)` is entered through the interrupt descriptor table. The generated code before the body:
1. pushes the vector number, and an error code of 0 for vectors where the CPU doesn't push one, so the frame always
   has the same shape;
2. runs `swapgs` if the interrupted code was in user mode. For NMIs, machine checks and double faults, which can arrive
   between a `swapgs` and the `iretq` after it, it decides from `IA32_GS_BASE` instead of the saved `cs`: the kernel's
   is an upper-half address, and anything else is swapped;
3. pushes every general register, completing the `RegisterFrame` on the stack the CPU switched to;
4. clears `rbp`, so stack walks end at the entry, and the direction flag, then calls the body with a pointer to the
   frame.

The function can't be called from Hemera code. Its addresses come from `x86_64.entry_points`, which the compiler
expands into one small stub per vector (256 in all) that pushes the vector number and jumps to the function:

```
// handler is a generic parameter too, so it must be known at compile time
idt_addresses :: x86_64.entry_points(user_entry)
```

`#calling_convention(.syscall_entry)` is the target of the `SYSCALL` instruction (`IA32_LSTAR`). The CPU pushes nothing
and leaves the user's stack pointer, so the generated code runs `swapgs`, saves the user's `rsp` and loads the kernel
stack using the `x86_64.SyscallScratch` the `gs` base points at, then builds the `RegisterFrame` from the registers
(`rip` from `rcx`, `rflags` from `r11`, `vector` is `x86_64.SYSCALL_VECTOR`).

For both:
* The body starts like an interrupt function's: no stack check in its prologue, no carrier block and no context until it
  sets them up with `intrinsics.set_carrier` and `push_context ... from`.
* Interrupts stay as the CPU left them (disabled through an interrupt gate, or by `IA32_FMASK` for `SYSCALL`).
* A `.entry` function may return, which is meant for NMIs: the generated code restores the frame and returns with
  `iretq`, with the matching `swapgs`. One function can serve every vector and return only for some, since
  `entry_points` takes a function that may return. A `.syscall_entry` function is always `#never_returns`.
* The frame is the body's to change: a `.entry` function that returns resumes with whatever the frame holds then.

`x86_64.return_to_user(frame)` restores every register from a frame and returns to user mode: `swapgs`, then `sysretq`
when its conditions hold (`rcx == rip`, `r11 == rflags`, and `rip` canonical), otherwise `iretq`. Since `RegisterFrame`'s
layout is part of the convention version, a kernel may keep frames in its thread structures and return through any of
them.

The compiler generates these sequences itself; Hemera has no inline assembly.

### Functions Entered from Outside

A function that something other than Hemera code calls, like a bootloader starting the program or another CPU, is
declared with the platform's C convention and without a context:

```
cpu_start #calling_convention(.c) #no_context :: fn(info: ptr[MpInfo]) #never_returns {
    carrier : runtime.CarrierBlock
    carrier.stack_limit = /* ... */
    intrinsics.set_carrier(&carrier)
    push_context boot from runtime.MINIMAL_CONTEXT {/* ... */}
}
```

* `#calling_convention(.c)` passes parameters and results the way the platform's C compilers do.
* `#no_context` leaves out the context parameter, and the prologue stack check, since there may be no carrier block
  yet. Like an interrupt function's body, its body sets up a carrier block and pushes a context before calling
  anything that needs them (see [control_flow.md](control_flow.md#functions-without-a-context)). It's part of the
  function's type, and can also follow a signature, like `#never_returns` (`fn(info: ptr[MpInfo]) #no_context`).
* Nothing more is needed when the caller gets the function's address, like a bootloader's table of CPUs. Something
  that finds it by name, like a linker or C code, needs it `#export`ed; the program's entry function is, without saying.

`#no_context` works with Hemera's own convention too, for Hemera code that runs before there's a carrier block.

A `.c` function without `#no_context` is a callback from foreign code, which gets the entry shim described in
[Calls to Foreign Code](#calls-to-foreign-code) to find its carrier and context (Windows x64, and Linux x86-64 linking C, so far).

## Other Conventions

### cdecl
Used for calling functions in C.

When calling a function:
* Push parameters onto the stack, from right to left
* Push one byte after EIP (instruction pointer) (well, one after the call instruction) onto the stack, then call the function
* Push the current EBP (base pointer) (the previous functions base) onto the stack, update EBP to the current ESP (stack pointer).
* Save CPU registers we want to keep to the stack
* Allocate space for local variables if they are required.

Then the function executes.

An example stack frame might look like this:

| Location  | Value                     |
|-----------|---------------------------|
| %ebp + 16 | third function parameter  |
| %ebp + 12 | second function parameter |
| %ebp + 8  | first function parameter  |
| %ebp + 4  | old EIP                   |
| %ebp      | old EBP                   |
| %ebp - 4  | first saved register      |
| %ebp - 8  | second saved register     |
| %ebp - 12 | first local variable      |
| %ebp - 16 | second local variable     |
| %ebp - 20 | third local variable      |

Then returning:
* Reset space allocated for local storage by updating the stack pointer
* Restore saved registers, in exactly reverse order they were pushed to the stack
* Restore the old base pointer
* Return from the function by popping EIP from the stack and jumping there, also updating the stack pointer
* Clean up pushed parameters (the caller does this)

### stdcall
Specified by Microsoft, used for Windows calls.

Every function has a hard-coded set of parameters that cannot vary from call to call (like variadic functions).
The fixed-sized block of parameters is cleaned up by the callee (as opposed to the caller in cdecl).

### fastcall
Attempts to fit values into registers, but behavior depends on the compiler.
