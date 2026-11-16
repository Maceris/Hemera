package main

import shapes from "../shapes"

LIMIT :: 3

first :: fn[T](a : T, b : T) -> T {
    return a
}

main :: fn() -> int {
    start := shapes.Point.{ x = 1, y = 2 }
    end := shapes.moved(start, LIMIT)
    small := first(1, 2)
    word := first("a", "b")
    return end.x + small + helper()
}
