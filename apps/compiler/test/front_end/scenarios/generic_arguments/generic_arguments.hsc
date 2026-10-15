package generic_arguments

Pair :: struct[A, B] {
    first : A,
    second : B,
}

// Pair takes two
Holder :: struct {
    pair : Pair[int],
}
