/*
 * Generic arguments given with mut (docs/types.md, Mutability in Type Arguments): ptr[T] can change
 * what it points to, mut passes on to the generics it uses, constraints can ask for it, and an
 * instance given mut becomes a read-only one.
 */
package mut_arguments_test

import compiler from "base"
import testing from "std"

Box :: struct[T] {
    value : ptr[T],
    uses : int,
}

Outer :: struct[T] {
    inner : Box[T],
}

// A template: it writes when its instance was given mut
set :: fn[T](box: Box[T], to: T) {
    box.value^ = to
}

// Checked: it's promised it can write
set_checked :: fn[T: compiler.Mutable](box: Box[T], to: T) {
    box.value^ = to
}

// Given mut where it's called: poke[mut int](...)
poke :: fn[T](at: ptr[T], value: T) {
    at^ = value
}

read :: fn(box: Box[int]) -> int {
    return box.value^ + box.uses
}

// mut written in an expression, like a constraint's argument
#assert compiler.satisfies(compiler.Mutable(mut int)) && !compiler.satisfies(compiler.Mutable(int))

writes_through_instances_given_mut #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    number := 1
    changeable := Box[mut int].{value = &number, uses = 2}
    changeable.value^ = 10
    testing.expect_eq(t, number, 10, "Box[mut int]'s ptr[T] is a ptr[mut int], written through")
    set(changeable, 20)
    testing.expect_eq(t, number, 20, "a template given Box[mut int] writes through its pointer")
    set_checked(changeable, 30)
    testing.expect_eq(t, number, 30, "so does one constrained to a Mutable T")
    poke[mut int](&number, 35)
    testing.expect_eq(t, number, 35, "mut given where the function's called")
    outer := Outer[mut int].{inner = changeable}
    outer.inner.value^ = 40
    testing.expect_eq(t, number, 40, "mut passes on to the generic types an instance uses")
    return .Ok
}

reads_through_instances_made_read_only #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    number := 40
    changeable := Box[mut int].{value = &number, uses = 2}
    // Read-only, from the changeable one
    read_only : Box[int] = changeable
    testing.expect_eq(t, read(changeable), 42, "a Box[mut int] is given where a Box[int] is taken, 40 + 2")
    testing.expect_eq(t, read_only.value^, 40, "a read-only Box made from it reads the same int")
    return .Ok
}
