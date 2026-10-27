package stack_returned_through_call

// first gives back a pointer into what it's given, so what it gives, given a view of the stack, can't be returned
first :: fn(values: int[]) -> ptr[int]? {
    for i in 0..<values.count {
        return &values[i]
    }
    return null
}

main :: fn() -> ptr[int]? {
    values : int[4]
    return first(values[0..<4])
}
