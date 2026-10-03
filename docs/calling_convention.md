# Calling Convention


## Our Convention
Passes an implicit context pointer on every call.
The callee pops its own arguments.

### Stack Frame

With the stack growing downwards, a stack frame is formatted like this:

                 (higher addresses /\)
|                                                        |                                                |
|--------------------------------------------------------|------------------------------------------------|
| (Previous Stack Frame)                                 |                                                |
|--------------------------------------------------------|------------------------------------------------|
| Offsets to Return Values                               | Written by the caller, but owned by this frame |
| Stack Parameters                                       |                                                |
|-  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  - |                                                |
| Return Address                                         |                                                |
| Base Address of Previous Frame                         | Callers base pointer                           |
|-  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  - |                                                |
| Local Variables                                        |                                                |
| Callee-Saved Registers                                 |                                                |
|-  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  -  - |                                                |
| Size of Frame (u32)                                    | <- This is the stack pointer whenever this     |
| Pase Pointer Offset (u32)                              |    frame calls out to another function         |
|--------------------------------------------------------|------------------------------------------------|
| (Next Stack Frame)                                     | Outgoing arguments go here                     |
                  (lower addresses \/)

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
which is why `bar`'s arguments include 8 bytes of padding.

| Address  | From BP | Value                                              | Notes                                                   |
|----------|---------|----------------------------------------------------|---------------------------------------------------------|
|          |         | (main's Stack Frame)                               | main's BP is `0x2030`                                   |
| `0x2000` |         | ---------------- foo's frame top ----------------- | main's stack pointer when it called foo                 |
| `0x1FE0` | BP+48   | (contents of b, 32 bytes)                          | Stack parameter, written by main                        |
| `0x1FC0` | BP+16   | (contents of a, 32 bytes)                          | Stack parameter, written by main                        |
| `0x1FB8` | BP+8    | `0xAC0A`                                           | Return address, in main right after `call foo`          |
| `0x1FB0` | BP      | `0x2030`                                           | main's BP. foo's BP points here                         |
| `0x1F80` | BP-48   | (space for c, 48 bytes)                            | bar writes its return value here                        |
| `0x1F78` | BP-56   | (space for unimportant, 1 byte + 7 padding)        |                                                         |
| `0x1F70` | BP-64   | (saved rbx)                                        | main's value of rbx                                     |
| `0x1F68` | BP-72   | (saved r12)                                        | main's value of r12                                     |
| `0x1F60` | BP-80   | size = `0xA0` (160), base pointer offset = `0x50`  | foo's frame bottom, foo's stack pointer when it calls bar |
|          |         | ---------------- bar's frame top ----------------- |                                                         |
| `0x1F58` | BP+56   | `-48`                                              | Offset to c, relative to foo's BP (bar's saved BP)      |
| `0x1F50` | BP+48   | (padding)                                          | Keeps the stack pointer 16-byte aligned at `call bar`   |
| `0x1F30` | BP+16   | (contents of d, 32 bytes)                          | Stack parameter, a copy of a written by foo             |
| `0x1F28` | BP+8    | `0xCB1C`                                           | Return address, in foo after `call bar`                 |
| `0x1F20` | BP      | `0x1FB0`                                           | foo's BP. bar's BP points here                          |
| `0x1EF0` | BP-48   | (space for e, 48 bytes)                            |                                                         |
| `0x1EE8` | BP-56   | (saved rbx)                                        | foo's value of rbx                                      |
| `0x1EE0` | BP-64   | size = `0x80` (128), base pointer offset = `0x40`  | bar's frame bottom (frame shown here)                   |

The "From BP" column for each row is relative to the base pointer of the frame that row belongs to.
Nothing inside a frame refers to its own absolute address, so a frame can be copied anywhere and only its saved base pointer
and return address need patching.

When bar runs `return e`:
1. Read the offset at `[BP+56]` (`-48`) and foo's BP at `[BP]` (`0x1FB0`), then copy e from `0x1EF0` to `0x1FB0 - 48 = 0x1F80`, which is c.
2. Restore rbx from `0x1EE8`, then `mov rsp, rbp`, `pop rbp` (BP is `0x1FB0` again), and `ret 48`, which pops bar's 48 bytes of arguments.
3. The stack pointer is now `0x1F60`, foo's frame bottom, exactly where it was before foo started the call.

#### The Same Frames, Thawed Lazily

Say a function called by bar yielded, and the fiber was resumed on a different thread where the scheduler's stack pointer (the fiber's stack top) is `0x5000`.
The innermost frames have already been thawed and returned, so now bar is the outermost frame on the stack, and foo and main are still frozen.
The frozen frames are kept in the heap with the same layout they had on the stack, so foo's frozen copy starts at some heap address `H`, and foo's BP in that copy would be `H + 0x50`.

bar is thawed at `0x5000 - 0x80 = 0x4F80`, so its BP is `0x4F80 + 0x40 = 0x4FC0`:

| Address  | From BP | Value                         | Notes                                                                     |
|----------|---------|-------------------------------|---------------------------------------------------------------------------|
| `0x5000` |         | ---- fiber stack top ----     | Scheduler's frame is above this                                           |
| `0x4FF8` | BP+56   | `-48`                         | Unchanged                                                                 |
| `0x4FF0` | BP+48   | (padding)                     |                                                                           |
| `0x4FD0` | BP+16   | (contents of d)               | Unchanged, the parameters moved with the frame                            |
| `0x4FC8` | BP+8    | `fiber_thaw_trampoline`       | Patched. The real return address `0xCB1C` is kept in the fiber's state    |
| `0x4FC0` | BP      | `H + 0x50`                    | Patched to point at foo's BP inside the frozen heap copy                  |
| `0x4F90` | BP-48   | (e)                           |                                                                           |
| `0x4F88` | BP-56   | (saved rbx)                   | Still foo's value of rbx, callee-saved registers survive the freeze       |
| `0x4F80` | BP-64   | size = `0x80`, BP offset = `0x40` |                                                                       |

When bar runs `return e` this time:
1. It does exactly the same thing as before: `[BP]` is `H + 0x50`, so e is copied to `H + 0x50 - 48 = H + 0x20`, which is c inside foo's frozen copy.
2. `ret 48` lands in `fiber_thaw_trampoline` with the stack pointer at `0x5000`, the fiber's stack top.
3. The trampoline keeps the return registers and callee-saved registers untouched, then thaws foo to `0x5000 - 0xA0 = 0x4F60` (bringing c along with it),
   sets BP to `0x4F60 + 0x50 = 0x4FB0`, patches foo's saved BP to main's BP in the heap copy and foo's return address to itself (keeping `0xAC0A`),
   sets the stack pointer to `0x4F60`, and jumps to `0xCB1C`.
4. foo continues after `call bar` with the stack pointer at its frame bottom, and finds the result in c at `BP-48 = 0x4F80`.

If foo had been the last frozen frame, the trampoline would leave its return address alone, since it already holds the real one.
When the fiber's entry function returns, it returns into the trampoline with nothing left to thaw, which means the fiber is finished.

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
