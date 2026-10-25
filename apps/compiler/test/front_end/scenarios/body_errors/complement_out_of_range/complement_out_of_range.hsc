package complement_out_of_range

// ~0x1ff in a u8 needs 0x1ff to be one, and it isn't
main :: fn() -> u8 {
    y : u8 = 3
    return y & ~0x1ff
}
