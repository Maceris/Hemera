// A target whose fill function has a frame larger than its build's max_frame_size of 16 KiB.
package framed

fill :: fn(value: u8) -> u8 {
    buffer : u8[65536]
    for index in 0..<65536 {
        buffer[index] = value
    }
    return buffer[100]
}

main :: fn() -> int {
    return cast[int](fill(42))
}
