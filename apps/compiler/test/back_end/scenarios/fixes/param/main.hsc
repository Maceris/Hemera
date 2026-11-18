// For the fix test: a @param naming no parameter, fixed by naming the one parameter without one.
package main

/**
 * Doubles a value.
 *
 * @param valu What's doubled.
 * @return Twice it.
 */
twice :: fn(value : int) -> int {
    return value * 2
}

main :: fn() -> int {
    return twice(0)
}
