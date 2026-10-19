package checked_bodies_unpromised

import compiler from "base"

/*
 * Constrained generics whose bodies use what their constraints don't promise (docs/types.md, Checked
 * Bodies): each reported once, where it's used, even though nothing calls them.
 */

total :: fn[T: compiler.Equatable](a: T, b: T) -> T {
    return a + b
}

smaller :: fn[T: compiler.Equatable](a: T, b: T) -> bool {
    return a < b
}

Number #constraint :: fn(T: type) {
    compiler.require_any(compiler.Integer(T), compiler.Float(T))
}

odd :: fn[T: Number](value: T) -> bool {
    return value % 2 == 1
}

Named #constraint :: fn(T: type) {
    compiler.require_field(T, "name", string)
}

count_of :: fn[T: Named](value: T) -> usize {
    return value.count
}

each :: fn[C: compiler.Equatable](values: C) -> int {
    for value in values {
    }
    return 0
}

largest :: fn[T: compiler.Ordered && (compiler.Integer || compiler.Float)](a: T, b: T) -> T {
    return if a > b { a } else { b }
}

pick :: fn[T: compiler.Ordered](a: T, b: T) -> T {
    return largest(a, b)
}

scaled :: fn[factor: usize](value: usize) -> usize where compiler.PowerOfTwo(factor) {
    return value * factor
}

other :: fn[factor: usize](value: usize) -> usize where compiler.AtLeastOne(factor) {
    return scaled[factor](value)
}

// Writing through a ptr[T] needs T given with mut
overwrite :: fn[T: compiler.Equatable](at: ptr[T], value: T) {
    at^ = value
}

main :: fn() {
}
