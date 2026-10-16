package stack_escaping_argument

// A view of a stack buffer passed to a parameter that keeps it
Registry :: struct { first : string }

register :: fn(registry: ptr[mut Registry], name #escaping : string) {
    registry.first = name
}

main :: fn(registry: ptr[mut Registry]) {
    name_bytes : u8[32]
    register(registry, string_of(&name_bytes[0], 4))
}
