package nested_uses_outer_local

// A nested function sees the package's names, not the function's locals
main :: fn() -> int {
    x := 5
    helper :: fn() -> int {
        return x
    }
    return helper()
}
