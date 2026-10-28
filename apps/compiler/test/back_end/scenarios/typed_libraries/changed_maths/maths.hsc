package maths

/*
 * The maths library built again with add's type changed, i32s where it had ints, under the same name: a program built
 * against the first refuses it when it starts, naming add, rather than calling it.
 */

add #export :: fn(a: i32, b: i32) -> i32 {
    return a + b
}

repeat #export :: fn(text: string, times: int) -> string {
    return text
}

Pair :: struct {
    low : int,
    high : int,
    sum : int,
}

ordered #export :: fn(a: int, b: int) -> Pair {
    return Pair.{low = a, high = b, sum = a + b}
}
