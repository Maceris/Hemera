package using_not_struct

// using takes a struct, or a pointer to something, whose members become the struct's
Counter :: struct {
    using count : int,
}

main :: fn() {
    counter : Counter
}
