package stack_parameter_address

// A string parameter holds what the caller passed, which may be on its stack
keep :: fn(where: ptr[string]) {}

main :: fn(name: string) {
    keep(&name)
}
