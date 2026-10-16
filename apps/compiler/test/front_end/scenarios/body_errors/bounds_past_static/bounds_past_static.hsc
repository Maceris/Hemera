package bounds_past_static

// Provably past the end of a static array
main :: fn() -> int {
    fixed : int[5]
    over :: 5
    return fixed[over]
}
