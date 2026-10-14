package struct_cycle

A :: struct {
    b : B,
}

B :: struct {
    a : A,
}
