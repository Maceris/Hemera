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
4. High Level Intermediate Representation Generation (See the [HLIR page](hlir.md))
5. Compile-Time Execution
6. Optimization
7. Medium Level Intermediate Representation Generation
8. Optimization
9. Executable Generation (backend)

```
File Import --> Parse --> Type Check <--\
    /|\/|\                     |        |
     |  \--------+-------------+        |
     |           |            \|/       |
     |           |     Type Deduction --/
     |          \|/
 Execution <--- HLIR Generation 
                 |
                \|/
            Optimization
                 |
                \|/
           MLIR Generation
                 |
                \|/
            Optimization
                 |
                \|/
        Executable Generation
```