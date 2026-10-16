package stack_return_local

// Returning a pointer into this function's own frame
main :: fn() -> ptr[int] {
    x := 5
    return &x
}
