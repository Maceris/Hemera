package insert_undeclared_in_code

import compiler from "base"

// The code names something that isn't declared where it's put
broken :: fn() -> compiler.Code {
    return #code(missing + 1)
}

main :: fn() -> int {
    return #insert broken()
}
