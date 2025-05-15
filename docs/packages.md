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
import foo from "../"
import builtin from "base"
import io // from "std"
import test from "std"
// You can give packages an alias
import pandas from "user" as pd 
import vulkan from "vendor" as vk
```

If, for some reason, trying to import from a folder in the local folder with a name exactly the same as a built-in location,
a relative path is used: `import example from "./base"`.

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
import library2 from "user" as lib2

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

## Structure

* `bin/` - Output from builds, should be ignored by source control
* `docs/` - Documentation related to the package
* `src/` - Source code for the package
* `test/` - Tests for the package
* `user/` - Dependencies, used by package manager
* `LICENSE.txt`
* `NOTICE.txt` - Notices and attributions required by dependencies
* `README.txt` / `README.md` 
