# Packages

A package is a collection of Hemera source code files in a folder. All of these files will have a (the same) package statement, providing the official name
of the package.

The package statement is required to standardize the character sets and name scheme, since directory names would be problematic due to things like
symlinks, case-insensitivity, or problematic characters in the folder name.

## Imports

Files import other packages using the `import` keyword.

They may (and usually do) have a pre-specified `from` part, specifying where the package is from, in the format `from "name"`.
These can be left off for `base` and `std`.

The built in locations are:

* `base` - Part of the language itself, which must be implemented by all compilers
* `std` - The standard library
* `user` - User supplied packages, like anything downloaded by the package manager
* `vendor` - Officially supported bindings and ports for third party libraries

Below are a few examples of imports

```
// Imports are relative to the current file if no prefix is specified
import foo from "../neighbor"
import bar from "bar_v1"
import builtin from "base"
import io // from "std"
import test from "std"
// You can give packages an alias
import pandas as pd from "user"
import vulkan as vk from "vendor"
```

If, for some reason, trying to import from a folder in the local folder with a name exactly the same as a built-in location,
a relative path is used: `import example from "./base"`.

### Circular Imports

Circular imports are fine. Imports indicate to the compiler what the file needs included to work, and allows
you to give the imports names. They do not work like C/C++ imports, and if something has already been imported
somewhere in the program, importing again does not do any meaningful amount of work.

We build everything in one big module, sort of like a "unity build" in the C world, but with
a wildly less-linear build process. A C unity build basically uses a preprocessor to drag all the text
into a single translation unit and that's processed top-down, whereas Hemera has a directed
graph of compilation-related work that needs to happen that it processes in parallel.

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

import library1 from "user"
import library2 as lib2 from "user"

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

## Package Info

Information about a package as a whole goes in a file named `package_info.hsc` in the package's folder, following Java's `package-info.java`.
It holds the package's documentation, as a comment above the package statement, and package-wide constants like `PACKAGE_TIER`.
Every `std` package has one, and other packages are encouraged to do the same.

```
/*
 * Atomic operations on integers, built on the interlocked intrinsics in base.
 */
package atomic

import tiers from "std"

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
| `Freestanding` | Nothing but `base` | `atomic`, `concurrency`, `reflection`, `tiers` |
| `Allocating` | An `Allocator` in `context` | `formatting`, `memory`, `string` |
| `Os` | System calls | `fiber`, `io`, `logger`, `os`, `time` |

A package's tier is the highest any of its files needs, and it's declared in the package's `package_info.hsc`
(see [Package Info](#package-info)).
