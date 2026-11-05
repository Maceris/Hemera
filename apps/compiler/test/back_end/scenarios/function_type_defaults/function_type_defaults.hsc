/*
 * Defaults in function types (docs/functions.md, Defaults in Function Types): a call through a
 * declaration's name uses the declaration's defaults, with what it inherits from a type it states, and
 * any other call its callee's type's: through a variable, a parameter, a field, an alias, a named
 * function type, and an Allocator's function, whose location is the caller's. A function type's
 * default can be any expression: a call, arithmetic, and names from the package it's written in, which
 * the caller doesn't import (scaled). Run with hemera --test.
 */
package function_type_defaults_test

import runtime from "base"
import scaled from "scaled"
import testing from "std"

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

offset :: fn() -> int {
    return 4
}

// Arithmetic and a call
SumFn :: alias fn(a: int, b: int = SECOND * 3 + offset()) -> int

add :: fn(a: int, b: int) -> int {
    return a + b
}

summed :: fn(f: SumFn) -> int {
    return f(1)
}

multiply :: fn(n: int, by: int) -> int {
    return n * by
}

scale :: fn(f: scaled.ScaleFn) -> int {
    return f(3)
}

// The line of line_of's call through f, below
LINE_OF_CALL : u32 : 74

line_of :: fn(f: (fn(location := #caller_location) -> u32)) -> u32 {
    return f()
}

where :: fn(location := #caller_location) -> u32 {
    return location.line
}

calls_through_a_name_with_the_declarations_defaults #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, foo(1), 2, "foo inherits b = SECOND from the FooFn it states")
    testing.expect_eq(t, same(1), 101, "same repeats FooFn's default, which is allowed")
    testing.expect_eq(t, qux(1), 3, "qux states no type, so its own default, 2, is used")
    // A constant naming a declaration is a call through its name
    f :: qux
    testing.expect_eq(t, f(1), 3, "a constant naming qux calls through its name, with qux's own default")
    return .Ok
}

calls_through_a_value_with_its_types_defaults #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // FooFn's default, whatever the function is
    testing.expect_eq(t, through(qux), 2, "through a FooFn parameter, b is FooFn's SECOND, not qux's 2")
    x : FooFn = qux
    testing.expect_eq(t, x(1), 2, "through a FooFn variable, b is FooFn's SECOND")
    holder := Holder.{qux}
    testing.expect_eq(t, holder.call(1), 2, "through a FooFn field, b is FooFn's SECOND")
    testing.expect_eq(t, named(qux), 11, "through a named function type, b is its 10")
    return .Ok
}

passes_the_callers_location_through_a_value #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, line_of(where), LINE_OF_CALL, "the caller's location is where the call through the value is")
    return .Ok
}

computes_defaults_from_any_expression #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, summed(add), 8, "SumFn's default is arithmetic and a call: 1 + (1 * 3 + 4)")
    testing.expect_eq(t, scale(multiply), 42, "ScaleFn's default uses scaled's own names, which this package doesn't import: 3 * (7 * 2)")
    return .Ok
}

calls_an_allocators_function_with_its_defaults #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    bytes, error :: context.allocator.function(context.allocator.data, 16, 8, null, 0)
    testing.require(t, error == null, "the context's allocator has 16 bytes, called with AllocatorFn's location default")?
    testing.expect_eq(t, bytes.count, 16, "the allocator gives as many bytes as asked for")
    context.allocator.function(context.allocator.data, 0, 8, cast[rawptr](bytes.data), 16)
    return .Ok
}

