package insert_wrong_members

import compiler from "base"

fields :: fn() -> compiler.Code {
    return #code fields {
        x : int,
    }
}

// Fields, among an enum's members
Color :: enum {
    #insert fields(),
    Blue,
}

main :: fn() -> int {
    return cast[int](Color.Blue)
}
