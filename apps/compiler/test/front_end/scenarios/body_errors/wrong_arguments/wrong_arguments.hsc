package wrong_arguments

add :: fn(a, b: int) -> int {
    return a + b
}

f :: fn() -> int {
    return add(1)
}
