// Macros written in another package, whose code sees this package's names, which a caller doesn't.
package helpers

import compiler from "base"

doubled :: fn(n: int) -> int {
    return n * 2
}

// temporary is the expansion's own, apart from any the caller has, even one it passes in
swap #macro :: fn(a: compiler.Code, b: compiler.Code) -> compiler.Code {
    return #code {
        temporary := #insert a
        #insert a = #insert b
        #insert b = temporary
    }
}

twice_doubled #macro :: fn(x: compiler.Code) -> compiler.Code {
    return #code(doubled(#insert x) + doubled(#insert x))
}

// A macro whose code calls another
quadrupled #macro :: fn(x: compiler.Code) -> compiler.Code {
    return #code(twice_doubled!(#insert x) * 2)
}

// An argument that isn't code is a value, given when the macro runs
add #macro :: fn(target: compiler.Code, amount: int) -> compiler.Code {
    return #code {
        #insert target += #insert amount
    }
}
