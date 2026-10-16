package stack_scoped_store

// Through a pointer to a #scoped struct, only what lives as long as the struct can be stored
Parser :: struct #scoped { input : u8[] }

reset :: fn(parser: ptr[mut Parser], other: u8[]) {
    parser.input = other
}
