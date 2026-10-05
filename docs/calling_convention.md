# Calling Convention


## Our Convention
Passes an implicit context pointer on every call.
The callee pops its own arguments.
Every function keeps a base pointer, so the chain of saved base pointers always links every frame to its caller's
(`morestack` and resuming fibers both rely on it).

### Carrier Register

One register always holds a pointer to the current thread's carrier block (see [multitasking.md](multitasking.md#carriers)):

| Architecture | Register |
|--------------|----------|
| x86-64       | `r14`    |
| AArch64      | `x28`    |

The register allocator never uses it, functions never save or restore it, and fiber switches leave it alone.
It is callee-saved in the platform conventions, so foreign code preserves it too.
It is only loaded from the OS's thread-local storage when a thread starts, and when foreign code calls into Hemera.

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

Frames never move once they are created, including on fibers, so return values that don't fit in registers are
written through plain pointers that the caller passes along with the stack parameters.

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
| `0x1F28` | BP+8    | `.loop_return`                | Pushed by the loop's `call`. `0xCB1C` is in `reentered_return`              |
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

### Prologue Stack Check

Every function checks that it has room on the current stack segment before it builds its frame,
comparing against `stack_limit` in the carrier block:

```
; Frames up to STACK_SMALL bytes
foo:
    cmp     rsp, [r14 + CARRIER_STACK_LIMIT]
    jbe     .grow
.body:
    push    rbp
    mov     rbp, rsp
    ; ...

; Larger frames, FRAME is the frame size plus the largest outgoing argument area
bar:
    lea     r11, [rsp - FRAME]
    cmp     r11, [r14 + CARRIER_STACK_LIMIT]
    jbe     .grow
.body:
    ; ...
```

`stack_limit` is `STACK_GUARD` (256) bytes above the real end of the segment.
That leaves room for a checked function with a small frame to call a leaf function, and for that leaf function
to call `morestack`, without going past the end:

* Leaf functions (they don't call anything) whose frame and return address fit in `STACK_SMALL` (128) bytes don't check at all.
* Functions with frames up to `STACK_SMALL` bytes compare the stack pointer directly.
* Larger functions compare where their frame will end.

The check costs a load, a compare and a predicted branch. On plain threads `stack_limit` is the thread stack's
limit, so the same check catches stack overflow there.

### Growing the Stack: morestack

`.grow` is out of line, at the end of the function, so the normal path falls straight through:

```
.grow:
    push    rbp                  ; a minimal frame, so this function has its own link in the base pointer chain
    mov     rbp, rsp
    mov     r11d, NEEDED         ; FRAME, plus room for the stack parameters below
    mov     r10d, PARAM_BYTES    ; this function's stack parameters and return value pointers
    lea     rax, [rip + .body]
    call    morestack            ; runs .body on a new segment, returns once it has returned
    pop     rbp
    ret     PARAM_BYTES          ; return to the original caller, popping the original parameters
```

`r10`, `r11` and `rax` stand for scratch registers that aren't used for arguments.

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
    ; take a segment of at least NEEDED + STACK_GUARD bytes: the carrier's spare, its cache, or a new allocation
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

### Calls to Foreign Code

A call to a foreign function goes through a shim that:

1. Increments the carrier's `foreign_depth` and saves the current context pointer in the carrier,
   for any callbacks.
2. If the stack pointer is on a fiber segment, switches to the carrier thread's own stack (just below where the
   scheduler's stack pointer was when it resumed the fiber), copies any stack arguments,
   and sets `stack_limit` to that stack's limit.
3. Calls the function with the platform's convention.
4. Undoes 2 and 1.

Hemera functions that foreign code can call get an entry shim that saves the foreign code's value of the carrier
register, loads it from the OS's thread-local storage (creating a carrier block if this thread has never run
Hemera code), uses the context saved by the shim above (or a default one on a foreign thread), and restores the
register on the way out.

### Suspending and Resuming a Fiber

The state for this lives in the fiber's `FiberResumeState` (`base/runtime/fiber.hsc`):

| Field                          | Meaning                                                                          |
|--------------------------------|----------------------------------------------------------------------------------|
| `saved_sp`                     | Stack pointer after `fiber_suspend` saved the callee-saved registers             |
| `top_frame`                    | Base pointer of the innermost suspended frame                                    |
| `top_continuation`             | Where that frame continues: just after its call to `fiber_suspend`               |
| `reentered_frame`              | The frame most recently re-entered, whose return address slot points at the loop |
| `reentered_return`             | The original contents of that slot (still signed, on AArch64)                    |
| `parent_frame`                 | That frame's caller's base pointer, saved before it could be popped              |
| `stack_segment`, `stack_limit` | The carrier's values for the fiber's current segment                             |

#### Suspending

The scheduler's yield function runs on the fiber's stack, and calls `fiber_suspend` once it has decided to switch:

```
fiber_suspend:
    push    callee-saved registers (never r14)
    fiber.saved_sp         = rsp
    fiber.top_frame        = rbp            ; the caller's frame, fiber_suspend doesn't build one
    fiber.top_continuation = [return address]
    if fiber.reentered_frame:
        [fiber.reentered_frame + 8] = fiber.reentered_return   ; suspended frames always hold real return addresses
        fiber.reentered_frame = null
    fiber.stack_segment, fiber.stack_limit = carrier's values
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
    carrier's stack_segment, stack_limit = fiber's values
    frame = fiber.top_frame,  cont = fiber.top_continuation,  restore_registers = true

reenter_next:
    fiber.reentered_frame  = frame
    fiber.reentered_return = [frame + 8]
    fiber.parent_frame     = [frame]
    rsp = frame + 16                        ; just above the frame's return address slot
    call    fiber_reenter                   ; pushes .loop_return into [frame + 8], and onto the shadow stack

.loop_return:                               ; the frame returned. Return value and callee-saved registers are untouched
    bottom = rsp                            ; the callee popped its parameters, so this is the caller's frame bottom
    cont   = fiber.reentered_return
    frame  = fiber.parent_frame
    restore_registers = false
    jmp     reenter_next

fiber_reenter:                              ; only ever reached by the call above
    rbp = frame
    if restore_registers:
        rsp = fiber.saved_sp
        pop     callee-saved registers, and skip fiber_suspend's return address
    else:
        rsp = bottom
    jmp     cont
```

The loop keeps `frame`, `cont`, `bottom` and `restore_registers` in scratch registers that aren't used for return values.

Re-entering every frame with a `call` means each frame's eventual `ret` pops an address that was really pushed,
both on the stack and on the shadow stack. No return address is ever rewritten by anything but a `call`,
the fiber doesn't need its own shadow stack, and frames never move.

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
* `fiber_suspend` writes `reentered_return` back exactly as it was, still signed, so nothing else needs re-signing.
* Shadow stack entries are dropped with `GCSPOPM` in a loop. (I'm not aware of a bulk equivalent of `INCSSP`.)
* Builds with branch target identification put `bti j` after every call instead of `endbr64`.

#### Walking the Stack

Stack traces aren't recorded as code runs. `intrinsics.capture_stack_trace` builds one when asked, by following
saved base pointers from the current frame and collecting each frame's return address (`[BP + 8]`):

* Across segments, there's nothing special to do: `morestack` and `.grow` build ordinary frames,
  so the chain leads from a function on a new segment back to its caller on the old one.
  Their return addresses are inside `morestack` and `.grow`, and get filtered out of the trace.
* On a running fiber, the outermost re-entered frame's return address is `.loop_return`. When the walk reaches it,
  it continues with the fiber's `reentered_return` as that frame's real return address, and `parent_frame` as the
  next frame. The fiber is found through the carrier block.
* On a suspended fiber (`intrinsics.capture_fiber_stack_trace`), the walk starts at `top_frame`. `fiber_suspend` has
  already put the real return address back, so the chain is ordinary all the way down.
* The walk stops at `fiber_entry` for fibers, and at the thread's entry function for threads.
* On AArch64 with pointer authentication, return addresses are stripped (`XPACI`) before being recorded.

Turning the addresses into function names, files and lines uses the debug information, and only happens when a
trace is printed or reported.

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
