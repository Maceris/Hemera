package mut_argument_read_only

// Given without mut, so its ptr[T] only reads
Box :: struct[T] {
    value : ptr[T],
}

main :: fn() {
    number := 1
    box :: Box[int].{value = &number}
    box.value^ = 2
}
