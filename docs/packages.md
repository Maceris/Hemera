# Packages

A package is a collection of Hemera source code files in a folder. All of these files will have a (the same) package statement, providing the official name
of the package.

The package statement is required to standardize the character sets and name scheme, since directory names would be problematic due to things like
symlinks, case-insensitivity, or problematic characters in the folder name.

A package can't be named `hemera`, which is the prefix of the compiler's own error and warning codes, like
`hemera:E4015` (E4044, [Diagnostics](compilation.md#diagnostics)).

## Imports

Files import other packages using the `import` keyword.

An import is `import name [as alias] [from "location"]`. The location names the package's folder, and the name is the
package's own, as its package statement gives it; the two needn't look alike, since a package's name never has to work
as a folder name. A name that isn't the package's is an error (E4043). To use a package by another name in a file, give
an alias with `as`.

What the location names depends on how it starts:

* **A built-in location and a colon** (`base:`, `std:`, `user:` or `vendor:`), then the package's folder inside it.
  `"std:io"` is `std/io`, and `"std:encoding/json"` is `std/encoding/json`.
* **Anything else** is a folder relative to the importing file's package, like `"../neighbor"` or `"bar_v1"`.
  `"std"` is a folder named `std` beside the importing package, never the standard library.

With no `from`, the package is in std and its folder is its name: `import io` is `import io from "std:io"`.

A location is checked before anything is read, and an invalid one is an error (E4042):

* It can't be empty, hold control characters, or use `\`; folders are always separated with `/`.
* A prefix must be one of the four built-in locations; a relative folder's location has no `:`.
* After a prefix, each folder must be a plain name: not empty, `.` or `..`, and not starting with a space or ending in
  `.` or a space, which Windows drops when opening a path. So a prefixed location can't name a folder outside its
  built-in location.
* The folder a prefixed location finds, after following any links, must still be inside its built-in location. That
  folder, as found, is the one the compiler then reads.

Nothing in a location is expanded: `~`, `%NAME%` and `$NAME` are just characters in a folder name.

The built in locations are:

* `base` - Part of the language itself, which must be implemented by all compilers
* `std` - The standard library
* `user` - User supplied packages, like anything downloaded by the package manager
* `vendor` - Officially supported bindings and ports for third party libraries

Below are a few examples of imports

```
// Without a prefix, a location is relative to this package's folder
import neighbor from "../neighbor"
import bar from "bar_v1"
// A built-in location, then the package's folder inside it
import builtin from "base:builtin"
import testing from "std:testing"
import json from "std:encoding/json"
import x86_64 from "base:intrinsics/x86_64"
// With no location, the package's folder in std
import io
// An alias is the name the package is used by in this file
import pandas as pd from "user:pandas"
import vulkan as vk from "vendor:vulkan"
import neighbor as next_door from "../neighbor"
```

### Circular Imports

Circular imports are fine. Imports indicate to the compiler what the file needs included to work, and allows
you to give the imports names. They do not work like C/C++ imports, and if something has already been imported
somewhere in the program, importing again does not do any meaningful amount of work.

We build everything in one big module, sort of like a "unity build" in the C world, but with
a wildly less-linear build process. A C unity build basically uses a preprocessor to drag all the text
into a single translation unit and that's processed top-down, whereas Hemera has a directed
graph of compilation-related work that needs to happen that it processes in parallel.

Work that needs something not available yet, like a name declared later or a type whose layout isn't known yet, waits
until it is. Declarations can therefore appear in any order, in any file of any package. If the compiler reaches a
point where nothing can make progress, it stops with errors instead of waiting forever:

* Each cycle of work waiting on itself is reported with every step in it, like "`A` needs `B`, which needs `A`".
* Each name that is never declared is reported where it's used.

Only cycles that can't be resolved are errors. Circular imports, mutually recursive functions (a call only needs the
other function's signature), and types that refer to each other through pointers are all fine. A struct containing
itself by value isn't, since its size would depend on itself.

## Name Collision

Since most things like functions and structs are global in the language, there is a risk of name collision when importing other libraries.
Names must be unique within a package, but there are no guarantees when importing other code or when a package gets imported. In 
the case of a collision, the function/struct/etc. will refer to the current package's version if unqualified, and must be qualified
with the other package's name or alias in order to use a different packages version.

This means that if a package gets imported into a project that defines the same function names, it will continue to work without modification.

Here are a few code snippets that demonstrate import prefixes.

```
package library1

foo :: fn(x: int) -> int {
    return x + 1
}
```

```
package library2

foo :: fn(x: int) -> int {
    return x * 2
}

bar :: fn(x: int) -> int {
    /*
     * Does not break when imported by example,
     * always refers to the library2 foo.
     */
    return foo(x) + 5
}
```

```
package example

import library1 from "user:library1"
import library2 as lib2 from "user:library2"

foo :: fn(x: int) -> int {
    return x
}

collision :: fn() {
    foo(5)          // Calls the foo from this package
    /*
     * Since foo is ambiguous, we would have to specify the library
     * even if it was not defined in this package
     */
    library1.foo(5) // Calls library1's foo
    lib2.foo(5)     // Calls library2's foo

    // When there are no conflicts, prefixes are optional
    lib2.bar(5)     // Calls library2's bar
    bar(5)          // Still calls library2's bar
}
```

### Builtins

The names in `base/builtin` (`int`, `string`, `Result`, `size_of`, ...) follow the same rules, as if every file imported them.
A package can declare a name a builtin already has, and its own is then the one used unqualified. The builtin is still
reachable with the `base` prefix, like `base.Result`. If an imported package declares a builtin's name and the current
package doesn't, the unqualified name is ambiguous, like any name declared by two imports.

```
package example

Result :: struct {
    code: int,
}

mine :: fn() -> Result {}                      // This package's Result
builtin :: fn() -> base.Result[int, string] {} // The builtin one
```

### Names and `#if`

A top-level `#if` can declare names and import packages, so until it's decided, what a package declares and what a
file imports aren't fully known. A name only waits for the `#if` chains (an `#if` with its `#else_if`s and `#else`)
that could change what it refers to:

* An undecided `#if` anywhere in the package with a branch declaring the name, since the package's own declaration
  would win.
* An undecided `#if` in the same file with a branch importing a package, when the name isn't found otherwise. What
  that package declares isn't known until it's loaded, and it's only loaded if that branch is picked.

A name found while an `#if` in its file may still add an import is used, and checked again once every `#if` is decided:
if a new import declares it too, it's ambiguous, as above, and compilation stops.

`#if` conditions follow the same rules, so the chains are decided in whatever order their names need. Here the first
`#if` is decided first, since nothing else can declare or import `BAR`, and the second waits for it, since `BAT` may
come from either of its branches:

```
package example

import foo from "user:foo" // declares BAR

#if BAR {
    import baz from "user:baz" // declares BAT
}
#else {
    BAT :: false
}

#if BAT {
    // ...
}
```

When chains need each other, neither can be decided first, and it's a circular dependency like any other:

```
package example

#if BAR {
    import baz from "user:baz" // declares BAT
}

#if BAT {
    import foo from "user:foo" // declares BAR
}
```

```
example.hsc(3,4): error hemera:E4007: Circular dependency. This #if needs BAR, which the #if on line 7 may import
(import foo, line 8); that #if needs BAT, which this #if may import (import baz, line 4)
```

The same goes for an `#if` whose condition needs a name only its own branches declare, like `#if FLAG { FLAG :: true }`.

## Package Info

Information about a package as a whole goes in a file named `package_info.hsc` in the package's folder, following Java's `package-info.java`.
It holds the package's documentation, as a comment above the package statement, and package-wide constants like `PACKAGE_TIER`.
Every `std` package has one, and other packages are encouraged to do the same.

```
/*
 * Atomic operations on integers, built on the interlocked intrinsics in base.
 */
package atomic

import tiers from "std:tiers"

PACKAGE_TIER :: tiers.Tier.Freestanding
```

It's an ordinary source file of the package, so its constants can be used unqualified anywhere in the package,
and are found by compile-time code through `PackageInfo.constants`.

## Structure

The following is the standard structure of a package intended to be built/distributed.

* `bin/` - Output from builds, should be ignored by source control
* `docs/` - Documentation related to the package
* `src/` - Source code for the package
* `test/` - Tests for the package
* `user/` - Dependencies, used by package manager
* `LICENSE.txt`
* `NOTICE.txt` - Notices and attributions required by dependencies
* `README.txt` / `README.md`

## Standard Library Tiers

Every `std` package says what it needs from the target with a `PACKAGE_TIER` constant, using `Tier` from the `tiers` package.
A package may only import packages of the same or a lower tier, so code without an operating system (`OS == .None`)
knows which parts of `std` it can use.

| Tier | Needs | Packages |
|---|---|---|
| `Freestanding` | Nothing but `base` | `c_string`, `concurrency`, `containers`, `locale`, `random`, `reflection`, `slop_os`, `text_buffer`, `tiers`, `time`, `unicode` |
| `Allocating` | An `Allocator` in `context` | `maps`, `memory`, `schema`, `strings`, `time_zones` |
| `Os` | System calls | `fiber`, `io`, `logger`, `os` |

A package's tier is the highest any of its files needs, and it's declared in the package's `package_info.hsc`
(see [Package Info](#package-info)).
