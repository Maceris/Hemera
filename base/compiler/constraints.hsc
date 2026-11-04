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

/**
 * Require that == and != work on T: numbers, characters, booleans, enums, pointers, strings, functions and types.
 *
 * @param T The type to check.
 */
require_equality : fn(T: type) : ---

/**
 * Require that <, <=, > and >= work on T: numbers and characters.
 *
 * @param T The type to check.
 */
require_ordering : fn(T: type) : ---

/**
 * Require that T is an integer, signed or unsigned.
 *
 * @param T The type to check.
 */
require_integer : fn(T: type) : ---
/**
 * Require that T is a signed integer.
 *
 * @param T The type to check.
 */
require_signed : fn(T: type) : ---
/**
 * Require that T is an unsigned integer.
 *
 * @param T The type to check.
 */
require_unsigned : fn(T: type) : ---

/**
 * Require that T is a float.
 *
 * @param T The type to check.
 */
require_float : fn(T: type) : ---

/**
 * Require that T is a number: an integer or a float.
 *
 * @param T The type to check.
 */
require_numeric : fn(T: type) : ---

/**
 * Require that T has a field: a struct with a field called name, of field_type, or a view or array, whose count is
 * a usize.
 *
 * @param T The type to check.
 * @param name The field's name, compared exactly.
 * @param field_type The type the field has to be, exactly.
 */
require_field : fn(T: type, name: string, field_type: type) : ---

/**
 * Require that T is an array, view or dynamic array of element: it can be gone through with for, indexed, and has a
 * count.
 *
 * @param T The type to check.
 * @param element The type its elements have to be.
 */
require_view : fn(T: type, element: type) : ---

/**
 * Require that T was given with mut, like SharedPtr[mut Buffer], so ptr[T] can change what it points to.
 *
 * @param T The generic parameter to check, as the generic was given it.
 */
require_mutable : fn(T: type) : ---

/**
 * Require that T isn't #owned, so a value of it can be copied and dropped (docs/memory.md, Owned Types).
 *
 * @param T The type to check.
 */
require_copyable : fn(T: type) : ---

/**
 * Require that condition holds, for anything the others don't cover, like a value parameter's range.
 *
 * @param condition What has to be true, worked out at compile time.
 * @param format_string Why the constraint isn't met when condition is false, with each % filled in, like a log
 *     message.
 * @param params The values for the %s, in order.
 */
require : fn(condition: bool, format_string: string, params: any...) : ---

/**
 * Require that at least one of its alternatives, each a constraint called with its arguments, is met:
 *
 *     require_any(Integer(T), Float(T))
 *
 * If none is, the reason says why for each. Every alternative is checked, since constraints
 * only find things out. The alternatives are given as arguments, though the declaration shows none.
 */
require_any : fn() : ---

/**
 * Say more about the last requirement that wasn't met, like what to do about it.
 *
 * @param format_string The note, with each % filled in, like a log message.
 * @param params The values for the %s, in order.
 */
note : fn(format_string: string, params: any...) : ---

/*
 * The constraints most generics need.
 */

/**
 * Require that values of T can be compared with == and !=.
 *
 * @param T The type to check.
 */
Equatable #constraint :: fn(T: type) {
    require_equality(T)
}

/**
 * Require that values of T have an order: <, <=, >, >=, ==.
 *
 * @param T The type to check.
 */
Ordered #constraint :: fn(T: type) {
    require_equality(T)
    require_ordering(T)
}

/**
 * Require that T is an integer, signed or unsigned.
 *
 * @param T The type to check.
 */
Integer #constraint :: fn(T: type) {
    require_integer(T)
}

/**
 * Require that T is a float.
 *
 * @param T The type to check.
 */
Float #constraint :: fn(T: type) {
    require_float(T)
}

/**
 * Require that T is a number: an integer or a float.
 *
 * @param T The type to check.
 */
Numeric #constraint :: fn(T: type) {
    require_numeric(T)
}

/**
 * Require that T's values can be copied and dropped freely: it isn't #owned.
 *
 * @param T The type to check.
 */
Copyable #constraint :: fn(T: type) {
    require_copyable(T)
}

/**
 * Require that T was given with mut, so what a ptr[T] points to can be changed.
 *
 * @param T The generic parameter to check, as the generic was given it.
 */
Mutable #constraint :: fn(T: type) {
    require_mutable(T)
}

/**
 * Require that C is an array, view or dynamic array of E.
 *
 * @param C The collection type to check.
 * @param E The type its elements have to be.
 */
ViewOf #constraint :: fn(C: type, E: type) {
    require_view(C, E)
}

/**
 * Require a count or capacity that holds something.
 *
 * @param count The count, a compile-time value; 0 doesn't meet it.
 */
AtLeastOne #constraint :: fn(count: usize) {
    require(count > 0, "% holds nothing; it needs to be at least 1", count)
}

/**
 * Require a capacity that's a power of two, like a ring buffer's, so wrapping is a mask.
 *
 * @param count The capacity, a compile-time value; 0 doesn't meet it, and 1 does.
 */
PowerOfTwo #constraint :: fn(count: usize) {
    require(count > 0 && count & (count - 1) == 0, "% isn't a power of two", count)
}

/**
 * Whether constraints are satisfied, given as a constraint expression, like
 * compiler.satisfies(Hashable(Point) && Ordered(Point)): a constant, worked out where the checker
 * works out constants, like #if and #assert, without reporting anything. In a generic, with its
 * parameters, so each instance can choose:
 *
 *     #if compiler.satisfies(Integer(T)) { ... }
 *
 * The constraint expression is given as its argument, though the declaration shows none.
 *
 * @return True when every constraint the expression needs is met; false otherwise, with nothing reported.
 */
satisfies : fn() -> bool : ---
