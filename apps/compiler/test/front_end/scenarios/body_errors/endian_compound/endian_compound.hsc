package endian_compound

// u32be has no arithmetic of its own
main :: fn(length: ptr[mut u32be]) -> int {
    length^ += 1
    return 0
}
