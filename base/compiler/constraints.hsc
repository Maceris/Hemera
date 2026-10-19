package compiler

/*
 * Constraints on generics (docs/types.md, Constraints): what a generic needs from its parameters,
 * written as #constraint functions of requirements, and named where the generic is declared:
 *
 *     array_find :: fn[T: compiler.Equatable](array: T[], value: T) -> usize?
 *     RingBuffer :: struct[T, capacity: usize] where compiler.PowerOfTwo(capacity) {...}
 *
 * Each is checked at compile time where an instance is made. A requirement that isn't met says
 * why, and checking goes on, so one error gives everything that's missing.
 */

/*
 * Requirements, only for #constraint functions. Each one is met, or adds why it isn't to what the
 * constraint found.
 */

// == and != work on T: numbers, characters, booleans, enums, pointers, strings, functions and types.
require_equality : fn(T: type) : ---

// <, <=, > and >= work on T: numbers and characters.
require_ordering : fn(T: type) : ---

// T is an integer, signed or unsigned.
require_integer : fn(T: type) : ---
require_signed : fn(T: type) : ---
require_unsigned : fn(T: type) : ---

// T is a float.
require_float : fn(T: type) : ---

// T is a number: an integer or a float.
require_numeric : fn(T: type) : ---

// T is a struct with a field called name, of field_type, or a view or array, whose count is a usize.
require_field : fn(T: type, name: string, field_type: type) : ---

// T is an array, view or dynamic array of element: it can be gone through with for, indexed, and has a count.
require_view : fn(T: type, element: type) : ---

// T was given with mut, like SharedPtr[mut Buffer], so ptr[T] can change what it points to.
require_mutable : fn(T: type) : ---

/*
 * condition holds, or the constraint isn't met, saying format_string with each % filled in, like a
 * log message: for anything the others don't cover, like a value parameter's range.
 */
require : fn(condition: bool, format_string: string, params: any...) : ---

/*
 * At least one of its alternatives, each a constraint called with its arguments, is met:
 *
 *     require_any(Integer(T), Float(T))
 *
 * If none is, the reason says why for each. Every alternative is checked, since constraints
 * only find things out.
 */
require_any : fn() : ---

// More about the last requirement that wasn't met, like what to do about it.
note : fn(format_string: string, params: any...) : ---

/*
 * The constraints most generics need.
 */

// Values of T can be compared with == and !=.
Equatable #constraint :: fn(T: type) {
    require_equality(T)
}

// Values of T have an order: <, <=, >, >=, ==.
Ordered #constraint :: fn(T: type) {
    require_equality(T)
    require_ordering(T)
}

Integer #constraint :: fn(T: type) {
    require_integer(T)
}

Float #constraint :: fn(T: type) {
    require_float(T)
}

// An integer or a float.
Numeric #constraint :: fn(T: type) {
    require_numeric(T)
}

// Given with mut: what a ptr[T] points to can be changed.
Mutable #constraint :: fn(T: type) {
    require_mutable(T)
}

// An array, view or dynamic array of E.
ViewOf #constraint :: fn(C: type, E: type) {
    require_view(C, E)
}

// A count or capacity that holds something.
AtLeastOne #constraint :: fn(count: usize) {
    require(count > 0, "% holds nothing; it needs to be at least 1", count)
}

// A capacity that's a power of two, like a ring buffer's, so wrapping is a mask.
PowerOfTwo #constraint :: fn(count: usize) {
    require(count > 0 && count & (count - 1) == 0, "% isn't a power of two", count)
}

/*
 * Whether constraints are satisfied, given as a constraint expression, like
 * compiler.satisfies(Hashable(Point) && Ordered(Point)): a constant, worked out where the checker
 * works out constants, like #if and #assert, without reporting anything. In a generic, with its
 * parameters, so each instance can choose:
 *
 *     #if compiler.satisfies(Integer(T)) { ... }
 */
satisfies : fn() -> bool : ---
