package compile_time_assert

size :: fn() -> int {
    return 16
}

SIZE :: size()

#assert SIZE == 17
