package null_pointer

// Only rawptr and optionals take null: a ptr[T] always points at something
main :: fn() {
    pointer : ptr[int] = null
}
