package break_too_far

f :: fn() {
    for i in 0..<3 {
        // Only one loop to leave
        break 2
    }
}
