// For the fix test: std's math, used without an import, fixed by importing it.
package main

import runtime from "base:runtime"

main :: fn() -> int {
    if math.PI > 3.0 {
        return 0
    }
    return 1
}
