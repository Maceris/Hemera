package no_context_generic

count_of :: fn[T](values: T[]) -> usize {
    return values.count
}

// A generic function needs a context like any other
peek #no_context :: fn(values: int[]) -> usize {
    return count_of(values)
}

main :: fn() -> int {
    numbers : int[1]
    return cast[int](peek(numbers))
}
