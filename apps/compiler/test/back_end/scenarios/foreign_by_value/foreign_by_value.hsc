/*
 * A #foreign function taking a struct by value, which can't be generated yet: the error names this file, though the
 * foreign function's code is made apart from any function's body. Never run.
 */
package foreign_by_value

KERNEL32 :: #library("kernel32")

Pair :: struct {
    a : u64,
    b : u64,
}

takes_pair #foreign(KERNEL32) : fn(pair: Pair) -> u32 : ---

main :: fn() -> int {
    return cast[int](takes_pair(Pair.{a = 1, b = 2}))
}
