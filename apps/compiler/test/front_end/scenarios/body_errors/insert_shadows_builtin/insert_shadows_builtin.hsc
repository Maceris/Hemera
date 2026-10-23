package insert_shadows_builtin

import compiler from "base"

make :: fn() -> compiler.Code {
    return #code {
        size_of :: fn(x: int) -> int {
            return x
        }
    }
}

// main uses the builtin, and the package declares one of its own too
#insert make()

main :: fn() -> int {
    return cast[int](size_of(u32))
}
