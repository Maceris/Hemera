package compiler

/*
 * Owned types (docs/memory.md, Owned Types): each value of an #owned type has one owner, which
 * releases it or moves it on, and the compiler checks every path does. These are how a type's own
 * functions make and end owners outside those rules, and how general code releases one.
 */

// Ends an owner without anything happening: nothing releases what it owned.
forget :: fn[T](value: T) {
}

// A second owner of the same value, without its type knowing: for a type's own share function.
duplicate :: fn[T](value: ptr[T]) -> T {
    return value^
}

// What place owns, leaving it empty: zero, which owns nothing.
take :: fn[T](place: ptr[mut T]) -> T {
    value :: place^
    empty : T
    place^ = empty
    return value
}

// Releases value with the function its type names in #owned(...).
release : fn[T](value: T) : ---
