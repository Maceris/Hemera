package format_parameters

// A #format(...) parameter's string written in place, checked against the parameters it names (docs/format_strings.md)
is_less :: fn(actual: int, bound: int, message #format(actual, bound) : string) -> bool {
    return actual < bound
}

// #format naming something that isn't another parameter
names_nothing :: fn(actual: int, message #format(missing) : string) {}

// #format on a parameter that isn't a string
not_a_string :: fn(actual: int, count #format(actual) : int) {}

main :: fn() {
    _ = is_less(1, 2, "fine: %1{08x} is under %2, 100%%")
    _ = is_less(1, 2, "too many: %3")
    _ = is_less(1, 2, "precision int: %1{.2}")
    names_nothing(1, "")
    not_a_string(1, 2)
}
