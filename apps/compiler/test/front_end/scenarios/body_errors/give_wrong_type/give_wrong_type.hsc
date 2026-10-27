package give_wrong_type

// What's given is the block's type
main :: fn() -> int {
    return compute[int] {
        give "three"
    }
}
