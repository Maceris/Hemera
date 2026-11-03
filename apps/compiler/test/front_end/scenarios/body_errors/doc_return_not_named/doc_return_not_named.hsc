package doc_return_not_named

/**
 * Read some.
 *
 * @return amount How many.
 */
read :: fn() -> (count : usize, done : bool) {
    return 0, true
}

main :: fn() -> int {
    return 0
}
