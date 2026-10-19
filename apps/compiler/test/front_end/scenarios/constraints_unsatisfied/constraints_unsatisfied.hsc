package constraints_unsatisfied

import compiler from "base"

HasCount #constraint :: fn(T: type) {
    compiler.require_field(T, "count", usize)
    compiler.note("give % a count: usize", T)
}

count_of :: fn[T: HasCount](value: T) -> usize {
    return value.count
}

largest :: fn[T: compiler.Ordered && (compiler.Integer || compiler.Float)](a: T, b: T) -> T {
    return if a > b { a } else { b }
}

Buffer :: struct[T: compiler.Equatable, capacity: usize] where compiler.AtLeastOne(capacity) && compiler.PowerOfTwo(capacity) {
    items : T[capacity],
}

Point :: struct {
    x : int,
}

main :: fn() {
    // Each one: why, from the constraint that isn't satisfied
    _ = count_of(Point.{x = 1})
    _ = largest('a', 'b')
    zero : Buffer[int, 0]
    six : Buffer[int, 6]
    points : Buffer[Point, 4]
}

// A number formatting can write: an integer, a float, or a character
Formattable #constraint :: fn(T: type) {
    compiler.require_any(compiler.Integer(T), compiler.Float(T), Character(T))
}

Character #constraint :: fn(T: type) {
    info :: type_info_of(T)
    compiler.require(info.variant == .CHAR, "% isn't a character", T)
}

show :: fn[T: Formattable](value: T) -> int {
    return 1
}

// A generic alias with a rule of its own
SmallBuffer :: alias[T, capacity: usize] Buffer[T, capacity] where Small(capacity)

Small #constraint :: fn(capacity: usize) {
    compiler.require(capacity <= 64, "% is more than a SmallBuffer holds", capacity)
}

more :: fn() {
    _ = show(Point.{x = 1})
    big : SmallBuffer[int, 128]
}
