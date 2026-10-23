package quote_unspliceable

import compiler from "base"

Point :: struct {
    x : int,
}

// A struct is neither code, a type nor a literal
quote :: fn() -> compiler.Code {
    p :: Point.{x = 1}
    return #code(#insert p)
}

main :: fn() {
    _ = quote
}
