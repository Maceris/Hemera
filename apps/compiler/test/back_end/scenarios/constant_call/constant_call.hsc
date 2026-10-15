/*
 * A constant whose value comes from calling a function, which needs compile-time execution: code
 * generation reports it instead of generating the call.
 */
package constant_call

Pair :: struct {
    a : u64,
    b : u64,
}

make_pair :: fn(a, b: u64) -> Pair {
    return Pair.{a, b}
}

PAIR : Pair : make_pair(1, 2)

main :: fn() -> int {
    return cast[int](PAIR.a)
}
