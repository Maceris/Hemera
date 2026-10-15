package assign_through_pointer

Point :: struct {
    x : int,
    y : int,
}

f :: fn(p: ptr[Point]) {
    // ptr[Point] can only read what it points to
    p.x = 1
}
