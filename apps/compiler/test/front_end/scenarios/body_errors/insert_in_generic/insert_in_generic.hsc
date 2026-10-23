package insert_in_generic

import compiler from "base"

one :: fn() -> compiler.Code {
    return #code(1)
}

// A generic's instances share its body, which #insert can't change for one yet
same :: fn[T](value: T) -> int {
    return #insert one()
}

main :: fn() -> int {
    return same(2)
}
