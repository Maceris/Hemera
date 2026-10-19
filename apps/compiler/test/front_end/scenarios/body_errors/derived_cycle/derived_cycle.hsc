package derived_cycle

// A derived parameter can't be worked out from itself
looped :: fn[A = ptr[A]](value: int) -> int {
    return value
}

main :: fn() {
    _ = looped(1)
}
