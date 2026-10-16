package bounds_wraps

// offset + 4 wraps for an offset near the top, so the check proves nothing
main :: fn(bytes: u8[], offset: usize) -> u8 {
    if offset + 4 <= bytes.count {
        return bytes[offset + 3]
    }
    return 0
}
