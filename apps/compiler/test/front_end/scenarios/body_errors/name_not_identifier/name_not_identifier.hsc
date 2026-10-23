package name_not_identifier

import compiler from "base"

// A name is one identifier, never other code
bad :: fn() -> compiler.Code {
    return compiler.name("a + b")
}

main :: fn() -> int {
    return #insert bad()
}
