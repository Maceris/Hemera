package constraints_ok

import compiler from "base"

// A constraint of this package's own: a struct with a count, named without a package
HasCount #constraint :: fn(T: type) {
    compiler.require_field(T, "count", usize)
    compiler.note("give % a count: usize", T)
}

// A value parameter's range
Small #constraint :: fn(size: usize) {
    compiler.require(size <= 64, "% is more than 64", size)
}

Counted :: struct {
    count : usize,
}

count_of :: fn[T: HasCount](value: T) -> usize {
    return value.count
}

largest :: fn[T: compiler.Ordered && (compiler.Integer || compiler.Float)](a: T, b: T) -> T {
    return if a > b { a } else { b }
}

Buffer :: struct[T: compiler.Equatable, capacity: usize] where compiler.AtLeastOne(capacity) && Small(capacity) {
    items : T[capacity],
}

scaled :: fn[factor: usize](value: usize) -> usize where compiler.PowerOfTwo(factor) {
    return value * factor
}

main :: fn() -> int {
    buffer : Buffer[int, 8]
    floats : Buffer[f64, 64]
    total :: count_of(Counted.{count = 3}) + scaled[4](2)
    return largest(1, 2) + cast[int](largest(1.0, 2.0)) + cast[int](total)
}
