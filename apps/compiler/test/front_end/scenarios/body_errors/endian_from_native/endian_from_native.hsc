package endian_from_native

// A native value becomes big-endian only with a cast, so the swap shows
main :: fn(length: ptr[mut u32be], native: u32) -> int {
    length^ = native
    return 0
}
