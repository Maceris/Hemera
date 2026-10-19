package constraint_unknown

// A where clause can only name #constraint functions
helper :: fn(T: type) {}

pick :: fn[T](value: T) -> T where helper(T) {
    return value
}

main :: fn() {
    _ = pick(1)
}
