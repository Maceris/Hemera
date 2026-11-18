// For the fix test: a local and a field misspelled, each fixed by the name spelled almost the same.
package main

Size :: struct {
    width : int,
    height : int,
}

main :: fn() -> int {
    size := Size.{width = 2, height = 3}
    total := size.widht
    return totl - 2
}
