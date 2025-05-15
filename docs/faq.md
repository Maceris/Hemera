# Frequently Asked Questions

## What languages inspired this?

* C++ - Hate for build systems, template errors, headers, and macros
* Go - Defer syntax, multiple return values
* Jai - Syntax, lack of exceptions, compile-time execution, allocator/context pattern
* Java - Streams, method references, RxJava, distaste for inheritance and globals
* Odin - Primitive types, library collections, Struct of Arrays (SOA) types
* Rust - Tagged unions, Result and Option types, immutability by default, pattern matching

## Why are they called functions?

Other languages use terms like procedures, methods, subroutines, routines, or subprograms. Some distinguish based on whether they return a value, or whether they are inside a class.

Ultimately function was decided on for two reasons. First, "function" and "function pointer" are familiar terms from C++, which this is intended to replace. Second, "fn" is less typing than "proc", "function", etc.

## Why does Hemera not have feature X?

### Exceptions

Exceptions can be very useful, but they introduce more risk of not being handled. If a Java method throws an unchecked exception without documenting it, the caller might have no idea that exception is possible and fail to handle it.

In order to enforce error handling, there are no thrown exceptions. Error states are handled explicitly. There are other options like Result/Option types and multiple return values, which can be used to return error values in a way that is unambiguous and cannot be ignored.

### Mutable global variables/state

Global variables are somewhat ubiquitous in other programming languages. Java has `public static` variables, C++ has all sorts of variables and macros that can be hanging around in various scopes.

These are used for a variety of things, with common examples being

* Calendar and timezone settings
* Some kind of common caches, like string caches, Java's cache for small Integer objects, or a cached state of the current time
* The state of a global random number generator
* Logging configuration, or the loggers themselves
* Hardware device interaction
* Singletons, like game or graphics driver state

However, they introduce a huge variety of issues with things like

* Concurrency
* Debugging
* Maintainability
* Locality of behavior
* Proving or understanding things about a procedure/method in isolation

The consensus is almost universally "don't use global variables". So instead of suggesting they not be used, they have been removed completely.

More specifically, there are still globally accessible variables, but any global variable must evaluate to a constant value at compile time.

Benefits of this include

* When calling a function, inputs and outputs are apparent from the function signature - there are no secret dependencies
* Memory lifetime and synchronization is more closely tied to allocator lifetimes and scope, thus easier to track and statically check
* Testing is easier, and can be more parallel, because state must be passed in to functions rather than set up globally

The context system handles passing around things like RNG state, logging configuration and allocators. 

### Objects / Methods

To summarize, data and procedures are separate as this better matches the problems this language is intended to solve.

Less concisely, this language is designed with a few biases against Object Oriented Programming, learned from 15 years of experience using Java.

A few hot takes from the creator:

* Inheritance, certainly beyond one level and possibly at all, is harmful. `extends` is evil, though `implements` gets a pass if (and only if) there are multiple implementations.
* Trying to build programs by granularly modeling a real world taxonomy as objects (`Cat extends Animal`) is counterproductive at best, and a nightmare at worst
* Encapsulation is frequently incorrectly used (as terminology), naked getters and setters is neither encapsulating anything nor a good idea
* Encapsulation is usually done at the wrong level, rendering it pointless by forcing details to leak out anyway. Microservices are significantly more OOP than `getX()` is.

### Operator overloading

Operator overloading leads to pain. It means that almost any line of code cannot be trusted to do what it appears to do.

They are frequently cited as needed for math, and some container operations. This language has all sorts of built in mathematical types (vectors, matrices, complex numbers, quaternions) which use operators as one would expect. 

With the math being built in, there are few cases for operator overloading, and it introduces more trouble than it would be worth.

### Prefix/postfix increment and decrement operators (`i++`, `--i`)

These operators add more confusion than they solve when saving one character over something like `i += 1`.

These operators are primarily used in for loops, which have ranged-based alternatives in this language that are even shorter and safer.

## Why am I like this?

Why is winter cold?
