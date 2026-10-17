package generic_value_given_type

// capacity is a value, so it takes one, not a type
Ring :: struct[T, capacity: usize] {
    items : T[capacity],
}

main :: fn() {
    ring : Ring[u8, u8]
}
