// A target of the build package: main returns the answer the build's settings give it.
package app

import compiler from "base"

ANSWER :: #run compiler.target_setting("answer", default = "0")

Mode :: enum {
    Slow,
    Fast,
}

// For the build's check: constant defaults, which reflection gives the values of, and one that's the caller's
scale :: fn(value: int, factor := 3, label := "scaled", mode := Mode.Fast, where := #caller_location) -> int {
    return value * factor
}

// For the build's check: generic, so main's call is to an instance, pick[int]
pick :: fn[T](first: T, second: T) -> T {
    return first
}

main :: fn() -> int {
    if ANSWER == "42" && scale(2) == 6 && pick(7, 8) == 7 {
        return 42
    }
    return 1
}
