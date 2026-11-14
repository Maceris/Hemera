package macro_local_hidden

import compiler from "base:compiler"

// What a macro's code declares is its own: the caller doesn't see hidden
declare #macro :: fn() -> compiler.Code {
    return #code {
        hidden := 1
    }
}

main :: fn() -> int {
    declare!()
    return hidden
}
