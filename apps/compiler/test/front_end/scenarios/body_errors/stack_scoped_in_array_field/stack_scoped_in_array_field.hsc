package stack_scoped_in_array_field

// Nor in an array a struct holds: a dynamic array's elements are on the heap
Parser :: struct #scoped { input : u8[] }

Parsers :: struct {
    all : Parser[..],
}

main :: fn() {
    parsers : Parsers
}
