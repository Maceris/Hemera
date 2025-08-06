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

### stdcall
Specified by Microsoft, used for Windows calls.

### fastcall
Attempts to fit values into registers, but behavior depends on the compiler.
