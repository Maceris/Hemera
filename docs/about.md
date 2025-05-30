# About

Hemera is:

* Compiled
* Statically typed
* Strongly typed
* Multi-paradigm: procedural, imperative, functional

## Features

* Context system, like [Jai](https://jai.community/) and [Odin](https://odin-lang.org/)
* Compile-time execution of any code
* `defer` statements - defer a statement until the end of scope
* First class functions
* Multiple return values
* Nested functions
* Parametric polymorphism
* Piping output from one function to another, with pattern matching
* Struct Of Array (SOA) data types
* Tagged unions, as well as C-style unions
* Variety of primitive types, for example:
    * 128-bit integers
    * endian-specific integer types
    * quaternions
    * relative pointers
    * vectors

## Banned Features

These are common things that do not exist in this language, the lack of which is considered a feature.

* Exceptions
* Header files
* Makefiles
* Methods
* Mutable global variables/state
* Objects (in the Object-Oriented sense)
* Operator overloading
* Prefix/postfix increment and decrement operators (`i++`, `--i`)
* Preprocessor
