/*
 * Generics with constraints (docs/types.md, Constraints), derived parameters and generic aliases, used the ways they
 * allow.
 */
package constraints_test

import compiler from "base"
import runtime from "base"
import containers from "std"
import testing from "std"

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

calls_constrained_generics #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, largest(3, 9), 9, "ints are Ordered Integers")
    testing.expect_eq(t, largest(2.5, 1.5), 2.5, "floats are Ordered Floats")
    testing.expect_eq(t, largest(cast[u8](200), cast[u8](7)), 200, "u8s compare unsigned")
    testing.expect_eq(t, count_of(Counted.{count = 5}), 5, "a struct with a usize count is HasCount")
    testing.expect_eq(t, scaled[8](3), 24, "8 is a power of two, so the where clause holds")
    return .Ok
}

uses_constrained_containers #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // std's constrained containers and base's array_find
    ring : containers.RingBuffer[int, 4]
    testing.expect(t, containers.ring_push(&ring, 11), "an empty ring of four has room")
    numbers : int[..]
    defer runtime.array_free(&numbers)
    runtime.array_add(&numbers, 4)
    runtime.array_add(&numbers, 8)
    found :: runtime.array_find(numbers, 8)
    testing.expect_eq(t, found, cast[usize?](1), "8 was added second")
    return .Ok
}

chooses_by_what_holds #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, describe(3), 10, "an int's instance takes the Integer branch")
    testing.expect_eq(t, describe(2.5), 20, "a float's takes the other")
    testing.expect_eq(t, describe(Counted.{count = 1}), 20, "so does a struct's")
    testing.expect_eq(t, width_of(cast[u16](1)), 2, "a u16 is an Integer, one of require_any's")
    testing.expect_eq(t, width_of('c'), size_of(char), "a char is a Character, another")
    testing.expect_eq(t, width_of(1.5), 8, "an untyped float is an f64, a Float")
    return .Ok
}

derives_parameters #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    bytes : u8[2]
    bytes[0] = 200
    bytes[1] = 100
    view : u8[] = bytes
    testing.expect_eq(t, sum(view), 44, "the total is derived as the elements' u8, so 300 wraps to 44")
    // Given instead of derived, a u64 total doesn't wrap
    testing.expect_eq(t, sum[u8[], u8, u64](view), 300, "given a u64 total, it doesn't wrap")
    testing.expect_eq(t, bits_of(cast[u16](1)), 16, "bits is derived from the type's size")
    linked : Linked[int]
    testing.expect(t, linked.pointer == null, "B is derived as ptr[int], and a zeroed optional is empty")
    return .Ok
}

uses_generic_aliases #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    named : Named[int]
    named.first = "answer"
    named.second = 42
    testing.expect_eq(t, second_of(named), 42, "Named[int] is Pair[string, int] itself")
    small : SmallRing[u8, 16]
    testing.expect(t, containers.ring_push(&small, 7), "16 is small enough for a SmallRing, which is a RingBuffer")
    twin : Twin[int]
    twin.first = 1
    testing.expect_eq(t, twin.first, 1, "a distinct alias keeps Pair's fields")
    return .Ok
}
