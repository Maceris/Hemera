package insert_at_top_level

import compiler from "base"

make :: fn() -> compiler.Code {
    return #code(1)
}

// At the top level, which comes later
#insert make()

main :: fn() {
}
