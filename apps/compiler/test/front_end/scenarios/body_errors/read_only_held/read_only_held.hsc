package read_only_held

// T is held in place, not only pointed to, so mut T doesn't become T
Held :: struct[T] {
    value : T,
}

main :: fn() {
    held := Held[mut int].{value = 1}
    plain : Held[int] = held
}
