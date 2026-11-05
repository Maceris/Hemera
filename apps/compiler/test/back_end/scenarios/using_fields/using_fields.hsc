/*
 * using on a named field (docs/types.md, Structs): through a pointer, which decides whether what's
 * reached can be changed, through two in a row, and a struct held in place.
 */
package using_fields_test

import runtime from "base"
import testing from "std"

Config :: struct {
    width : int,
    height : int,
}

// Reads and changes through it
Handle :: struct[T] {
    using value : ptr[mut T],
    uses : int,
}

// Only reads through it
View :: struct {
    using config : ptr[Config],
}

// Through two in a row
Outer :: struct {
    using inner : ptr[mut Handle[Config]],
}

Point :: struct {
    x : int,
    y : int,
}

// Named using of a struct held in place
Placed :: struct {
    using at : Point,
    label : string,
}

reaches_fields_through_using #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    config :: runtime.new(Config)
    defer runtime.free(config)
    config.width = 30
    handle := Handle[Config].{value = config, uses = 1}
    handle.height = 12
    view :: View.{config = config}
    outer :: Outer.{inner = &handle}
    placed := Placed.{at = Point.{x = 1, y = 2}, label = "p"}
    placed.y = 5
    testing.expect_eq(t, handle.width + view.height, 42, "both reach the same Config through their pointers, one having changed it")
    testing.expect_eq(t, outer.width, 30, "using through two pointers in a row reaches the Config")
    testing.expect_eq(t, outer.uses, 1, "and the Handle between")
    testing.expect_eq(t, placed.x + placed.y, 6, "a struct held in place is reached, and changed, through using")
    // The field itself, by its name
    testing.expect_eq(t, handle.value.width, 30, "the pointer's field is still reached by its name")
    testing.expect_eq(t, view.config^.height, 12, "a read-only pointer's field too")
    testing.expect_eq(t, placed.at.y, 5, "and the struct held in place's")
    // A field's address through a cast, as kernels reach objects by address
    width :: &cast[ptr[mut Config]](cast[u64](config)).width
    width^ = 12
    testing.expect_eq(t, config.width, 12, "a field's address through a cast from a number is the field's own")
    return .Ok
}
