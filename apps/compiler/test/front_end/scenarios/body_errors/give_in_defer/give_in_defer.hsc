package give_in_defer

// What's deferred runs as the block is left, so it can't give the block's value
main :: fn() -> int {
    return compute[int] {
        defer {
            give 2
        }
        give 1
    }
}
