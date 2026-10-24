package nested_generic

main :: fn() -> int {
    same :: fn[T](value: T) -> T {
        return value
    }
    return same(1)
}
