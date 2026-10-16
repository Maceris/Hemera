package stack_named_result

// Returning a named result that points into this frame
main :: fn() -> (result: ptr[int]) {
    x := 5
    result = &x
    return result
}
