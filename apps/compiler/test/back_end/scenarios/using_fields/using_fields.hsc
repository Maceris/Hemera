/*
 * using on a named field (docs/types.md, Structs): through a pointer, which decides whether what's
 * reached can be changed, through two in a row, and a struct held in place. main returns 42 if each
 * worked, or the number of the first check that didn't.
 */
package using_fields_test

import runtime from "base"

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

main :: fn() -> int {
    config :: runtime.new(Config)
    config.width = 30
    handle := Handle[Config].{value = config, uses = 1}
    handle.height = 12
    view :: View.{config = config}
    outer :: Outer.{inner = &handle}
    placed := Placed.{at = Point.{x = 1, y = 2}, label = "p"}
    placed.y = 5
    if handle.width + view.height != 42 || outer.width != 30 || outer.uses != 1 || placed.x + placed.y != 6 {
        return 1
    }
    // The field itself, by its name
    if handle.value.width != 30 || view.config^.height != 12 || placed.at.y != 5 {
        return 2
    }
    // A field's address through a cast, as kernels reach objects by address
    width :: &cast[ptr[mut Config]](cast[u64](config)).width
    width^ = 12
    if config.width != 12 {
        return 3
    }
    runtime.free(config)
    return 42
}
