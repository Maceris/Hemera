package dynamic_array_parameter

// A dynamic array given as a parameter is the caller's, and its elements change only through a pointer to it
clear :: fn(values: int[..]) {
    for value, i in values {
        values[i] = 0
    }
}

main :: fn() -> int {
    numbers : int[..]
    clear(numbers)
    return 0
}
