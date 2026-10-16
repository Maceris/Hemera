package generic_value_kind

// capacity is a usize, not a boolean
Ring :: struct[T, capacity: usize] {
    items : T[capacity],
}

main :: fn() {
    ring : Ring[u8, true]
}
