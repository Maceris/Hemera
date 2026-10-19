/*
 * Generics with constraints (docs/types.md, Constraints), derived parameters and generic aliases, used the ways they allow: main returns
 * 42 if they all gave what they should, or the number of the first check that didn't.
 */
package constraints_test

import compiler from "base"
import runtime from "base"
import containers from "std"

HasCount #constraint :: fn(T: type) {
    compiler.require_field(T, "count", usize)
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

scaled :: fn[factor: usize](value: usize) -> usize where compiler.PowerOfTwo(factor) {
    return value * factor
}

// compiler.satisfies: whether constraints hold, as a compile-time bool
#assert compiler.satisfies(compiler.Equatable(int) && compiler.Ordered(f32))
#assert !compiler.satisfies(compiler.Equatable(Counted))

// Each instance chooses its own way
describe :: fn[T](value: T) -> int {
    #if compiler.satisfies(compiler.Integer(T)) {
        return 10
    }
    #else {
        return 20
    }
}

// require_any: any one of them will do
Formattable #constraint :: fn(T: type) {
    compiler.require_any(compiler.Integer(T), compiler.Float(T), Character(T))
}

Character #constraint :: fn(T: type) {
    info :: type_info_of(T)
    compiler.require(info.variant == .CHAR, "% isn't a character", T)
}

width_of :: fn[T: Formattable](value: T) -> usize {
    return size_of(T)
}

// Derived parameters: worked out from the others, unless they're given
element_of :: fn(C: type) -> type {
    info :: type_info_of(C)
    if info.variant == .ARRAY {
        return bit_cast[type](cast[ptr[compiler.TypeInfoArray]](info).base_type)
    }
    return u8
}

// The total is the elements' type, unless it's given, like a u64 for bytes
sum :: fn[C, E = element_of(C), Total = E](values: C) -> Total where compiler.ViewOf(C, E) && compiler.Numeric(E) && compiler.Numeric(Total) {
    total : Total = 0
    for value in values {
        total += cast[Total](value)
    }
    return total
}

bits_of :: fn[T, bits = size_of(T) * 8](value: T) -> usize {
    return bits
}

Linked :: struct[A, B = ptr[A]] {
    value : A,
    pointer : B?,
}

// Generic aliases: one parameter fixed, one left; a rule of their own; and a distinct one
Pair :: struct[A, B] {
    first : A,
    second : B,
}

Named :: alias[V] Pair[string, V]

SmallRing :: alias[T, capacity: usize] containers.RingBuffer[T, capacity] where Small(capacity)

Small #constraint :: fn(capacity: usize) {
    compiler.require(capacity <= 64, "% is more than a SmallRing holds", capacity)
}

Twin :: distinct alias[T] Pair[T, T]

second_of :: fn(pair: Pair[string, int]) -> int {
    return pair.second
}

main :: fn() -> int {
    if largest(3, 9) != 9 || largest(2.5, 1.5) != 2.5 || largest(cast[u8](200), cast[u8](7)) != 200 {
        return 1
    }
    if count_of(Counted.{count = 5}) != 5 || scaled[8](3) != 24 {
        return 2
    }
    // std's constrained containers and base's array_find
    ring : containers.RingBuffer[int, 4]
    if !containers.ring_push(&ring, 11) {
        return 3
    }
    numbers : int[..]
    runtime.array_add(&numbers, 4)
    runtime.array_add(&numbers, 8)
    match runtime.array_find(numbers, 8) {
        case Some(index) => {
            if index != 1 {
                return 4
            }
        }
        case None => return 4
    }
    runtime.array_free(&numbers)
    if describe(3) != 10 || describe(2.5) != 20 || describe(Counted.{count = 1}) != 20 {
        return 5
    }
    if width_of(cast[u16](1)) != 2 || width_of('c') != size_of(char) || width_of(1.5) != 8 {
        return 6
    }
    bytes : u8[2]
    bytes[0] = 200
    bytes[1] = 100
    view : u8[] = bytes
    // Given instead of derived, a u64 total doesn't wrap
    if sum(view) != 44 || sum[u8[], u8, u64](view) != 300 || bits_of(cast[u16](1)) != 16 {
        return 7
    }
    linked : Linked[int]
    if linked.pointer != null {
        return 8
    }
    named : Named[int]
    named.first = "answer"
    named.second = 42
    small : SmallRing[u8, 16]
    twin : Twin[int]
    twin.first = 1
    if second_of(named) != 42 || !containers.ring_push(&small, 7) || twin.first != 1 {
        return 9
    }
    return 42
}
