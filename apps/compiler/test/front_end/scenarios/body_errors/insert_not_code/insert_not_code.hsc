package insert_not_code

five :: fn() -> int {
    return 5
}

// #insert takes a compiler.Code, not an int
main :: fn() -> int {
    return #insert five()
}
