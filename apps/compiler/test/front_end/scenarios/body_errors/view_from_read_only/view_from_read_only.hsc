package view_from_read_only

fill :: fn(values: mut int[]) {
    for value, i in values {
        values[i] = 1
    }
}

// A parameter is a copy that can't be changed, so it can't become a mut view
fill_copy :: fn(numbers: int[4]) {
    fill(numbers)
}

main :: fn() -> int {
    numbers : int[4]
    fill_copy(numbers)
    return 0
}
