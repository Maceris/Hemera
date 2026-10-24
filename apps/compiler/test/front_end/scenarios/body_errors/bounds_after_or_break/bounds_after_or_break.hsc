package bounds_after_or_break

next :: fn(i: usize) -> usize? {
    return if i < 3 { i } else { null }
}

// The loop ends only through or_break, which leaves with nothing known about i
main :: fn(values: int[]) -> int {
    i : usize = 0
    loop {
        i = next(i) or_break
        i += 1
    }
    return values[i]
}
