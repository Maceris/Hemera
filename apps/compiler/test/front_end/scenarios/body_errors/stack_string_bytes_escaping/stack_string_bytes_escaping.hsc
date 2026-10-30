package stack_string_bytes_escaping

// A string's bytes are its memory: string_bytes of a string on the stack can't outlive the stack
name_bytes :: fn() -> u8[] {
    storage : u8[4]
    return string_bytes(string_of(&storage[0], 4))
}

main :: fn() {
    name_bytes()
}
