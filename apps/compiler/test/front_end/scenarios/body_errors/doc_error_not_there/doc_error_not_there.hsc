package doc_error_not_there

Problem :: enum {
    Missing,
}

/**
 * Finds it.
 * @error Gone it went
 */
find :: fn() -> Result[int, Problem] {
    return .Ok(1)
}

main :: fn() -> int {
    return 0
}
