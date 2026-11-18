package main

import compiler from "base:compiler"

// A macro, and a function that uses it
add #macro :: fn(target: compiler.Code, amount: int) -> compiler.Code {
    return #code {
        #insert target += #insert amount
    }
}

counted :: fn(by : int) -> int {
    STEP :: 2
    total := STEP + by
    add!(total, 1)
    return total
}

Length :: alias int
Meters :: distinct alias int

scaled :: fn(value : int, factor := 3, rest : int...) -> int {
    return value * factor
}
