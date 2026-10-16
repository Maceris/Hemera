package generic_value_variable

// A value in a generic list must be a constant
filled :: fn[count: usize](value: u8) -> u8[count] {
    result : u8[count]
    return result
}

main :: fn() {
    n : usize = 4
    bytes :: filled[n](cast[u8](1))
}
