package bounds_deferred_write

/*
 * A defer assigns count as each turn of the loop ends, continue included, so after the loop it's 4, not the 0 it was
 * set to: the return isn't taken, and the index after it, which nothing proves, is reached and has to be reported
 */
main :: fn(values: int[]) -> int {
    count := 0
    for i in 0..<4 {
        defer count += 1
        if i == 1 {
            continue
        }
    }
    if count == 0 {
        return 0
    }
    return values[5]
}
