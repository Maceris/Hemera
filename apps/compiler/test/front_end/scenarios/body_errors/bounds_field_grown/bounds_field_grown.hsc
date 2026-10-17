package bounds_field_grown

Ring :: struct {
    items : int[8],
    count : usize,
}

// Counted up from below 8, the count can be 8, past the last item
grown :: fn(ring: ptr[mut Ring]) -> int {
    if ring.count >= 8 {
        return 0
    }
    ring.count += 1
    return ring.items[ring.count]
}
