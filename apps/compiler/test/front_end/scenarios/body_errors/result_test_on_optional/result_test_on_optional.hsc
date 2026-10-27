package result_test_on_optional

// is_ok and is_error are a result's, as is_some and is_none are an optional's
main :: fn() -> int {
    maybe : int? = 3
    if maybe is_ok {
        return 1
    }
    return 0
}
