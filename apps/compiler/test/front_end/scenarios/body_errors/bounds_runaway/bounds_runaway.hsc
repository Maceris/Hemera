package bounds_runaway

// i goes up by two, past the check
main :: fn(values: int[]) -> int {
    i : usize = 0
    total := 0
    loop {
        total += values[i + 1]
        i += 2
    }
    while i < values.count
    return total
}
