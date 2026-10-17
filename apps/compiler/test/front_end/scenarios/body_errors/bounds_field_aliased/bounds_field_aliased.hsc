package bounds_field_aliased

Ring :: struct {
    items : int[8],
    count : usize,
}

// other may be ring, so storing through it may change ring.count
aliased :: fn(ring: ptr[mut Ring], other: ptr[mut Ring]) -> int {
    if ring.count >= 8 {
        return 0
    }
    other.count = 100
    return ring.items[ring.count]
}
