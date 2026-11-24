package bounds_call_writes

Counted :: struct {
    items : int[8],
    count : usize,
}

// Writes through what it's given
grow :: fn(counted: ptr[mut Counted]) {
    counted.count += 100
}

// Writes nothing itself, but calls what does
grows :: fn(counted: ptr[mut Counted]) {
    grow(counted)
}

// The call may have changed counted.count, so it's no longer known in bounds
after :: fn(counted: ptr[mut Counted]) -> int {
    if counted.count >= counted.items.count {
        return 0
    }
    grows(counted)
    return counted.items[counted.count]
}
