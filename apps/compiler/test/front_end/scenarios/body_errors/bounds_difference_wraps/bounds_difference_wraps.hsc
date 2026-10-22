package bounds_difference_wraps

// count - at wraps for an at past count, so the check proves nothing about at
main :: fn(bytes: u8[], at: usize) -> u8 {
    if bytes.count - at >= 4 {
        return bytes[at + 3]
    }
    return 0
}
