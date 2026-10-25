package local_type_generic

// A generic type declared inside a function isn't supported yet
main :: fn() -> int {
    Pair :: struct[T] {
        a : T,
    }
    return 0
}
