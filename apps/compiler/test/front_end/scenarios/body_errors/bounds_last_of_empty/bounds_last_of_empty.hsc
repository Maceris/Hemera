package bounds_last_of_empty

// The last element of what may be empty
main :: fn(values: int[]) -> int {
    return values[values.count - 1]
}
