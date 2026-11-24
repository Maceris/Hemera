package at_most_view

// A view's count can change, so it can't bound a field
Listed :: struct {
    items : u8[],
    count #at_most(items.count) : usize,
}

main :: fn() -> int {
    listed := Listed.{}
    return cast[int](listed.count)
}
