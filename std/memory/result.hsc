package memory

// Whether result holds an error.
is_error :: fn[T, E](result: Result[T, E]) -> bool {
    return match result {
        case Error(_) => true
        case _ => false
    }
}

// Whether result holds a value.
is_ok :: fn[T, E](result: Result[T, E]) -> bool {
    return match result {
        case Ok(_) => true
        case _ => false
    }
}
