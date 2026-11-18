// For the fix test: a match that leaves two of an enum's members out, fixed by an arm for each.
package main

Color :: enum {
    Red,
    Green,
    Blue,
}

counted :: fn(color : Color) -> int {
    count := 0
    match color {
        case .Red => {
            count = 1
        }
    }
    return count
}

main :: fn() -> int {
    return counted(.Red) - 1
}
