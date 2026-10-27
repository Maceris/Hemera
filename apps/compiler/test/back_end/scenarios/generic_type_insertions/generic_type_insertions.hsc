package generic_type_insertions

import compiler from "base"

/*
 * #insert in a generic type (docs/compilation.md, Code Values): each instance inserts into a tree of its own, so
 * a field inserted can use the type's parameter, among a struct's fields and a union's variants. main returns 42
 * if every instance has what was inserted.
 */

counted :: fn() -> compiler.Code {
    return #code fields {
        count : int,
    }
}

typed :: fn() -> compiler.Code {
    return #code fields {
        value : T,
    }
}

shapes :: fn() -> compiler.Code {
    return #code variants {
        Empty,
    }
}

Holder :: struct[T] {
    #insert counted(),
    #insert typed(),
}

Maybe :: union[T] {
    Some(T),
    #insert shapes(),
}

main :: fn() -> int {
    h := Holder[int].{ count = 4, value = 30 }
    f := Holder[u8].{ count = 1, value = 7 }
    m := Maybe[int].Some(1)
    e := Maybe[int].Empty
    extra := match e {
        case Some(x) => x
        case Empty => 0
    }
    some := match m {
        case Some(x) => x
        case Empty => 50
    }
    return h.count + h.value + cast[int](f.value) + f.count + extra + some - 1
}
