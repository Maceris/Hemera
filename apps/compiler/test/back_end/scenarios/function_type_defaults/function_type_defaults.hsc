/*
 * Defaults in function types (docs/functions.md, Defaults in Function Types): a call through a
 * declaration's name uses the declaration's defaults, with what it inherits from a type it states, and
 * any other call its callee's type's: through a variable, a parameter, a field, an alias, a named
 * function type, and an Allocator's function, whose location is the caller's. main returns 42 if they
 * all worked.
 */
package function_type_defaults_test

import runtime from "base"

SECOND :: 1

FooFn :: alias fn(a: int, b: int = SECOND) -> int
NamedFn :: fn(a: int, b: int = 10) -> int

// Inherits b = SECOND from FooFn
foo : FooFn : fn(a: int, b: int) -> int {
    return a + b
}

// Repeats it, which is allowed
same : FooFn : fn(a: int, b: int = SECOND) -> int {
    return a + b * 100
}

// Its own default, since it doesn't state a type
qux :: fn(a: int, b: int = 2) -> int {
    return a + b
}

Holder :: struct {
    call : FooFn,
}

through :: fn(f: FooFn) -> int {
    return f(1)
}

named :: fn(f: NamedFn) -> int {
    return f(1)
}

line_of :: fn(f: (fn(location := #caller_location) -> u32)) -> u32 {
    return f()
}

where :: fn(location := #caller_location) -> u32 {
    return location.line
}

main :: fn() -> int {
    if foo(1) != 2 || same(1) != 101 {
        return 1
    }
    if qux(1) != 3 {
        return 2
    }
    // Through a parameter, a variable and a field: FooFn's default, whatever the function is
    if through(qux) != 2 {
        return 3
    }
    x : FooFn = qux
    if x(1) != 2 {
        return 4
    }
    holder := Holder.{qux}
    if holder.call(1) != 2 {
        return 5
    }
    if named(qux) != 11 {
        return 6
    }
    // A constant naming a declaration is a call through its name
    f :: qux
    if f(1) != 3 {
        return 7
    }
    // The caller's location is where the call through the value is
    if line_of(where) != 45 {
        return 8
    }
    bytes, error :: context.allocator.function(context.allocator.data, 16, 8, null, 0)
    if error != null || bytes.count != 16 {
        return 9
    }
    context.allocator.function(context.allocator.data, 0, 0, cast[rawptr](bytes.data), 16)
    return 42
}
