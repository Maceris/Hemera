package bounds_at_most_grows

Kept :: struct {
    name : u8[32],
    count #at_most(name.count) : usize,
}

// One more than 32, unless it's checked first
grow :: fn(kept: ptr[mut Kept]) {
    kept.count += 1
}
