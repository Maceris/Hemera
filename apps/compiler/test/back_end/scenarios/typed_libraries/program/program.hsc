package program

import maths from "../maths"

/*
 * Calls a typed library's exports through the library, which the runtime loads and checks before main. main returns
 * 42 if each gives what it should.
 */

main :: fn() -> int {
    if maths.add(40, 2) != 42 {
        return 1
    }
    text :: maths.repeat("ab", 3)
    if text != "ababab" {
        return 2
    }
    pair :: maths.ordered(9, 4)
    if pair.low != 4 || pair.high != 9 || pair.sum != 13 {
        return 3
    }
    // A function value of an export calls through the library too
    adds := maths.add
    if adds(1, 2) != 3 || maths.twice(21) != 42 {
        return 4
    }
    return 42
}
