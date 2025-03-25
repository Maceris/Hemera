# Compilation

An important note is that we have arbitrary compile-time execution.
This means that it ***is not safe*** to compile untrusted code,
much like it would not be safe to build with untrusted arbitrary makefiles.

If dealing with potentially untrusted code, any IDE that will
automatically compile the code or do something like request that a language server
calculate values should be avoided, or opened in a safe mode which avoids such operations.

## Compilation Stages

1. Lexing
2. Parsing
3. Type Checking
4. Compile-Time Execution
5. Intermediate Language 1 Generation
6. Optimization
7. Intermediate Language 2 Generation
8. Optimization
9. Executable Generation

