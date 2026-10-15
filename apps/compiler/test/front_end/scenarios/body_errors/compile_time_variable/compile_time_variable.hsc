package compile_time_variable

buffer :: fn[count](count: usize) -> u8[count] {
    result : u8[count]
    return result
}

f :: fn(n: usize) {
    // count is a compile-time parameter, so n would have to be a constant
    bytes := buffer(n)
}
