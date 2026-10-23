package insert_needs_itself

import compiler from "base"

make :: fn(count: int) -> compiler.Code {
    return #code {
        LIMIT :: 4
    }
}

// What it runs needs LIMIT, which only what it inserts declares
#insert make(LIMIT)

main :: fn() -> int {
    return LIMIT
}
