# Packages

A package is a collection of Hemera source code files in a folder. All of these files will have a (the same) package statement, providing the official name
of the package.

The package statement is required to standardize the character sets and name scheme, since directory names would be problematic due to things like
symlinks, case-insensitivity, or problematic characters in the folder name.

## Imports

Files import other packages using the `import` keyword.

They may (and usually do) have a prefix like `core:`, specifying the type of package. The prefixes are:

* `base` - Part of the language itself, which must be implemented by all compilers
* `std` - The standard library
* `user` - User supplied packages, like anything downloaded by the package manager
* `vendor` - Officially supported bindings and ports for third party libraries

Below are a few examples of imports

```
// Imports are relative to the current file if no prefix is specified
import "../foo"
import "base:builtin"
import "std:io"
import "std:test" // I am not apologizing
// You can give packages an alias
import "user:pandas" as pd 
import "vendor:vulkan"
```

## Name collision

Since most things like functions and structs are global in the language, there is a risk of name collision when importing other libraries.
Names must be unique within a package, but there are no guarantees when importing other code or when a package gets imported. In 
the case of a collision, the function/struct/etc. will refer to the current package's version if unqualified, and must be qualified
with the other package's name or alias in order to use that version.

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
    return x
}
```

```
package example

import "vendor:library1"
import "vendor:library2" as lib2

foo :: fn(x: int) -> int {
    return x
}

collision :: fn() {
    foo(5)          // Calls the foo from this package
    library1.foo(5) // Calls library1's foo
    lib2.foo(5)     // Calls library2's foo

    // When there are no conflicts, prefixes are optional
    lib2.bar(5)     // Calls library2's bar
    bar(5)          // Still calls library2's bar
}
```
