# Calling Convention


## Our Convention
Passes an implicit context pointer on every call.


### Stack Frame

(WIP, lazy loading of stack frames for Fibers complicate things greatly)

[//]: # (TODO make it make sense)

With the stack growing downwards, a stack frame is formatted like this:

|                                                        |
|--------------------------------------------------------|
| (Previous Stack Frame)                                 |
|--------------------------------------------------------|
| Return Address                                         |
| Base Address of Previous Frame                         |
| Offsets to Return Values (that don't fit in registers) |
| Parameters (that don't fit in registers)               |
| Local Variables                                        |
| Saved Registers                                        |
| Size of Frame                                          |
|--------------------------------------------------------|
| (Next Stack Frame)                                     |

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

| Values                      | Notes                      |
|-----------------------------|----------------------------|
| (main's Stack Frame)        |                            |
|-----------------------------|----------------------------|
| 0xABCD                      | Frame starts at 0x1234     |
| (main's frame address)      |                            |
| (contents of a)             | Provided by caller         |
| (contents of b)             | Provided by caller         |
| (space for unimportant)     |                            |
| (space for c)               |                            |
| (dumped registers)          |                            |
| (size of this frame)        |                            |
|-----------------------------|----------------------------|
| 0xCAFE                      |                            |
| 0x1234                      |                            |
| 50                          | Offset to c in last frame  |
| (contents of d)             | Provided by caller         |
| (space for e)               |                            |


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
