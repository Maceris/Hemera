package bounds_at_most_literal

Kept :: struct {
    name : u8[32],
    count #at_most(name.count) : usize,
}

made :: fn() -> Kept {
    return Kept.{count = 40}
}
