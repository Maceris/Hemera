package macro_call_not_macro

doubled :: fn(n: int) -> int {
    return n * 2
}

// Only a #macro function is called with !
main :: fn() -> int {
    return doubled!(21)
}
