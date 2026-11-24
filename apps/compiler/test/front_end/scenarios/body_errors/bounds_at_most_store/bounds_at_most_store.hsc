package bounds_at_most_store

Kept :: struct {
    name : u8[32],
    count #at_most(name.count) : usize,
}

// What it's given isn't proven at most 32
store :: fn(kept: ptr[mut Kept], given: u8[]) {
    kept.count = given.count
}
