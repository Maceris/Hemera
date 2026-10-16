package stack_keeps_parameter

// Keeping a parameter needs #escaping
Registry :: struct { first : string }

register :: fn(registry: ptr[mut Registry], name: string) {
    registry.first = name
}
