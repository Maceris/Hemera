package insert_in_generic_type

import compiler from "base"

fields :: fn() -> compiler.Code {
    return #code fields {
        extra : int,
    }
}

// A generic type's instances share its fields
Box :: struct[T] {
    value : T,
    #insert fields(),
}

main :: fn() -> int {
    box := Box[int].{value = 1}
    return box.value
}
