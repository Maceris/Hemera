package scoped_dynamic_local

// A dynamic array's elements are on the heap, where a #scoped struct can't be
Parser :: struct #scoped { input : u8[] }

main :: fn() {
    parsers : Parser[..]
}
