package insert_top_level_expression

import compiler from "base"

make :: fn() -> compiler.Code {
    return #code(1)
}

// An expression, where declarations go
#insert make()

main :: fn() {
}
