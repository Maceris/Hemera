# Keywords

Keywords come in three kinds, from always reserved to only special in one place.

## Reserved Keywords

These start an expression, a statement or a type, so they can't be the name of a variable,
parameter, constant, function or type:

* `auto_cast` - Automatically converts the value to the necessary type, if possible
* `bit_cast` - Does a bit cast conversion between types
* `break` - For breaking out of loops
* `case` - For switch cases
* `cast` - Converts a value to a compatible type
* `continue` - For continuing with loops
* `defer` - Used to defer statements until the end of scope
* `distinct` - For type aliases that are treated as distinct
* `else` - For conditional statements
* `enum` - For defining enums
* `false` - The false boolean value
* `fn` - For defining functions
* `for` - For "for" loops
* `if` - For conditional statements
* `compute` - A block that gives a value with give (see [control_flow.md](control_flow.md#compute-blocks))
* `give` - Gives a compute block its value, leaving it
* `is_error` - Checks if a result holds an error
* `is_none` - Checks if an optional is missing a value
* `is_ok` - Checks if a result holds a value
* `is_some` - Checks if an optional has a value
* `loop` - For creating a loop
* `match` - For pattern matching
* `mut` - For mutable values
* `null` - The null pointer value
* `or_break` - Breaks if an optional is not present, otherwise evaluates to the value
* `or_continue` - Continues if an optional is not present, otherwise evaluates to the value
* `or_else` - Evaluates to an optionals value if present, or the provided default if not
* `or_return` - Evaluates to an optionals value if present, or returns a default value if not
* `push_context` - For using a different context within a scope
* `return` - For returning a value from a function
* `struct` - For defining data structures
* `switch` - For switch statements
* `true` - The true boolean value
* `union` - For defining tagged unions
* `using` - For including fields into scope
* `void` - Indicates a lack of return values
* `while` - For specifying a condition in loops
* `with` - For specifying resources for loops

## Contextual Keywords

These are keywords only where they start their construct, and ordinary names everywhere else, so a
parameter can be called `from` and a field `package`:

* `alias` - For type aliasing, at the start of a declaration's value or after `distinct`
* `all` - After `break`, to exit out of all loops
* `as` - In an import, for giving the package another name
* `from` - In an import, for where the package is, and in `push_context name from value`
* `import` - At the top level of a file, for importing other packages
* `in` - In a `for` loop, after the names of the values
* `package` - The first statement of a file, for defining the package

```
import arch from "../arch"     // import, from: keywords

copy :: fn(from: ptr[u8], to: ptr[mut u8], count: usize) {/* ... */}  // from: a parameter

for value in values {/* ... */}  // in: a keyword
in := 0                          // in: a variable
```

A declaration's value starting with `alias` followed by a type is always an alias, so a constant
whose value is just a variable called `alias` reads as an alias of the type after it.

## Names of Members

Where only a name can go, any word is a name, reserved keywords included: after a `.`, a struct's
field names, named arguments and named fields in a literal (`name = value`), an enum's members and a
union's variants.

```
ImportInfo :: struct {
    alias : string,
    from : string,
}

Direction :: enum {
    in,
    out,
}

mode := direction.in
info := ImportInfo.{alias = "arch", from = "../arch"}
```

## Builtin Names

`context`, and the names of builtin types like `int`, `string`, `any` and `type`, aren't keywords:
they're names declared by the language, like any other. A declaration with the same name hides the
builtin one in its scope, so a parameter called `type` can't be used as the type `type` in its
function.
