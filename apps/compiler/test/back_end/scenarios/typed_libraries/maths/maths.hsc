package maths

import runtime from "base"

/*
 * A typed library's package: its #export functions are its interface, called through the library by programs that
 * import this package. A generic function isn't exported: a program instantiates it, as it does any other.
 */

add #export :: fn(a: int, b: int) -> int {
    return a + b
}

// Takes the caller's context, and allocates with it
repeat #export :: fn(text: string, times: int) -> string {
    bytes : u8[..]
    for i in 0..<times {
        for byte in view_of(cast[ptr[u8]](text.data), text.count) {
            runtime.array_add(&bytes, byte)
        }
    }
    return string_of(cast[ptr[u8]](bytes.data), bytes.count)
}

// A result through a pointer, as anything over two registers is
Pair :: struct {
    low : int,
    high : int,
    sum : int,
}

ordered #export :: fn(a: int, b: int) -> Pair {
    return if a < b { Pair.{low = a, high = b, sum = a + b} } else { Pair.{low = b, high = a, sum = a + b} }
}

twice :: fn[T](value: T) -> T {
    return value + value
}
