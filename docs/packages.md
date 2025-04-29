# Packages

A package is a collection of Hemera source code files in a folder. All of these files will have a (the same) package statement, providing the official name
of the package.

The package statement is required to standardize the character sets and name scheme, since directory names would be problematic due to things like
symlinks, case-insensitivity, or problematic characters in the folder name.

## Name collision

Since most things like functions and structs are global in the langauge, there is a risk of name collision when importing other libraries.
Names must be unique within a package, but there are no guarantees when importing other code or when a package gets imported. In 
the case of a collision, the function/struct/etc. will refer to the current package's verison if unqualified, and must be qualified
with the other package's name or alias in order to use that version.

This means that if a package gets imported into a project that defines the same function names, it will continue to work without modification.

Here are a few code snippits that demonstrate import prefixes.

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
