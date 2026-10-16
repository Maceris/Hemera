package compile_time_cycle

// SIZE comes from running needs_size, whose body can't be checked until SIZE is known
SIZE :: needs_size()

needs_size :: fn() -> int {
    buffer : u8[SIZE]
    return 1
}
