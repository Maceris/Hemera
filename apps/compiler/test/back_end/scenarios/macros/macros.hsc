/*
 * Macros (docs/compilation.md, Macros): #macro functions called as name!(arguments), whose code is put in
 * place hygienically. The locals a macro's code declares are its own, and its names are looked up where
 * the macro was written (helpers), while the code it's given stays the caller's. main returns 42 if every
 * expansion did what it should.
 */
package macros_test

import compiler from "base"
import helpers from "helpers"

// Not the doubled the macros in helpers call
doubled :: fn(n: int) -> int {
    return n * 100
}

// A macro in the caller's own file
negated #macro :: fn(x: compiler.Code) -> compiler.Code {
    return #code(0 - #insert x)
}

main :: fn() -> int {
    temporary := 5
    a := 1
    b := 30
    helpers.swap!(a, b)
    if a != 30 || b != 1 || temporary != 5 {
        return 1
    }
    // The caller's temporary, swapped with the macro's own beside it
    helpers.swap!(temporary, b)
    if temporary != 1 || b != 5 {
        return 2
    }
    if helpers.twice_doubled!(3) != 12 {
        return 3
    }
    if helpers.quadrupled!(a) != 240 {
        return 4
    }
    if negated!(doubled(1)) != -100 {
        return 5
    }
    total := 0
    helpers.add!(total, 40)
    helpers.add!(total, 2)
    return total
}
