package function_argument_wrong

// A function given to a generic takes and gives what its parameter says
Table :: struct[K, hash: fn(key: K) -> u64] {
    last : u64,
}

hash_narrow :: fn(key: int) -> u32 {
    return 0
}

main :: fn() {
    table : Table[int, hash_narrow]
}
