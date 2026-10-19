/*
 * Generic arguments given with mut (docs/types.md, Mutability in Type Arguments): ptr[T] can change
 * what it points to, mut passes on to the generics it uses, constraints can ask for it, and an
 * instance given mut becomes a read-only one. main returns 42 if each worked, or the number of the
 * first check that didn't.
 */
package mut_arguments_test

import compiler from "base"

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

main :: fn() -> int {
    number := 1
    changeable := Box[mut int].{value = &number, uses = 2}
    changeable.value^ = 10
    set(changeable, 20)
    set_checked(changeable, 30)
    if number != 30 {
        return 1
    }
    poke[mut int](&number, 35)
    if number != 35 {
        return 3
    }
    outer := Outer[mut int].{inner = changeable}
    outer.inner.value^ = 40
    // Read-only, from the changeable one
    read_only : Box[int] = changeable
    if read(changeable) != 42 || read_only.value^ != 40 || number != 40 {
        return 2
    }
    return 42
}
