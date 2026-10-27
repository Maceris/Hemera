package bounds_sum_changed

// What was known about at + i is about the i it was computed with, so changing i forgets it
mark :: fn(into: mut u8[], at: usize, i: usize) {
    j := i
    if at + j < into.count {
        j += 1
        into[at + j] = 1
    }
}

main :: fn() {
    bytes : u8[4]
    mark(bytes[0..<4], 1, 1)
}
