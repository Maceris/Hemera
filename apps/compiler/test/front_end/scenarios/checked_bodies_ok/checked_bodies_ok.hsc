package checked_bodies_ok

import compiler from "base"

/*
 * Constrained generics whose bodies only use what their constraints promise (docs/types.md, Checked
 * Bodies), each checked once with archetypes, whether anything uses it or not.
 */

HasCount #constraint :: fn(T: type) {
    compiler.require_field(T, "count", usize)
}

count_of :: fn[T: HasCount](value: T) -> usize {
    return value.count
}

// Integer || Float promises what both have: arithmetic and ordering
largest :: fn[T: compiler.Ordered && (compiler.Integer || compiler.Float)](a: T, b: T) -> T {
    return if a > b { a } else { b }
}

// require_any promises what all its alternatives have
Number #constraint :: fn(T: type) {
    compiler.require_any(compiler.Integer(T), compiler.Float(T))
}

halved :: fn[T: Number](value: T) -> T {
    return value / 2
}

element_of :: fn(C: type) -> type {
    info :: type_info_of(C)
    if info.variant == .ARRAY {
        return bit_cast[type](cast[ptr[compiler.TypeInfoArray]](info).base_type)
    }
    return u8
}

// A view's elements, by for and by index, with a total of its own type
sum :: fn[C, E = element_of(C), Total = E](values: C) -> Total where compiler.ViewOf(C, E) && compiler.Numeric(E) && compiler.Numeric(Total) {
    total : Total = 0
    for value in values {
        total += cast[Total](value)
    }
    if values.count > 0 {
        total -= cast[Total](values[0]) - cast[Total](values[0])
    }
    return total
}

scaled :: fn[factor: usize](value: usize) -> usize where compiler.PowerOfTwo(factor) {
    return value * factor
}

// Calls with what's promised: the same where clause, a template, and constrained generics
scaled_again :: fn[factor: usize](value: usize) -> usize where compiler.PowerOfTwo(factor) {
    return scaled[factor](value)
}

first_or :: fn[T](values: T[], fallback: T) -> T {
    if values.count > 0 {
        return values[0]
    }
    return fallback
}

biggest :: fn[T: compiler.Ordered && compiler.Integer](values: T[]) -> T {
    best := first_or(values, 0)
    for value in values {
        best = largest(best, value)
    }
    return halved(best + best)
}

// Which way an #if goes is only known at an instance, so it's left to them
parity :: fn[T: compiler.Equatable](value: T) -> int {
    #if compiler.satisfies(compiler.Integer(T)) {
        return cast[int](value % 2)
    }
    #else {
        return 0
    }
}

// So is a type a value parameter sizes
Sized :: struct[T, capacity: usize] {
    items : T[capacity],
}

filled :: fn[T: compiler.Numeric, capacity: usize](value: T) -> T where compiler.AtLeastOne(capacity) {
    sized : Sized[T, capacity]
    sized.items[0] = value
    return sized.items[0]
}

main :: fn() {
    numbers : i32[2]
    view : i32[] = numbers
    _ = biggest(view) + sum(view) + largest(1, 2) + halved(4) + filled[i32, 2](1)
    _ = scaled_again[4](1) + cast[usize](parity(3))
}
