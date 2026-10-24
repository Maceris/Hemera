package view_read_only

// A view without mut only reads its elements
clear :: fn(values: int[]) {
    for value, i in values {
        values[i] = 0
    }
}

main :: fn() -> int {
    numbers : int[2]
    clear(numbers)
    return numbers[0]
}
