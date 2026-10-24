package view_loses_read_only

fill :: fn(values: mut int[]) {
    for value, i in values {
        values[i] = 1
    }
}

// A view that only reads can't be given where one that writes is wanted
pass :: fn(values: int[]) {
    fill(values)
}

main :: fn() -> int {
    numbers : int[4]
    pass(numbers)
    return 0
}
