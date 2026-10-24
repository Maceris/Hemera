package mut_changes_nothing

// mut on a value held as itself changes nothing
add :: fn(n: mut int) -> int {
    return n + 1
}

main :: fn() -> int {
    return add(1)
}
