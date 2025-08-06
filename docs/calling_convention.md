# Calling Convention


## Our Convention
Passes an implicit context pointer on every call.

[//]: # (TODO add in information about stack frames relating to fibers)

## Other Conventions

### cdecl
Used for calling functions in C.

### stdcall
Specified by Microsoft, used for Windows calls.

### fastcall
Attempts to fit values into registers, but behavior depends on the compiler.
