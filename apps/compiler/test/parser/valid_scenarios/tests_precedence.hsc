package valid_scenarios

// is_none, is_some, is_ok and is_error bind tighter than && and ||, and looser than a comparison (docs/operators.md)
tests_precedence :: fn(a: Result[int, int], b: Result[int, int], x: int?, y: int?) -> bool {
    both :: a is_ok && b is_error
    either :: x is_none || y is_some
    mixed :: a is_error || x is_some && y is_none
    nested :: (x is_none) is_none
    compared :: (a == b) is_ok
    if a is_ok && x is_some {
        return !(b is_error || y is_none)
    }
    return both && either || mixed
}
