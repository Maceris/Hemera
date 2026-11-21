package main

value :: fn() -> u64 {
    return 7
}

/*
 * An untyped constant in one branch of an if or arm of a match takes the type another gives, wherever it's written:
 * first, last or among else ifs. Only untyped constants: none of these is an error.
 */
main :: fn() -> int {
    flag := true
    which := 1
    first : u64 = if flag { 0 } else { value() }
    last : u64 = if flag { value() } else { 0 }
    inferred :: if flag { 0 } else { value() }
    chained :: if flag { 0 } else if which == 2 { 1 } else { value() }
    matched :: match which {
        case 0 => 0
        case 1 => 2
        case _ => value()
    }
    // Untyped alone, they're the widest's type: f64 here
    widest :: if flag { 0 } else { 1.5 }
    sum : u64 = first + last + inferred + chained + matched
    return cast[int](sum) + cast[int](widest)
}
