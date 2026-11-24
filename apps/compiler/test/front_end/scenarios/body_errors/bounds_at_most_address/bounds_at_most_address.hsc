package bounds_at_most_address

Kept :: struct {
    name : u8[32],
    count #at_most(name.count) : usize,
}

// What's stored through the pointer couldn't be proven
address :: fn(kept: ptr[mut Kept]) -> ptr[mut usize] {
    return &kept.count
}
