package functions

answer :: fn() {
    {
        defer cleanup()
        return void
    }
    return void
}

// The return is the third statement, so indexing its values by the statement index would overrun
values :: fn() -> int {
    first()
    second()
    return 1
}

trap : fn() : ---
