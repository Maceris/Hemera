package bounds_union_overlap

// A #union's fields share their bytes: storing one changes what the other is
Overlaid :: struct #union {
    count : usize,
    bytes : u8[8],
}

overlaid :: fn(value: ptr[mut Overlaid], items: int[4]) -> int {
    if value.count >= 4 {
        return 0
    }
    value.bytes[7] = 255
    return items[value.count]
}
