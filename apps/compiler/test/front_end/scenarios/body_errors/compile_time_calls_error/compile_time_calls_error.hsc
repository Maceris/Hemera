package compile_time_calls_error

// broken's error is the only one: what needed SIZE fails without reporting it again
broken :: fn() -> int {
    return "not a number"
}

SIZE :: broken()

buffer_of :: fn() -> int {
    buffer : u8[SIZE]
    return 0
}
