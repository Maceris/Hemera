// A target built several times at once: main returns the answer its target's settings give it.
package app

import compiler from "base"

ANSWER :: #run compiler.target_setting("answer", default = "0")

main :: fn() -> int {
    value := 0
    for character in ANSWER {
        value = value * 10 + (cast[int](character) - cast[int]('0'))
    }
    return value
}
